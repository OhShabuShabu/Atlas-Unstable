{ config, pkgs, lib, ... }:

let
  entries = builtins.readDir ./.;
  # Import all subdirectory default.nix files (cpu/, gpu/, audio/, detect/)
  subdirs = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
  subdirModules = map (d: ./. + "/${d}/default.nix") subdirs;
in {
  imports = subdirModules;

  # Enable firmware for all hardware — needed by any GPU driver for KMS
  hardware.enableRedistributableFirmware = true;
}
