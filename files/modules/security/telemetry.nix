{ config, pkgs, lib, ... }:
{
  services = {
    journald = {
      storage = "volatile";
      upload.enable = false;
      extraConfig = ''
        RuntimeMaxUse=500M
        RuntimeMaxFileSize=50M
      '';
    };
    avahi.enable = false;
    geoclue2.enable = false;
    accounts-daemon.enable = lib.mkForce false;
  };

  networking.modemmanager.enable = false;
  system.autoUpgrade.enable = false;
}