{ config, pkgs, inputs, ... }:
{
  hardware.graphics.enable32Bit = true;

  programs.steam = {
    enable = true;
    package = pkgs.steam.override {
      extraPkgs = pkgs: with pkgs; [ mangohud ];
    };
  };

  hardware.steam-hardware.enable = true;

  environment.systemPackages = with pkgs; [
    steamcmd
    mangohud
    goverlay
  ];
}
