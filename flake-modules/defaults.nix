{ lib, inputs, ... }: {
  flake.defaults = inputs.haumea.lib.load {
    src = ./../files/defaults;
    inputs = { inherit lib; };
  };
}
