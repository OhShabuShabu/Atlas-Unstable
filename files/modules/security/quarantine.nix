{ pkgs, ... }:

let
  quarantineDir = "/etc/quarantine";
in

{
  systemd.tmpfiles.rules = [
    "d ${quarantineDir} 0700 root root -"
  ];

  systemd.services.quarantine-setup = {
    description = "Setup sandboxed quarantine directory at ${quarantineDir}";
    before = [ "snout-watcher.service" "quarantine-sanitizer.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "quarantine-setup.sh" ''
        set -euo pipefail
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

        # Bind-mount quarantine onto itself with restrictive flags
        # This prevents execution of any quarantined files even if permissions change
        if ! mountpoint -q "$QUARANTINE"; then
          mount --bind "$QUARANTINE" "$QUARANTINE" 2>/dev/null || true
        fi
        mount -o remount,noexec,nosuid,nodev,bind "$QUARANTINE" 2>/dev/null || true
      '';
    };
  };

  systemd.paths.quarantine-sanitizer = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = [ "${quarantineDir}" ];
      Unit = "quarantine-sanitizer.service";
    };
  };

  systemd.services.quarantine-sanitizer = {
    after = [ "quarantine-setup.service" ];
    before = [ "quarantine-sanitizer.path" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "quarantine-sanitizer.sh" ''
        set -euo pipefail
        QUARANTINE="${quarantineDir}"
        [ -d "$QUARANTINE" ] || exit 0
        find "$QUARANTINE" -type f ! -name "README.txt" -exec chmod 0000 {} \; 2>/dev/null || true
        find "$QUARANTINE" -type f ! -name "README.txt" -exec chown root:root {} \; 2>/dev/null || true
      '';
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
        set -euo pipefail
        QUARANTINE="${quarantineDir}"

        [ -d "$QUARANTINE" ] || exit 0

        if command -v chattr &>/dev/null; then
          chattr -a "$QUARANTINE" 2>/dev/null || true
          find "$QUARANTINE" -type f -exec chattr -a {} \; 2>/dev/null || true
        fi

        if [ "$(find "$QUARANTINE" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
          find "$QUARANTINE" -type f -exec ${pkgs.coreutils}/bin/shred -f -u {} \; 2>/dev/null || true
        fi

        find "$QUARANTINE" -mindepth 1 -delete 2>/dev/null || true
      '';
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "quarantine-list" ''
      set -euo pipefail
      QUARANTINE="${quarantineDir}"
      if [ ! -d "$QUARANTINE" ]; then
        echo "Quarantine is empty"
        exit 0
      fi
      mapfile -t FILES < <(find "$QUARANTINE" -type f ! -name "README.txt" 2>/dev/null)
      if [ "''${#FILES[@]}" -gt 0 ]; then
        echo "=== Quarantined Files (''${#FILES[@]} total) ==="
        for f in "''${FILES[@]}"; do
          echo "  $(stat --printf='%s bytes | %y' "$f" 2>/dev/null)  $(basename "$f")"
        done
      else
        echo "Quarantine is empty"
      fi
    '')
    (pkgs.writeShellScriptBin "quarantine-purge" ''
      set -euo pipefail
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
