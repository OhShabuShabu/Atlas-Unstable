{ config, pkgs, lib, ... }:

let
  registry = import ../../../../lib/module-registry.nix;
  dir = ./.;
  entries = builtins.readDir dir;
  allNixFiles = builtins.filter
    (f: f != "default.nix" && builtins.match ".*\\.nix" f != null)
    (builtins.attrNames entries);

  # Read module state; fall back to all-enabled if state file absent
  moduleState = registry.readModuleState;

  # Only import files that are enabled in the module state
  enabledFiles = builtins.filter
    (f: registry.shouldImportFile moduleState f)
    allNixFiles;

in {
  imports = map (f: dir + "/${f}") enabledFiles;
}
