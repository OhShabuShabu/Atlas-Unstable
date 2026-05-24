{ config, pkgs, lib, ... }:

let
  entries = builtins.readDir ./.;
  nixFiles = builtins.filter
    (n: builtins.match ".*\\.nix" n != null)
    (builtins.attrNames entries);
  modulePaths = map (f: ./. + "/${f}") nixFiles;
  filtered = builtins.filter (f: f != ./default.nix) modulePaths;
in {
  imports = filtered;
}
