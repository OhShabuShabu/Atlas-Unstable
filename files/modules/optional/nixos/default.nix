{ config, pkgs, lib, ... }:
let
  dir = ./.;
  entries = builtins.readDir dir;
  nixFiles = builtins.filter
    (f: f != "default.nix" && builtins.match ".*\\.nix" f != null)
    (builtins.attrNames entries);
in
{
  imports = map (f: dir + "/${f}") nixFiles;
}
