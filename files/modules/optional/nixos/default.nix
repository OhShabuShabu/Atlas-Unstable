# INFO: Auto-imports optional NixOS system modules from the registry.
# Place system module .nix files (e.g., gpu.nix, privacy.nix) in this
# directory. They will be automatically imported based on registry state.
#
# Module state is managed via: yorha-module (CLI) or yorha-module-manager (TUI).
# Registry source: ../../../lib/module-registry.nix
# State file: /persistent/etc/yorha-modules/state.json
{ config, pkgs, lib, ... }:

let
  registry = import ../../../lib/module-registry.nix { inherit lib; };
  dir = ./.;
  entries = builtins.readDir dir;
  allNixFiles = builtins.filter
    (f: f != "default.nix" && builtins.match ".*\\.nix" f != null)
    (builtins.attrNames entries);

  moduleState = registry.readModuleState;

  # Filter files based on registry state (opt-out model: unknown = enabled)
  enabledFiles = builtins.filter
    (f: registry.shouldImportFile moduleState f)
    allNixFiles;

in {
  imports = map (f: dir + "/${f}") enabledFiles;
}
