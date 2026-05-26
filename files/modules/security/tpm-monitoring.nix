{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: TPM & UEFI MONITORING - Continuous Tamper Detection
# INFO: ============================================================================
# INFO: Continuously monitors TPM PCR values and UEFI firmware variables.
#       Detects bootkits, UEFI tampering, and firmware changes.
# NOTE: TPM PCR monitor runs every 30 minutes (timer).
#       UEFI var monitor runs every 15 minutes (timer).
#       Firmware version check moved to firmware-check.nix.
# WARN: PCR mismatch triggers automatic reboot — all services confirm
#       with the user via a 30-second countdown.

let
  persistentDir = "/persistent";
  pcrBaselinePath = "${persistentDir}/tpm-pcr-baseline.json";
  uefiBaselinePath = "${persistentDir}/uefi-var-baseline.json";
  pcrSelection = "sha256:0,1,7";
  tpmTools = "${pkgs.tpm2-tools}/bin";

  # INFO: Script to reboot with 30-second countdown on tamper detection
  tamperRebootScript = pkgs.writeShellScript "reboot-on-tamper.sh" ''
    REASON="$1"
    echo "TAMPER: $REASON"
    echo "TAMPER: System will reboot in 30 seconds"
    echo "TAMPER: Cancel with: sudo systemctl cancel-shutdown"
    ${pkgs.util-linux}/bin/logger -p auth.crit -t tamper-detect "$REASON"
    ${pkgs.systemd}/bin/shutdown -r +1 "TAMPER: $REASON"
  '';

  # INFO: TPM PCR monitor — checks PCR values every 30 min
  pcrMonitorScript = pkgs.writeShellScript "tpm-pcr-monitor.sh" ''
    set -euo pipefail

    CURR="/tmp/tpm-pcr-$$.json"
    BASELINE="${pcrBaselinePath}"
    REBOOT="${tamperRebootScript}"

    ${tpmTools}/tpm2_pcrread "${pcrSelection}" -o "$CURR" 2>/dev/null || {
      echo "TPM-MON: Cannot read PCRs"
      exit 1
    }

    if [ ! -f "$BASELINE" ]; then
      mkdir -p "$(dirname "$BASELINE")"
      cp "$CURR" "$BASELINE"
      chmod 0600 "$BASELINE"
      echo "TPM-MON: Baseline created"
      exit 0
    fi

    if ! diff -q "$CURR" "$BASELINE" >/dev/null 2>&1; then
      echo "TPM-MON: CRITICAL — PCR mismatch detected!"
      $REBOOT "TPM PCR MISMATCH — Bootkit or UEFI tampering detected"
      exit 1
    fi

    rm -f "$CURR"
    echo "TPM-MON: PCR check passed"
  '';

  # INFO: UEFI variable monitor — checks critical UEFI vars every 15 min
  uefiMonitorScript = pkgs.writeShellScript "uefi-var-monitor.sh" ''
    set -euo pipefail

    BASELINE="${uefiBaselinePath}"
    REBOOT="${tamperRebootScript}"
    CURR="/tmp/uefi-vars-$$.txt"

    # Read critical UEFI variables
    UEFI_DIR="/sys/firmware/efi/efivars"
    for var in SecureBoot SetupMode VendorKeys; do
      FILE=$(${pkgs.findutils}/bin/find "$UEFI_DIR" -name "$var*" -print -quit 2>/dev/null || true)
      if [ -n "$FILE" ]; then
        sha256sum "$FILE" >> "$CURR"
      fi
    done

    if [ ! -s "$CURR" ]; then
      echo "UEFI-MON: No UEFI variables readable"
      rm -f "$CURR"
      exit 0
    fi

    if [ ! -f "$BASELINE" ]; then
      mkdir -p "$(dirname "$BASELINE")"
      cp "$CURR" "$BASELINE"
      chmod 0600 "$BASELINE"
      echo "UEFI-MON: Baseline created"
      rm -f "$CURR"
      exit 0
    fi

    if ! diff -q "$CURR" "$BASELINE" >/dev/null 2>&1; then
      echo "UEFI-MON: CRITICAL — UEFI variable change detected!"
      $REBOOT "UEFI VARIABLE CHANGE — Firmware tampering detected"
      rm -f "$CURR"
      exit 1
    fi

    rm -f "$CURR"
    echo "UEFI-MON: UEFI var check passed"
  '';

in

{
  # ============================================================================
  # TPM PCR MONITOR (timer-based, every 30 min)
  # ============================================================================
  systemd.services.tpm-pcr-monitor = {
    description = "TPM PCR Integrity Monitor";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pcrMonitorScript}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_SYS_BOOT" ];
      TimeoutStartSec = "30s";
    };
  };

  systemd.timers.tpm-pcr-monitor = {
    description = "TPM PCR Monitor Timer (every 30 min)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      RandomizedDelaySec = "60s";
    };
  };

  # ============================================================================
  # UEFI VARIABLE MONITOR (timer-based, every 15 min)
  # ============================================================================
  systemd.services.uefi-var-monitor = {
    description = "UEFI Variable Integrity Monitor";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${uefiMonitorScript}";
      User = "root";
      Group = "root";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_SYS_ADMIN" "CAP_SYS_BOOT" ];
      TimeoutStartSec = "30s";
    };
  };

  systemd.timers.uefi-var-monitor = {
    description = "UEFI Variable Monitor Timer (every 15 min)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      RandomizedDelaySec = "30s";
    };
  };

  # ============================================================================
  # TAMPER REBOOT SCRIPT + MONITORING PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    (pkgs.runCommandLocal "reboot-on-tamper" {} ''
      mkdir -p $out/bin
      cp ${tamperRebootScript} $out/bin/reboot-on-tamper
      chmod 0755 $out/bin/reboot-on-tamper
    '')
  ];
}
