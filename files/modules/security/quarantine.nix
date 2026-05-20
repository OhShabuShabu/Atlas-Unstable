{ pkgs, lib, ... }:

let
  quarantineDir = "/etc/quarantine";
in

{
  systemd.tmpfiles.rules = [
    "d ${quarantineDir} 0700 root root -"
  ];

  systemd.services.quarantine-setup = {
    description = "Setup sandboxed quarantine directory at ${quarantineDir}";
    before = [ "snout-daemon.service" "quarantine-sanitizer.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "quarantine-setup.sh" ''
        set -e
        QUARANTINE="${quarantineDir}"
        mkdir -p "$QUARANTINE"
        chmod 0700 "$QUARANTINE"
        chown root:root "$QUARANTINE"

        if command -v chattr &>/dev/null; then
          chattr +a "$QUARANTINE" 2>/dev/null || true
        fi

        cat > "$QUARANTINE/README.txt" << 'EOF'
          ╔══════════════════════════════════════════════╗
          ║         QUARANTINE — LOCKED DOWN             ║
          ║   Files here are isolated from the system.   ║
          ║   Permissions: 0000 (no access)              ║
          ║   All files are auto-scanned by ClamAV.      ║
          ║   Quarantine is wiped at each shutdown.      ║
          ╚══════════════════════════════════════════════╝
        EOF
        chmod 0600 "$QUARANTINE/README.txt"

        mount --bind "$QUARANTINE" "$QUARANTINE" 2>/dev/null || true
        mount -o remount,noexec,nosuid,nodev "$QUARANTINE" 2>/dev/null || true
      '';
    };
  };

  systemd.services.quarantine-sanitizer = {
    description = "Sanitize quarantined files to 0000 permissions";
    after = [ "quarantine-setup.service" ];
    wants = [ "quarantine-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "quarantine-sanitizer.sh" ''
        set -e
        QUARANTINE="${quarantineDir}"

        sanitize() {
          find "$QUARANTINE" -type f ! -name "README.txt" -exec chmod 0000 {} \; 2>/dev/null || true
          find "$QUARANTINE" -type f ! -name "README.txt" -exec chown root:root {} \; 2>/dev/null || true
        }

        sanitize

        if command -v ${pkgs.inotify-tools}/bin/inotifywait &>/dev/null; then
          while true; do
            ${pkgs.inotify-tools}/bin/inotifywait -q -e create,moved_to \
              --format '%w%f' "$QUARANTINE" 2>/dev/null || break
            sanitize
          done
        else
          while true; do
            sanitize
            sleep 10
          done
        fi
      '';
      Restart = "on-failure";
      RestartSec = 5;
      PrivateNetwork = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      CapabilityBoundingSet = [ "CAP_DAC_OVERRIDE" "CAP_CHOWN" "CAP_FOWNER" ];
      SystemCallArchitectures = "native";
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
    };
  };

  systemd.services.quarantine-cleanup = {
    description = "Securely wipe quarantine directory at shutdown";
    before = [ "shutdown.target" "reboot.target" "poweroff.target" ];
    wantedBy = [ "shutdown.target" "reboot.target" "poweroff.target" ];
    conflicts = [ "quarantine-sanitizer.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "quarantine-cleanup.sh" ''
        set -e
        QUARANTINE="${quarantineDir}"

        if [ ! -d "$QUARANTINE" ]; then
          exit 0
        fi

        if command -v chattr &>/dev/null; then
          chattr -a "$QUARANTINE" 2>/dev/null || true
          find "$QUARANTINE" -type f -exec chattr -a {} \; 2>/dev/null || true
        fi

        FILE_COUNT=$(find "$QUARANTINE" -type f 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -gt 0 ]; then
          find "$QUARANTINE" -type f -exec ${pkgs.coreutils}/bin/shred -f -u {} \; 2>/dev/null || true
        fi

        find "$QUARANTINE" -mindepth 1 -delete 2>/dev/null || true
      '';
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "quarantine-list" ''
      QUARANTINE="${quarantineDir}"
      if [ -d "$QUARANTINE" ] && [ "$(ls -A "$QUARANTINE" 2>/dev/null)" ]; then
        FILES=$(find "$QUARANTINE" -type f ! -name "README.txt" 2>/dev/null)
        if [ -n "$FILES" ]; then
          echo "=== Quarantined Files ($(echo "$FILES" | wc -l) total) ==="
          echo "$FILES" | while read f; do
            echo "  $(stat --printf='%s bytes | %y' "$f" 2>/dev/null)  $(basename "$f")"
          done
        else
          echo "Quarantine is empty"
        fi
      else
        echo "Quarantine is empty"
      fi
    '')
    (pkgs.writeShellScriptBin "quarantine-purge" ''
      set -e
      QUARANTINE="${quarantineDir}"
      if [ ! -d "$QUARANTINE" ]; then
        echo "error: quarantine directory not found" >&2
        exit 1
      fi
      echo "purging all quarantined files..."
      chattr -a "$QUARANTINE" 2>/dev/null || true
      find "$QUARANTINE" -type f -exec shred -f -u {} \; 2>/dev/null || true
      find "$QUARANTINE" -mindepth 1 -delete 2>/dev/null || true
      chattr +a "$QUARANTINE" 2>/dev/null || true
      echo "done — quarantine purged"
    '')
  ];
}
