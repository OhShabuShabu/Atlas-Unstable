{ ... }: {
  flake.modules.nixos.virtualisation = { pkgs, lib, ... }: {
    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings = {
      iptables = false;
    };
  };
}
