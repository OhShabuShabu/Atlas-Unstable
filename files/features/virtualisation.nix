{ ... }: {
  flake.modules.nixos.virtualisation = { pkgs, lib, ... }: {
    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings = {
      # Enable iptables management so Docker containers get NAT/masquerade
      # access to the internet and port forwarding works.
      iptables = true;
      "storage-driver" = "overlay2";
      "log-driver" = "json-file";
      "log-opts" = {
        max-size = "50m";
        max-file = "3";
      };
    };
  };
}
