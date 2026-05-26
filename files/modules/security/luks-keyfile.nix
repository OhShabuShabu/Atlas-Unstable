{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: LUKS KEYFILE GENERATION & TPM SEALING
# INFO: ============================================================================
# INFO: Creates TPM-sealed LUKS keyfile for 2-factor unlock (keyfile + passphrase)
# NOTE: The TPM-sealed blob lives in /boot (unencrypted ESP, visible but useless
#       without TPM + correct PCR values).
#       The sealed blob is unsealed during initrd into a tmpfs keyfile.
#       cryptsetup reads the keyfile from initrd tmpfs before opening LUKS.
#       Post-boot, a service auto-enrolls the keyfile if no LUKS slot exists.
# WARN: TPM PCR mismatch (firmware/secureboot change) prevents unseal → passphrase fallback
# WARN: Without the TPM-sealed keyfile, passphrase-only unlock still works

let
  bootDir = "/boot";                          # EFI System Partition (unencrypted)
  sealedPriv = "${bootDir}/luks-keyfile.priv";  # TPM-sealed private blob
  sealedPub = "${bootDir}/luks-keyfile.pub";    # TPM-sealed public blob
  unsealedKeyfile = "/run/luks-keyfile";       # Unsealed in initrd tmpfs (RAM only)
  persistentKeyRaw = "/persistent/luks-keyfile-raw";  # Raw key in encrypted /persistent
  pcrSelection = "sha256:0,1,7";
  luksDevice = "/dev/disk/by-partlabel/disk-main-root";

  # INFO: Manual script to generate LUKS keyfile and seal it to TPM
  # NOTE: Run once: `sudo generate-luks-keyfile`
  #       Then (if auto-enroll fails): `sudo cryptsetup luksAddKey <device> /run/luks-keyfile-raw`
  generateScript = pkgs.writeShellScript "generate-luks-keyfile.sh" ''
    set -euo pipefail

    BOOT="${bootDir}"
    SEALED_PRIV="${sealedPriv}"
    SEALED_PUB="${sealedPub}"
    TEMP_KEY=$(mktemp)
    PCR="${pcrSelection}"
    TPM_TOOLS="${pkgs.tpm2-tools}/bin"
    RAW_OUT="${persistentKeyRaw}"

    echo "=== LUKS Keyfile Generator ==="
    echo "Creates 512-byte random keyfile, sealed to TPM PCRs: $PCR"
    echo ""

    if [ ! -e /dev/tpm0 ]; then
      echo "ERROR: /dev/tpm0 not found — TPM 2.0 required"
      exit 1
    fi

    if [ -f "$SEALED_PRIV" ]; then
      echo "WARNING: TPM sealed key already exists at $SEALED_PRIV"
      echo "Remove manually to regenerate"
      exit 0
    fi

    echo "Generating 512-byte random keyfile..."
    dd if=/dev/urandom of="$TEMP_KEY" bs=512 count=1 2>/dev/null
    chmod 0600 "$TEMP_KEY"

    echo "Sealing keyfile to TPM PCRs $PCR..."
    $TPM_TOOLS/tpm2_createprimary -C e -c /tmp/primary.ctx 2>/dev/null || true
    $TPM_TOOLS/tpm2_policypcr -l "$PCR" -L /tmp/pcr.policy 2>/dev/null
    $TPM_TOOLS/tpm2_create -C /tmp/primary.ctx \
      -L /tmp/pcr.policy \
      -i "$TEMP_KEY" \
      -u "$SEALED_PUB" -r "$SEALED_PRIV" 2>/dev/null
    chmod 0600 "$SEALED_PRIV" "$SEALED_PUB"

    # Copy raw key to /persistent (encrypted) for auto-enrollment
    cp "$TEMP_KEY" "$RAW_OUT"
    chmod 0600 "$RAW_OUT"

    # Also copy to /run for immediate manual enrollment
    cp "$TEMP_KEY" /run/luks-keyfile-raw
    chmod 0600 /run/luks-keyfile-raw
    rm -f "$TEMP_KEY" /tmp/primary.ctx /tmp/pcr.policy

    echo ""
    echo "SUCCESS! Sealed key created."
    echo "  Private blob: $SEALED_PRIV"
    echo "  Public blob:  $SEALED_PUB"
    echo "  Raw key:      $RAW_OUT"
    echo ""
    echo "Auto-enrollment will add this keyfile to LUKS on next boot."
    echo "To enroll immediately:"
    echo "  sudo cryptsetup luksAddKey ${luksDevice} /run/luks-keyfile-raw"
    echo ""
  '';

  # INFO: Initrd script — unseals TPM keyfile into RAM before LUKS unlock
  unsealScript = pkgs.writeShellScript "luks-keyfile-unseal.sh" ''
    set -euo pipefail

    OUTPUT="${unsealedKeyfile}"
    SEALED_PRIV="${sealedPriv}"
    SEALED_PUB="${sealedPub}"
    PCR="${pcrSelection}"
    TPM_TOOLS="${pkgs.tpm2-tools}/bin"

    # Skip if keyfile already exists
    [ -f "$OUTPUT" ] && exit 0

    # Check TPM availability
    if [ ! -e /dev/tpm0 ]; then
      echo "LUKS: TPM unavailable — passphrase fallback" >&2
      exit 1
    fi

    # Check sealed blobs exist
    if [ ! -f "$SEALED_PRIV" ] || [ ! -f "$SEALED_PUB" ]; then
      echo "LUKS: Sealed key not found — passphrase fallback" >&2
      exit 1
    fi

    # Create TPM primary key
    $TPM_TOOLS/tpm2_createprimary -C e -c /tmp/primary.ctx 2>/dev/null || {
      echo "LUKS: TPM createprimary failed — fallback" >&2; exit 1; }

    # Create PCR policy (must match sealing PCRs)
    $TPM_TOOLS/tpm2_policypcr -l "$PCR" -L /tmp/pcr.policy 2>/dev/null || {
      echo "LUKS: PCR policy failed — fallback" >&2; exit 1; }

    # Load the sealed key
    $TPM_TOOLS/tpm2_load -C /tmp/primary.ctx \
      -u "$SEALED_PUB" -r "$SEALED_PRIV" \
      -c /tmp/sealed.ctx 2>/dev/null || {
      echo "LUKS: TPM load FAILED (PCR mismatch) — passphrase fallback" >&2
      ${pkgs.util-linux}/bin/logger -p auth.crit -t luks-keyfile "TPM unseal FAILED — PCR mismatch"
      exit 1
    }

    # Unseal to initrd tmpfs
    $TPM_TOOLS/tpm2_unseal -c /tmp/sealed.ctx -o "$OUTPUT" 2>/dev/null || {
      echo "LUKS: TPM unseal command failed — passphrase fallback" >&2
      exit 1
    }

    chmod 0600 "$OUTPUT"
    rm -f /tmp/primary.ctx /tmp/pcr.policy /tmp/sealed.ctx
    echo "LUKS: TPM keyfile unsealed successfully"
  '';

  # INFO: Post-boot script — auto-enrolls keyfile into LUKS if no keyfile slot exists
  autoEnrollScript = pkgs.writeShellScript "luks-keyfile-auto-enroll.sh" ''
    set -euo pipefail

    LUKS_DEV="${luksDevice}"
    RAW_KEY="${persistentKeyRaw}"
    LOGGER="${pkgs.util-linux}/bin/logger"

    echo "LUKS-ENROLL: Checking keyfile enrollment..."

    # Check if sealed keyfile exists in /boot
    if [ ! -f "${sealedPriv}" ]; then
      echo "LUKS-ENROLL: No sealed keyfile — run 'sudo generate-luks-keyfile' first"
      exit 0
    fi

    # Check LUKS device exists
    if [ ! -e "$LUKS_DEV" ]; then
      echo "LUKS-ENROLL: Device $LUKS_DEV not found — skipping" >&2
      exit 1
    fi

    # Count active LUKS key slots
    ACTIVE_SLOTS=$("${pkgs.cryptsetup}/bin/cryptsetup" luksDump "$LUKS_DEV" 2>/dev/null | \
      grep -c "ENABLED" || echo 0)

    # If 2+ slots active, keyfile is already enrolled
    if [ "$ACTIVE_SLOTS" -ge 2 ]; then
      echo "LUKS-ENROLL: Keyfile already enrolled ($ACTIVE_SLOTS active slots)"
      $LOGGER -p auth.info -t luks-enroll "Keyfile already enrolled ($ACTIVE_SLOTS slots)"
      exit 0
    fi

    # Check if raw keyfile exists in /persistent
    if [ ! -f "$RAW_KEY" ]; then
      echo "LUKS-ENROLL: Raw keyfile not found at $RAW_KEY"
      echo "LUKS-ENROLL: Run 'sudo generate-luks-keyfile' then enroll manually:"
      echo "LUKS-ENROLL:   sudo cryptsetup luksAddKey $LUKS_DEV /run/luks-keyfile-raw"
      exit 1
    fi

    # Auto-enroll the keyfile into LUKS slot 1
    echo "LUKS-ENROLL: Adding keyfile to LUKS slot 1..."
    if "${pkgs.cryptsetup}/bin/cryptsetup" luksAddKey "$LUKS_DEV" "$RAW_KEY" 2>/dev/null; then
      echo "LUKS-ENROLL: Keyfile enrolled successfully"
      $LOGGER -p auth.info -t luks-enroll "Keyfile enrolled in LUKS slot 1"
    else
      echo "LUKS-ENROLL: Failed to add keyfile (wrong passphrase or device)" >&2
      $LOGGER -p auth.err -t luks-enroll "Keyfile enrollment FAILED"
      exit 1
    fi
  '';
in

{
  # INFO: Generate script in PATH for one-time manual use
  environment.systemPackages = with pkgs; [
    (pkgs.runCommandLocal "generate-luks-keyfile" {} ''
      mkdir -p $out/bin
      cp ${generateScript} $out/bin/generate-luks-keyfile
      chmod 0755 $out/bin/generate-luks-keyfile
    '')
  ];

  # INFO: Initrd service — unseals TPM key BEFORE cryptsetup runs
  boot.initrd.systemd.services."luks-keyfile-unseal" = {
    description = "Unseal TPM LUKS keyfile";
    after = [ "systemd-modules-load.service" ];
    before = [ "systemd-cryptsetup@crypt.service" ];
    wantedBy = [ "systemd-cryptsetup@crypt.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${unsealScript}";
      SuccessExitStatus = [ 0 1 ];
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
    };
  };

  # INFO: Point LUKS to initrd tmpfs keyfile (fallback to passphrase if not present)
  boot.initrd.luks.devices."crypt".keyFile = unsealedKeyfile;

  # INFO: Required TPM tools in initrd
  boot.initrd.systemd.packages = [ pkgs.tpm2-tools ];

  # INFO: Pre-load TPM kernel modules in initrd
  boot.initrd.kernelModules = [ "tpm_tis" "tpm_crb" ];

  # INFO: Post-boot auto-enrollment service
  # NOTE: If the keyfile is already enrolled, this does nothing (idempotent)
  systemd.services.luks-keyfile-enroll = {
    description = "Auto-enroll TPM-sealed LUKS keyfile";
    after = [ "persistent-storage.service" ];
    wants = [ "persistent-storage.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${autoEnrollScript}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
      SuccessExitStatus = [ 0 1 ];
      TimeoutStartSec = "30s";
    };
  };

  # INFO: Safety setup: passphrase is always a fallback if keyfile missing/fails
  # NOTE: LUKS slot 0 = passphrase, slot 1 = keyfile (added after generate-luks-keyfile)
}
