{ config, lib, pkgs, ... }:

{
  # INFO: Firmware version attestation — detects unauthorized BIOS/UEFI updates
  # INFO: Compares current firmware version against a stored baseline.
  # INFO: On first boot, creates baseline. On mismatch, logs CRITICAL alert.

  systemd.services.firmware-version-check = {
    description = "Firmware Version Attestation — Detect BIOS/UEFI Tampering";
    after = [ "systemd-udev-settle.service" ];
    wants = [ "systemd-udev-settle.service" ];
    before = [ "tpm-attestation-check.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "firmware-version-check.sh" ''
        set -euo pipefail

        BASELINE="/persistent/firmware-version-baseline"
        APPROVED="/persistent/firmware-update-approved"
        LOGGER="${pkgs.util-linux}/bin/logger"
        DMIDECODE="${pkgs.dmidecode}/bin/dmidecode"

        # Read current firmware version
        CURRENT=$($DMIDECODE -s system-firmware-version 2>/dev/null || \
                  cat /sys/devices/virtual/dmi/id/bios_version 2>/dev/null || \
                  echo "unknown")

        echo "FIRMWARE: Current version: $CURRENT"

        # Create baseline on first boot
        if [ ! -f "$BASELINE" ]; then
          echo "$CURRENT" > "$BASELINE"
          chmod 0600 "$BASELINE"
          echo "FIRMWARE: Baseline created: $CURRENT"
          $LOGGER -p auth.info -t firmware-check "Baseline created: $CURRENT"
          exit 0
        fi

        BASELINE_VER=$(cat "$BASELINE")

        if [ "$CURRENT" = "$BASELINE_VER" ]; then
          echo "FIRMWARE: Version matches baseline — OK"
          $LOGGER -p auth.info -t firmware-check "Version OK: $CURRENT"
          exit 0
        fi

        # Version mismatch — check if update was approved
        if [ -f "$APPROVED" ]; then
          echo "FIRMWARE: Version changed but update approved: $BASELINE_VER → $CURRENT"
          $LOGGER -p auth.warning -t firmware-check "Approved update: $BASELINE_VER → $CURRENT"
          # Update baseline to new version
          echo "$CURRENT" > "$BASELINE"
          rm -f "$APPROVED"
          exit 0
        fi

        # Unexpected firmware change — CRITICAL alert
        echo "FIRMWARE: CRITICAL — Unexpected firmware version change!"
        echo "  Expected: $BASELINE_VER"
        echo "  Current:  $CURRENT"
        $LOGGER -p auth.crit -t firmware-check "TAMPER DETECTED: firmware changed $BASELINE_VER → $CURRENT"
        ${pkgs.systemd}/bin/systemd-cat -p crit <<< "FIRMWARE TAMPER: Version changed from $BASELINE_VER to $CURRENT"

      '';
      SuccessExitStatus = [ 0 1 ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/persistent" ];
      ProtectHome = true;
      PrivateTmp = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
      User = "root";
      Group = "root";
    };

    wantedBy = [ "multi-user.target" ];
  };

  environment.systemPackages = with pkgs; [
    dmidecode
    (pkgs.writeShellScriptBin "firmware-version-approve-update" ''
      set -euo pipefail
      if [ $# -ne 1 ]; then
        echo "Usage: firmware-version-approve-update <new-version-string>"
        exit 1
      fi
      echo "$1" > /persistent/firmware-update-approved
      chmod 0600 /persistent/firmware-update-approved
      echo "Approved firmware update to: $1"
      echo "Run 'sudo systemctl start firmware-version-check' to update baseline"
    '')
  ];
}
