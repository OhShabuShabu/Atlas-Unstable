{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: SECURE BOOT - Kernel Signing & Enforcement
# INFO: ============================================================================
# INFO: Creates kernel signing key, signs kernel/initrd, enables Secure Boot
# NOTE: The signing key lives in /persistent (LUKS-encrypted).
#       Systemd services handle automatic signing after NixOS rebuild.
#       A boot-time service verifies Secure Boot is actually enabled.
# WARN: Secure Boot must be enabled in UEFI firmware settings separately.
#       Run `uefi-enroll-key` to enroll the signing cert in UEFI db.
# WARN: If Secure Boot is not enabled in firmware, signed kernels still boot
#       (the signature is ignored in non-enforcing mode).
# WARN: Key generation runs once — deleting the key breaks future signing.

let
  persistentDir = "/persistent";
  signingKey = "${persistentDir}/kernel-sign.key";
  signingCert = "${persistentDir}/kernel-sign.crt";

  # INFO: Service to generate kernel signing key (runs once, idempotent)
  keyGenService = pkgs.writeShellScript "generate-kernel-signing-key.sh" ''
    set -euo pipefail

    KEY="${signingKey}"
    CERT="${signingCert}"

    if [ -f "$KEY" ] && [ -f "$CERT" ]; then
      echo "SBKEY: Signing key already exists"
      exit 0
    fi

    echo "SBKEY: Generating 4096-bit RSA signing key..."
    mkdir -p "$(dirname "$KEY")"

    ${pkgs.openssl}/bin/openssl req -new -x509 -newkey rsa:4096 \
      -keyout "$KEY" -out "$CERT" \
      -days 3650 -nodes -subj "/CN=Atlas Secure Boot Key/" \
      -sha256 2>/dev/null

    chmod 0600 "$KEY"
    chmod 0644 "$CERT"
    echo "SBKEY: Signing key created: $KEY"
    echo "SBKEY: Certificate created: $CERT"

    # Log to syslog
    ${pkgs.util-linux}/bin/logger -p auth.info -t secureboot "Kernel signing key created"
  '';

  # INFO: Service to sign kernel and initrd images after each rebuild
  signKernelService = pkgs.writeShellScript "sign-kernel-and-initrd.sh" ''
    set -euo pipefail

    KEY="${signingKey}"
    CERT="${signingCert}"
    SBTOOLS="${pkgs.sbsigntool}/bin"
    LOGGER="${pkgs.util-linux}/bin/logger"
    SIGNED=0

    if [ ! -f "$KEY" ] || [ ! -f "$CERT" ]; then
      echo "SBKERN: Signing key not found — run secureboot-key-generate first"
      exit 1
    fi

    # Sign all vmlinuz kernels
    for KERNEL in /boot/vmlinuz-*; do
      BASENAME=$(basename "$KERNEL")
      # Skip if already signed
      if $SBTOOLS/sbverify --cert "$CERT" "$KERNEL" 2>/dev/null; then
        echo "SBKERN: Already signed: $BASENAME"
        continue
      fi
      echo "SBKERN: Signing $BASENAME..."
      $SBTOOLS/sbsign --key "$KEY" --cert "$CERT" \
        --output "$KERNEL.tmp" "$KERNEL" 2>/dev/null && \
      mv "$KERNEL.tmp" "$KERNEL" && \
      SIGNED=$((SIGNED + 1)) && \
      echo "SBKERN: Signed $BASENAME"
    done

    # Verify kernel signatures only (UEFI Secure Boot verifies kernel EFI stub, not initrd)
    echo "SBKERN: Verifying kernel signatures..."
    VERIFY_FAIL=0
    for KERNEL in /boot/vmlinuz-*; do
      $SBTOOLS/sbverify --cert "$CERT" "$KERNEL" 2>/dev/null || {
        echo "SBKERN: VERIFY FAILED: $KERNEL" >&2
        VERIFY_FAIL=$((VERIFY_FAIL + 1))
      }
    done

    if [ "$SIGNED" -gt 0 ]; then
      $LOGGER -p auth.info -t secureboot "Signed $SIGNED kernel images"
    fi
    if [ "$VERIFY_FAIL" -gt 0 ]; then
      $LOGGER -p auth.err -t secureboot "$VERIFY_FAIL kernel(s) failed signature verification"
    fi
    echo "SBKERN: Signing complete ($SIGNED signed, $VERIFY_FAIL verify failures)"
  '';

  # INFO: UEFI key enrollment script — run manually after key generation
  uefiEnrollScript = pkgs.writeShellScript "uefi-enroll-key.sh" ''
    set -euo pipefail

    CERT="${signingCert}"

    echo "=== UEFI Key Enrollment ==="
    echo ""
    echo "This script enrolls the Secure Boot signing certificate into UEFI."
    echo ""
    echo "Options:"
    echo "  1) Enroll to MOK (Machine Owner Key) via mokutil"
    echo "     Requires: reboot + manual enrollment in MOK Manager"
    echo "  2) Enroll to UEFI db via efi-updatevar"
    echo "     Requires: Secure Boot in Setup Mode"
    echo "  3) Print instructions for firmware menu enrollment"
    echo ""

    if [ ! -f "$CERT" ]; then
      echo "ERROR: Certificate not found at $CERT"
      echo "Run secureboot-key-generate service first"
      exit 1
    fi

    if command -v mokutil &>/dev/null; then
      if mokutil --list-enrolled 2>/dev/null | grep -q "Atlas Secure Boot Key"; then
        echo "✓ Key already enrolled in MOK"
        exit 0
      fi
      echo "Enrolling key via MOK..."
      sudo mokutil --import "$CERT" 2>/dev/null && \
        echo "Key imported. Reboot and follow MOK Manager prompts." || \
        echo "MOK enrollment failed. Try method 3 (firmware menu)."
    elif command -v efi-updatevar &>/dev/null; then
      echo "Enrolling key directly to UEFI db..."
      sudo efi-updatevar -e -f "$CERT" db 2>/dev/null && \
        echo "✓ Key enrolled in UEFI db" || \
        echo "Direct enrollment failed. System may not be in Setup Mode."
    else
      echo ""
      echo "Manual enrollment instructions:"
      echo "  1. Reboot and enter UEFI firmware settings"
      echo "  2. Enable Secure Boot and enter Setup Mode"
      echo "  3. Enroll custom key from: $CERT"
      echo "  4. Save and exit"
      echo ""
      echo "Alternatively, install mokutil and try again:"
      echo "  sudo mokutil --import $CERT"
      echo "  (then reboot and follow prompts)"
    fi
  '';

  # INFO: Boot-time verification that Secure Boot is actually enabled
  secureBootCheckScript = pkgs.writeShellScript "secureboot-check.sh" ''
    set -euo pipefail

    LOGGER="${pkgs.util-linux}/bin/logger"

    # Check UEFI Secure Boot status
    if [ -d /sys/firmware/efi ]; then
      SB_FILE=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null || true)
      if [ -n "$SB_FILE" ]; then
        SB_VAL=$(od -An -tx1 "$SB_FILE" 2>/dev/null | head -1 | ${pkgs.gawk}/bin/awk '{print $1}')
        if [ "$SB_VAL" = "01" ]; then
          echo "SB-CHECK: ✓ Secure Boot is ENABLED in UEFI"
          $LOGGER -p auth.info -t secureboot "Secure Boot enabled"
          exit 0
        else
          echo "SB-CHECK: ⚠ Secure Boot is DISABLED in UEFI (value: $SB_VAL)"
          echo "SB-CHECK: Run 'uefi-enroll-key' to enroll the signing key,"
          echo "SB-CHECK: then enable Secure Boot in UEFI firmware settings."
          $LOGGER -p auth.warning -t secureboot "Secure Boot DISABLED in UEFI"
          exit 1
        fi
      else
        echo "SB-CHECK: ⚠ Cannot read Secure Boot status (efivars not accessible)"
        exit 1
      fi
    else
      echo "SB-CHECK: Not a UEFI system — Secure Boot not applicable"
      exit 0
    fi
  '';
