{ lib, ... }: {
  flake.lib = {
    module-registry = import ./../files/lib/module-registry.nix { inherit lib; };
  };
}
