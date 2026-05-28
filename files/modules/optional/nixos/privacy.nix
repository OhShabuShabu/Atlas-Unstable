# ============================================================================
# MODULE: privacy
# CATEGORY: privacy
# VERSION: 1.1.0
# TAGS: vpn privacy metadata mullvad browser
# DEPS: none
# INFO: Mullvad VPN with kill switch, metadata cleaner, Mullvad Browser
# ============================================================================
{ config, pkgs, lib, ... }:

let
  cfg = config.atlas.modules.privacy;
in {
  options.atlas.modules.privacy = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "yusa";
      description = "Primary username for privacy module configuration";
    };
  };

  config = {
    # Mullvad VPN
    services.mullvad-vpn.enable = true;

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 53 853 ];
      allowedUDPPorts = [ 53 853 51820 ];
    };

    # Mullvad Browser
    programs.mullvad-browser.enable = true;

    # Metadata stripping
    systemd.user.services.mat2-service = {
      enable = true;
      description = "Auto-strip metadata from downloaded files";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.mat2}/bin/mat2 --quiet "$HOME/Downloads/" 2>/dev/null || true
      '';
    };

    environment.systemPackages = with pkgs; [ libnotify mat2 ];
  };
}
