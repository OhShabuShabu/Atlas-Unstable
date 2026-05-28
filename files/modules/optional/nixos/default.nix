{ config, pkgs, lib, ... }:

let
  # DISABLED: Module registry — comment back in when ready
  # registry = import ../../../../lib/module-registry.nix;
  dir = ./.;
  entries = builtins.readDir dir;
  allNixFiles = builtins.filter
    (f: f != "default.nix" && builtins.match ".*\\.nix" f != null)
    (builtins.attrNames entries);

  # DISABLED: Filter by module state
  # moduleState = registry.readModuleState;
  # enabledFiles = builtins.filter
  #   (f: registry.shouldImportFile moduleState f)
  #   allNixFiles;

  # Import all files while registry is disabled
  enabledFiles = allNixFiles;

in {
  imports = map (f: dir + "/${f}") enabledFiles;
}
