{ ... }: {
  flake.modules.nixos.network = { pkgs, lib, config, ... }: {
    networking.networkmanager.enable = true;
    networking.networkmanager.dns = "systemd-resolved";
    networking.useDHCP = false;

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
        MaxSessions = 2;
        TCPKeepAlive = false;
      };
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };

    networking.nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];
  };
}
