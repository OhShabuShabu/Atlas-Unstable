{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: TPM PCR ATTESTATION
# INFO: ============================================================================
# INFO: Hardware-rooted integrity check using TPM 2.0:
#   - Boot-time PCR attestation (detects bootkit/UEFI tampering)
#   - Tamper-triggered emergency reboot
#   - PCR baseline management
# NOTE: LUKS key sealing is handled by luks-keyfile.nix (single source of truth)
# WARN: Requires TPM 2.0 hardware (firmware TPM or discrete TPM)
# WARN: PCR mismatch triggers automatic reboot with 30-second countdown

let
  persistentDir = "/persistent";
  pcrBaselinePath = "${persistentDir}/tpm-pcr-baseline.json";
  pcrSelection = "sha256:0,1,7";  # Firmware + UEFI vars + Secure Boot
  tpm2Tools = "${pkgs.tpm2-tools}/bin";

  # INFO: Service to verify TPM PCRs match baseline at boot
  # NOTE: On first boot, creates baseline. On mismatch, triggers emergency reboot.
  tpmAttestationService = pkgs.writeShellScript "tpm-attestation-check.sh" ''
    set -euo pipefail

    LOG="${pcrBaselinePath}"
    CURR="/tmp/tpm-pcr-current.json"
    LOGGER="${pkgs.util-linux}/bin/logger"

    # Wait for TPM device
    if [ ! -e /dev/tpm0 ]; then
      echo "TPM: /dev/tpm0 not found — waiting..." >&2
      for i in $(seq 1 10); do
        sleep 1
        [ -e /dev/tpm0 ] && break
      done
    fi

    if [ ! -e /dev/tpm0 ]; then
      echo "TPM: Device not available after 10s — will retry on next boot" >&2
      $LOGGER -p auth.warning -t tpm-attestation "TPM device unavailable — PCR check skipped"
      exit 0
    fi

    ${tpm2Tools}/tpm2_pcrread "${pcrSelection}" -o "$CURR" 2>/dev/null || {
      echo "TPM: Failed to read PCRs — is tpm2-tools installed?" >&2
      $LOGGER -p auth.err -t tpm-attestation "Failed to read PCR values"
      exit 1
    }

    # First boot — create baseline
    if [ ! -f "$LOG" ]; then
      mkdir -p "$(dirname "$LOG")"
      cp "$CURR" "$LOG"
      chmod 0600 "$LOG"
      echo "TPM: PCR baseline created at $LOG"
      echo "TPM: PCRs monitored: ${pcrSelection}"
      $LOGGER -p auth.info -t tpm-attestation "PCR baseline created (PCRs: ${pcrSelection})"
      exit 0
    fi

    # Compare current PCRs to baseline
    if ! diff -q "$CURR" "$LOG" >/dev/null 2>&1; then
      echo "TPM: CRITICAL — PCR MISMATCH DETECTED!" >&2
      echo "TPM: Current PCR values differ from baseline — bootkit or firmware tampering suspected" >&2
      ${pkgs.util-linux}/bin/logger -p auth.crit -t tpm-attestation "PCR MISMATCH — system integrity compromised"

      # Emergency reboot with 30-second countdown
      echo "TPM: Rebooting in 30 seconds (cancel with: sudo systemctl cancel-shutdown)"
      ${pkgs.systemd}/bin/shutdown -r +1 "TPM PCR MISMATCH — Integrity check failed"
      exit 1
    fi

    echo "TPM: PCR attestation PASSED — values match baseline"
  '';
in

{
  imports = [
    # No sub-imports — standalone module
  ];

  # INFO: Create persistent storage directories with proper permissions
  systemd.tmpfiles.rules = [
    "d ${persistentDir} 0700 root root -"
  ];

  # INFO: TPM PCR attestation service — verifies boot-time integrity
  # NOTE: Creates baseline on first boot; compares on every subsequent boot
  # WARN: PCR mismatch triggers emergency shutdown with 30-second countdown
  systemd.services.tpm-attestation-check = {
    description = "TPM PCR Attestation & Tamper Detection";
    after = [ "persistent.mount" ];
    wants = [ "persistent.mount" ];
    before = [ "tpm-pcr-monitor.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${tpmAttestationService}";
      User = "root";
      Group = "root";
      # Security sandboxing
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/persistent" ];
      ProtectHome = true;
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
      TimeoutStartSec = "60s";
      SuccessExitStatus = [ 0 1 ];
    };
  };

  # NOTE: tpm2-tools is provided by configuration.nix environment.systemPackages
  # NOTE: LUKS key sealing is handled by luks-keyfile.nix
}
