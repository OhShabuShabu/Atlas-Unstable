{ config, pkgs, lib, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
  hasYusaPasswordHash =
    builtins.pathExists secretsFile &&
    builtins.any (line: lib.hasPrefix "yusa-password-hash:" line)
      (lib.splitString "\n" (builtins.readFile secretsFile));
in {
  sops = {
    defaultSopsFile = secretsFile;

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    secrets = lib.mkIf hasYusaPasswordHash {
      yusa-password-hash = {
        neededForUsers = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    sops
    ssh-to-age
  ];
}
