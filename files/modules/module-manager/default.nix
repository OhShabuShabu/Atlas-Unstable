# ============================================================================
# ATLAS MODULE MANAGER — NixOS Module
# ============================================================================
# Provides:
#   - atlas-module-manager TUI command (fzf/gum/dialog/newt/TTY fallback)
#   - atlas-module-apply command (apply changes + rebuild)
#   - atlas-module command (unified CLI for all module operations)
#   - atlas-module-verify command (module load verification)
#   - Desktop entry for launching the module manager
#   - Systemd timer for module update checks
#   - Systemd path unit for module change monitoring
#   - Persistent state directory at /persistent/etc/atlas-modules
# ============================================================================
{ config, pkgs, lib, ... }:

let
  cfg = config.services.atlas-module-manager;

  discoverScript = pkgs.writeShellScriptBin "atlas-module-discover" ''
    if [[ -d "/persistent/home/yusa/Atlas/atlas-unstable" ]]; then
      echo "/persistent/home/yusa/Atlas/atlas-unstable"
    elif [[ -n "''${FLAKE:-}" ]]; then
      echo "''${FLAKE%/}"
    else
      dirname "$(readlink -f "$0")"
    fi
  '';

  moduleManagerScript = pkgs.writeShellScriptBin "atlas-module-manager" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/atlas-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    ATLAS_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/atlas-module-manager.sh"
  '';

  moduleApplyScript = pkgs.writeShellScriptBin "atlas-module-apply" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/atlas-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    ATLAS_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/atlas-module-apply.sh" "$@"
  '';

  moduleCliScript = pkgs.writeShellScriptBin "atlas-module" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/atlas-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    ATLAS_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/atlas-module.sh" "$@"
  '';

  moduleVerifyScript = pkgs.writeShellScriptBin "atlas-module-verify" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/atlas-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    ATLAS_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/atlas-module-verify.sh" "$@"
  '';

  desktopEntry = pkgs.makeDesktopItem {
    name = "atlas-module-manager";
    desktopName = "Atlas Module Manager";
    comment = "Manage optional system and user modules";
    icon = "system-software-install";
    exec = "${moduleManagerScript}/bin/atlas-module-manager";
    terminal = true;
    categories = [ "System" "Settings" ];
    keywords = [ "atlas" "modules" "nixos" "configuration" ];
  };

in {
  options.services.atlas-module-manager = {
    enable = lib.mkEnableOption "Atlas Module Manager";

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Periodically check for module updates";
    };

    updateInterval = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Systemd timer interval for update checks";
    };

    enableDesktopEntry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install desktop entry for the module manager";
    };

    enablePathMonitor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Monitor module directory for changes and notify";
    };

    enableVerifyTimer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Periodically verify enabled modules are loaded";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      moduleManagerScript
      moduleApplyScript
      moduleCliScript
      moduleVerifyScript
      fzf
      jq
      curl
      gum         # Enhanced TUI (fallback to fzf)
      dialog      # Minimal TTY TUI (fallback)
      whiptail    # TTY dialog (fallback, part of newt)
      newt    # Minimal TTY TUI (fallback, part of newt)
    ] ++ lib.optional cfg.enableDesktopEntry desktopEntry;

    systemd.tmpfiles.rules = [
      "d /persistent/etc/atlas-modules 0775 yusa users -"
    ];

    systemd.services.atlas-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "Atlas Module Update Check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleApplyScript}/bin/atlas-module-apply --check-updates 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t atlas-modules'";
        User = "root";
      };
    };

    systemd.timers.atlas-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "Atlas Module Update Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updateInterval;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.atlas-module-health = {
      description = "Atlas Module Health Check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleApplyScript}/bin/atlas-module-apply --validate 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t atlas-modules'";
        User = "root";
      };
    };

    systemd.timers.atlas-module-health = {
      description = "Atlas Module Health Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };

    systemd.paths.atlas-modules = lib.mkIf cfg.enablePathMonitor {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = [
          "/persistent/etc/atlas-modules"
        ];
        Unit = "atlas-modules-summary.service";
      };
    };

    systemd.services.atlas-modules-summary = lib.mkIf cfg.enablePathMonitor {
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"Module state changed: \$(date)\" | ${pkgs.systemd}/bin/systemd-cat -t atlas-modules -p info'";
      };
    };

    systemd.services.atlas-module-verify = lib.mkIf cfg.enableVerifyTimer {
      description = "Atlas Module Load Verification";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleVerifyScript}/bin/atlas-module-verify --quick 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t atlas-modules-verify'";
        User = "root";
      };
    };

    systemd.timers.atlas-module-verify = lib.mkIf cfg.enableVerifyTimer {
      description = "Atlas Module Load Verification Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };
  };
}