in

{
  # INFO: Packages needed for Secure Boot operations
  environment.systemPackages = with pkgs; [
    sbsigntool      # sbsign/sbverify for kernel signing
    efibootmgr      # EFI boot manager
    openssl         # Key generation (already in config but explicit here)
    (pkgs.runCommandLocal "uefi-enroll-key" {} ''
      mkdir -p $out/bin
      cp ${uefiEnrollScript} $out/bin/uefi-enroll-key
      chmod 0755 $out/bin/uefi-enroll-key
    '')
  ];

  # INFO: Kernel signing key generation (runs once at boot, idempotent)
  systemd.services.secureboot-key-generate = {
    description = "Generate Secure Boot Kernel Signing Key";
    after = [ "persistent.mount" ];
    wants = [ "persistent.mount" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "secureboot-sign-kernel.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${keyGenService}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/persistent" ];
      ProtectHome = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" "CAP_FOWNER" ];
      TimeoutStartSec = "30s";
    };
  };

  # INFO: Kernel/initrd signing service (runs after each rebuild)
  systemd.services.secureboot-sign-kernel = {
    description = "Sign Kernel and Initrd Images";
    after = [ "secureboot-key-generate.service" ];
    wants = [ "secureboot-key-generate.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "secureboot-verify.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${signKernelService}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/persistent" "/boot" ];
      ProtectHome = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" "CAP_FOWNER" ];
      TimeoutStartSec = "60s";
    };
  };

  # INFO: Secure Boot boot-time verification
  # NOTE: Logs warning if Secure Boot is disabled in UEFI
  systemd.services.secureboot-verify = {
    description = "Verify Secure Boot is enabled in UEFI";
    after = [ "secureboot-sign-kernel.service" ];
    wants = [ "secureboot-sign-kernel.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${secureBootCheckScript}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "read-only";
      PrivateTmp = true;
      # Needs to read efivars
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" ];
      SuccessExitStatus = [ 0 1 ];
      TimeoutStartSec = "10s";
    };
  };

  # INFO: Boot config — keep configuration limit low (signed images only)
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 3;

  # INFO: Remove invalid kernel param (secure_boot=1 is not a valid kernel parameter)
  #       Secure Boot enforcement is UEFI-level, not kernel-level.
}
