{ pkgs, lib, ... }:

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
        systemctl is-active --quiet snout-daemon 2>/dev/null && echo "  Running" || echo "  Stopped"
        echo "Recent events:"
        if [ -f /var/log/snout/events.log ]; then
          ${pkgs.coreutils}/bin/tail -10 /var/log/snout/events.log 2>/dev/null || true
        fi
        ;;
      status)
        systemctl status snout-daemon 2>/dev/null || echo "snout-daemon not running"
        ;;
      logs)
        journalctl -fu snout-daemon
        ;;
      *)
        echo "Usage: snout <scan|status|logs>"
        exit 1
        ;;
    esac
  '';

  snoutDaemon = pkgs.writeShellScriptBin "snout-daemon" ''
    set -e
    LOG_DIR="/var/log/snout"
    EVENTS_LOG="$LOG_DIR/events.log"
    mkdir -p "$LOG_DIR"

    log_event() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] [''${1:-INFO}] ''${2:-}" >> "$EVENTS_LOG"
    }

    notify_user() {
      ${notifyScript}/bin/notify-user "$@" 2>/dev/null || true
    }

    log_event "INFO" "Snout daemon starting"

    if command -v ${pkgs.inotify-tools}/bin/inotifywait &>/dev/null; then
      log_event "INFO" "Watching /etc/quarantine for new files"
      while true; do
        event=$(${pkgs.inotify-tools}/bin/inotifywait -q -e create,moved_to --format '%w%f' /etc/quarantine 2>/dev/null) || break
        log_event "ALERT" "File quarantined: $event"
        notify_user "critical" "Quarantine" "New file: $(basename "$event")"
        result=$(${pkgs.clamav}/bin/clamscan --quiet "$event" 2>/dev/null || echo "FOUND")
        if echo "$result" | grep -q "FOUND"; then
          log_event "THREAT" "Threat in: $event"
          notify_user "critical" "Snout Security" "Threat in quarantine: $(basename "$event")"
        else
          log_event "INFO" "Clean: $event"
        fi
      done
    else
      log_event "WARN" "inotify not available, polling every 60s"
      while true; do
        before=$(ls -la /etc/quarantine 2>/dev/null | md5sum)
        sleep 60
        after=$(ls -la /etc/quarantine 2>/dev/null | md5sum)
        if [ "$before" != "$after" ]; then
          log_event "ALERT" "Quarantine modified"
          notify_user "critical" "Quarantine" "Changes in /etc/quarantine"
        fi
      done
    fi
  '';
in

{
  environment.systemPackages = [ snoutBin snoutDaemon ];

  systemd.tmpfiles.rules = [
    "d /var/log/snout 0750 root root -"
  ];

  systemd.services.snout-daemon = {
    description = "Snout Security Monitoring Daemon";
    after = [ "network.target" "clamav-daemon.service" ];
    wants = [ "clamav-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${snoutDaemon}/bin/snout-daemon";
      Restart = "on-failure";
      RestartSec = 5;
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
