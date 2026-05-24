{ pkgs, ... }:

let
  notifications = import ../../lib/notifications.nix { inherit pkgs; };
  notifyScript = notifications.notifyScript;

  snoutBin = pkgs.writeShellScriptBin "snout" ''
    set -e
    case "''${1:-help}" in
      scan)
        echo "=== Snout Security Scan ==="
        echo "Quarantine:"
        if [ -d /etc/quarantine ] && [ "$(ls -A /etc/quarantine 2>/dev/null)" ]; then
          echo "  Files: $(ls /etc/quarantine | wc -l)"
          ${pkgs.clamav}/bin/clamscan --recursive --quiet /etc/quarantine 2>/dev/null && \
            echo "  Status: clean" || echo "  WARNING: threats found"
        else
          echo "  Empty"
        fi
        echo "AIDE:"
        [ -f /var/lib/aide/aide.db.gz ] && echo "  Database: present" || echo "  Database: not initialized"
        echo "Snout daemon:"
        systemctl is-active --quiet snout-watcher.path 2>/dev/null && echo "  Running" || echo "  Stopped"
        echo "Recent events:"
        if [ -f /var/log/snout/events.log ]; then
          ${pkgs.coreutils}/bin/tail -10 /var/log/snout/events.log 2>/dev/null || true
        fi
        ;;
      status)
        systemctl status snout-watcher.path 2>/dev/null || echo "snout-watcher not running"
        systemctl status snout-watcher.service 2>/dev/null || true
        ;;
      logs)
        tail -f /var/log/snout/events.log 2>/dev/null || echo "No events log yet"
        ;;
      *)
        echo "Usage: snout <scan|status|logs>"
        exit 1
        ;;
    esac
  '';
in

{
  environment.systemPackages = [ snoutBin ];

  systemd.tmpfiles.rules = [
    "d /var/log/snout 0750 root root -"
  ];

  systemd.paths.snout-watcher = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = [ "/etc/quarantine" ];
      Unit = "snout-watcher.service";
    };
  };

  systemd.services.snout-watcher = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "snout-watcher.sh" ''
        set -e
        LOG_DIR="/var/log/snout"
        EVENTS_LOG="$LOG_DIR/events.log"
        mkdir -p "$LOG_DIR"

        log_event() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] [''${1:-INFO}] ''${2:-}" >> "$EVENTS_LOG"
        }

        NOTIFY="${notifyScript}/bin/notify-user"
        QUARANTINE="/etc/quarantine"

        for file in "$QUARANTINE"/*; do
          [ -f "$file" ] || continue
          [ "$(basename "$file")" = "README.txt" ] && continue

          log_event "ALERT" "File quarantined: $file"
          "$NOTIFY" critical "Quarantine" "New file: $(basename "$file")"

          result=$(${pkgs.clamav}/bin/clamscan --quiet "$file" 2>/dev/null || echo "FOUND")
          if echo "$result" | grep -q "FOUND"; then
            log_event "THREAT" "Threat in: $file"
            "$NOTIFY" critical "Snout Security" "Threat: $(basename "$file")"
          else
            log_event "INFO" "Clean: $file"
          fi
        done
      '';
      User = "root";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      ReadWritePaths = [ "/var/log/snout" ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" ];
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
    };
  };
}
