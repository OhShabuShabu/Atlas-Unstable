{ pkgs, lib, ... }:

let
  scanDirs = "/home /tmp /var /srv";
  logFile = "/var/log/clamav/scan.log";
  quarantineDir = "/etc/quarantine";

  notifyScript = pkgs.writeShellScriptBin "clamav-notify" ''
    NOTIFY="${pkgs.libnotify}/bin/notify-send"
    SEVERITY="''${1:-normal}"
    TITLE="''${2:-ClamAV}"
    MESSAGE="''${3:-}"

    for user in yusa; do
      uid=$(id -u "$user" 2>/dev/null || echo 1000)
      bus_path="/run/user/$uid/bus"
      if [ -S "$bus_path" ]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus_path" \
          "$NOTIFY" -u "$SEVERITY" -t 15000 "$TITLE" "$MESSAGE" 2>/dev/null || true
      fi
    done
  '';
in

{
  systemd.tmpfiles.rules = [
    "d /var/log/clamav 0750 root root -"
    "d /var/lib/clamav/tmp 0750 clamav clamav -"
  ];

  services.clamav = {
    daemon.enable = true;
    daemon.settings = {
      TemporaryDirectory = "/var/lib/clamav/tmp";
      OnAccessIncludePath = [ "/home" "/tmp" "/var" "/srv" ];
      OnAccessPrevention = false;
      OnAccessExtraScanning = true;
      OnAccessExcludeRootUID = true;
      OnAccessMaxFileSize = "10M";
    };
    updater.enable = true;
    # NOTE: On-access scanning disabled on unstable kernel - causes filesystem hangs
    clamonacc.enable = false;
  };

  systemd.services.clamav-daemon = {
    serviceConfig = {
      Restart = "on-failure";
      NoNewPrivileges = true;
    };
  };

  systemd.services.clamav-daily-scan = {
    description = "Daily ClamAV virus scan with auto-quarantine and notifications";
    after = [ "network.target" "clamav-daemon.service" ];
    wantedBy = [];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "clamav-daily-scan.sh" ''
        set -e
        SCAN_DIRS="${scanDirs}"
        LOG_FILE="${logFile}"
        QUARANTINE="${quarantineDir}"
        CLAMSCAN="${pkgs.clamav}/bin/clamscan"
        NOTIFY="${notifyScript}/bin/clamav-notify"

        mkdir -p "$(dirname "$LOG_FILE")"
        mkdir -p "$QUARANTINE"

        echo "=== ClamAV Scan $(date) ===" >> "$LOG_FILE"

        $CLAMSCAN --recursive --detect-pua=yes \
          --exclude-dir="/proc" --exclude-dir="/sys" --exclude-dir="/dev" \
          --exclude-dir="$QUARANTINE" \
          --move="$QUARANTINE" \
          --log="$LOG_FILE" $SCAN_DIRS 2>&1 | tail -50 >> "$LOG_FILE"

        THREATS=$(grep -c "FOUND" "$LOG_FILE" 2>/dev/null || echo "0")

        if [ "$THREATS" -gt 0 ]; then
          THREAT_LIST=$(grep "FOUND" "$LOG_FILE" | sed 's/.*FOUND//' | head -3 | tr '\n' ' ')
          "$NOTIFY" critical "ClamAV Alert" "Threats quarantined: $THREAT_LIST"
          echo "ALERT: $THREATS threats quarantined at $(date)" >> "$LOG_FILE"

          find "$QUARANTINE" -type f ! -name "README.txt" -exec chmod 0000 {} \; 2>/dev/null || true
          find "$QUARANTINE" -type f ! -name "README.txt" -exec chown root:root {} \; 2>/dev/null || true
        else
          "$NOTIFY" low "ClamAV Scan Complete" "No threats found"
          echo "Scan completed - No threats found at $(date)" >> "$LOG_FILE"
        fi

        if [ -d "$QUARANTINE" ] && [ "$(ls -A "$QUARANTINE" 2>/dev/null)" ]; then
          echo "=== Quarantine Verification Scan $(date) ===" >> "$LOG_FILE"
          $CLAMSCAN --recursive --quiet "$QUARANTINE" >> "$LOG_FILE" 2>&1 || true
        fi

        find /var/log/clamav -maxdepth 1 -name "scan.log.*" -mtime +7 -delete 2>/dev/null || true
      '';
    };
  };

  systemd.services.clamav-tmp-scan = {
    description = "ClamAV frequent /tmp scan with auto-quarantine";
    after = [ "network.target" "clamav-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "clamav-tmp-scan.sh" ''
        set -e
        QUARANTINE="${quarantineDir}"
        CLAMSCAN="${pkgs.clamav}/bin/clamscan"
        NOTIFY="${notifyScript}/bin/clamav-notify"

        mkdir -p "$QUARANTINE"

        result=$($CLAMSCAN --recursive --no-summary \
          --move="$QUARANTINE" /tmp 2>&1) || true

        if echo "$result" | grep -qi "FOUND"; then
          THREATS=$(echo "$result" | grep -c "FOUND" || true)
          THREAT_LIST=$(echo "$result" | grep "FOUND" | head -3 | sed 's/.*://' | tr '\n' ' ')
          "$NOTIFY" critical "ClamAV Quarantine" "Threats quarantined from /tmp: $THREAT_LIST"
          find "$QUARANTINE" -type f ! -name "README.txt" -exec chmod 0000 {} \; 2>/dev/null || true
          find "$QUARANTINE" -type f ! -name "README.txt" -exec chown root:root {} \; 2>/dev/null || true
        fi
      '';
    };
  };

  systemd.timers.clamav-tmp-scan = {
    description = "Frequent ClamAV /tmp scan timer (every 5 min)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  systemd.timers.clamav-daily-scan = {
    description = "Daily ClamAV virus scan timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  environment.systemPackages = [ notifyScript ];
}
