{ config, pkgs, lib, ... }:

let
  entries = builtins.readDir ./.;
  subdirs = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
  subdirModules = map (d: ./. + "/${d}/default.nix") subdirs;
in {
  imports = subdirModules;

  hardware.enableRedistributableFirmware = true;
}
