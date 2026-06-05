{ ... }: {
  flake.modules.nixos.virtualisation = { pkgs, lib, ... }: {
    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings = {
      iptables = false;
      "storage-driver" = "overlay2";
      "log-driver" = "json-file";
      "log-opts" = {
        max-size = "50m";
        max-file = "3";
      };
    };
  };
}
