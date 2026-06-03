# ============================================================================
# ATLAS MODULE MANAGER — NixOS Module
# ============================================================================
# Provides:
#   - yorha-module-manager TUI command (fzf/gum/dialog/newt/TTY fallback)
#   - yorha-module-apply command (apply changes + rebuild)
#   - yorha-module command (unified CLI for all module operations)
#   - yorha-module-verify command (module load verification)
#   - Desktop entry for launching the module manager
#   - Systemd timer for module update checks
#   - Systemd path unit for module change monitoring
#   - Persistent state directory at /persistent/etc/yorha-modules
# ============================================================================
{ config, pkgs, lib, ... }:

let
  cfg = config.services.yorha-module-manager;

  discoverScript = pkgs.writeShellScriptBin "yorha-module-discover" ''
    if [[ -d "/persistent/home/yusa/System/YoRHA" ]]; then
      echo "/persistent/home/yusa/System/YoRHA"
    elif [[ -n "''${FLAKE:-}" ]]; then
      echo "''${FLAKE%/}"
    else
      dirname "$(readlink -f "$0")"
    fi
  '';

  moduleManagerScript = pkgs.writeShellScriptBin "yorha-module-manager" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/yorha-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    YORHA_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/yorha-module-manager.sh"
  '';

  moduleApplyScript = pkgs.writeShellScriptBin "yorha-module-apply" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/yorha-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    YORHA_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/yorha-module-apply.sh" "$@"
  '';

  moduleCliScript = pkgs.writeShellScriptBin "yorha-module" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/yorha-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    YORHA_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/yorha-module.sh" "$@"
  '';

  moduleVerifyScript = pkgs.writeShellScriptBin "yorha-module-verify" ''
    set -euo pipefail
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    BASE="$(${discoverScript}/bin/yorha-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    YORHA_MODULES_BASE="$BASE"
    exec ${pkgs.bash}/bin/bash "$BASE/files/bin/yorha-module-verify.sh" "$@"
  '';

  desktopEntry = pkgs.makeDesktopItem {
    name = "yorha-module-manager";
    desktopName = "YoRHa Module Manager";
    comment = "Manage optional system and user modules";
    icon = "system-software-install";
    exec = "${moduleManagerScript}/bin/yorha-module-manager";
    terminal = true;
    categories = [ "System" "Settings" ];
    keywords = [ "yorha" "modules" "nixos" "configuration" ];
  };

in {
  options.services.yorha-module-manager = {
    enable = lib.mkEnableOption "YoRHa Module Manager";

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
      newt    # TTY dialog (fallback, provides whiptail)
    ] ++ lib.optional cfg.enableDesktopEntry desktopEntry;

    systemd.tmpfiles.rules = [
      "d /persistent/etc/yorha-modules 0775 yusa users -"
    ];

    systemd.services.yorha-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "YoRHa Module Update Check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleApplyScript}/bin/yorha-module-apply --check-updates 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t yorha-modules'";
        User = "root";
      };
    };

    systemd.timers.yorha-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "YoRHa Module Update Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updateInterval;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.yorha-module-health = {
      description = "YoRHa Module Health Check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleApplyScript}/bin/yorha-module-apply --validate 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t yorha-modules'";
        User = "root";
      };
    };

    systemd.timers.yorha-module-health = {
      description = "YoRHa Module Health Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };

    systemd.paths.yorha-modules = lib.mkIf cfg.enablePathMonitor {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = [
          "/persistent/etc/yorha-modules"
        ];
        Unit = "yorha-modules-summary.service";
      };
    };

    systemd.services.yorha-modules-summary = lib.mkIf cfg.enablePathMonitor {
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"Module state changed: \$(date)\" | ${pkgs.systemd}/bin/systemd-cat -t yorha-modules -p info'";
      };
    };

    systemd.services.yorha-module-verify = lib.mkIf cfg.enableVerifyTimer {
      description = "YoRHa Module Load Verification";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c '${moduleVerifyScript}/bin/yorha-module-verify --quick 2>&1 | ${pkgs.systemd}/bin/systemd-cat -t yorha-modules-verify'";
        User = "root";
      };
    };

    systemd.timers.yorha-module-verify = lib.mkIf cfg.enableVerifyTimer {
      description = "YoRHa Module Load Verification Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };
  };
}
