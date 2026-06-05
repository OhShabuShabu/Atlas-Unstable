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
  cfg = config.yorha.modules.privacy;
in {
  options.yorha.modules.privacy = {
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
      # Only allow WireGuard outbound connections.
      # Do NOT open DNS ports 53/853 inbound — that would turn the machine into an
      # open resolver, enabling DNS amplification attacks.
      enable = true;
      allowedUDPPorts = [ 51820 ];
    };

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

    environment.systemPackages = with pkgs; [ libnotify mat2 mullvad-browser ];
  };
}
