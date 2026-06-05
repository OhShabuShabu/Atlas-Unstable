{ ... }: {
  flake.modules.nixos.network = { pkgs, lib, config, ... }: {
    networking.networkmanager.enable = true;
    networking.networkmanager.dns = "systemd-resolved";
    networking.useDHCP = false; # NetworkManager is the sole DHCP client — prevents networkd conflicts

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;

        AllowTcpForwarding = false;
        AllowAgentForwarding = false;
        ClientAliveCountMax = 2;
        LogLevel = "VERBOSE";
        MaxAuthTries = 3;
        MaxSessions = 10;
        TCPKeepAlive = true;
      };
      extraConfig = ''
        Match Address 192.168.*,10.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*
          PasswordAuthentication yes
      '';
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };

    # DNS handled by systemd-resolved via NetworkManager — see hardening.nix
  };
}
