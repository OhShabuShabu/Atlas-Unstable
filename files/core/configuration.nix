{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../hardware/default.nix
    ../profiles/default.nix
    ../modules/security/default.nix
    ../modules/security/snort.nix
    ../modules/security/snout.nix
    ../modules/optional/nixos
    ../modules/module-manager/default.nix
  ];

  services.yorha-module-manager.enable = true;

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";

  system.stateVersion = "25.11";
}
