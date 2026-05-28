# ============================================================================
# ATLAS MODULE MANAGER — NixOS Module
# ============================================================================
# Provides:
#   - atlas-module-manager TUI command (fzf-based)
#   - atlas-module-apply command (apply changes + rebuild)
#   - Desktop entry for launching the module manager
#   - Systemd timer for module update checks
#   - Persistent state directory at /persistent/etc/atlas-modules
# ============================================================================
{ config, pkgs, lib, ... }:

let
  cfg = config.services.atlas-module-manager;

  # Path to the repository base at runtime
  repoBase = "/persistent/home/yusa/Atlas/atlas-unstable";

  # Wrapper that discovers the repo base at runtime (works for both
  # flakes-based builds and direct invocations)
  discoverScript = pkgs.writeShellScriptBin "atlas-module-discover" ''
    # Try runtime path first, fall back to compile-time path
    if [[ -d "/persistent/home/yusa/Atlas/atlas-unstable" ]]; then
      echo "/persistent/home/yusa/Atlas/atlas-unstable"
    elif [[ -n "''${FLAKE:-}" ]]; then
      # Extract base from flake URI
      echo "''${FLAKE%/}"
    else
      # Fallback to the script's location
      dirname "$(readlink -f "$0")"
    fi
  '';

  moduleManagerScript = pkgs.writeShellScriptBin "atlas-module-manager" ''
    set -euo pipefail

    # Find the repository base
    BASE="$(${discoverScript}/bin/atlas-module-discover)"

    # Source the module registry
    source "$BASE/files/lib/module-registry.sh"

    # Override the module base to the runtime path
    ATLAS_MODULES_BASE="$BASE"

    # Launch the TUI
    exec bash "$BASE/files/bin/atlas-module-manager.sh"
  '';

  moduleApplyScript = pkgs.writeShellScriptBin "atlas-module-apply" ''
    set -euo pipefail

    BASE="$(${discoverScript}/bin/atlas-module-discover)"
    source "$BASE/files/lib/module-registry.sh"
    ATLAS_MODULES_BASE="$BASE"

    exec bash "$BASE/files/bin/atlas-module-apply.sh" "$@"
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
      default = false;
      description = "Periodically check for module updates";
    };

    updateInterval = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "Systemd timer interval for update checks";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── Packages ──────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      moduleManagerScript
      moduleApplyScript
      desktopEntry
      fzf                              # TUI dependency
      jq                               # JSON state manipulation
      curl                             # Module downloads
    ];

    # ─── State Directory ───────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /persistent/etc/atlas-modules 0750 root root -"
    ];

    # ─── Auto-Update Timer ─────────────────────────────────────────────
    systemd.services.atlas-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "Atlas Module Update Check";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${moduleApplyScript}/bin/atlas-module-apply --check-updates";
        User = "root";
      };
    };

    systemd.timers.atlas-module-update-check = lib.mkIf cfg.autoUpdate {
      description = "Atlas Module Update Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updateInterval;
        Persistent = true;
      };
    };
  };
}
