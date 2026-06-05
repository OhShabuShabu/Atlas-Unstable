{ config, pkgs, lib, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;
in {
  sops = lib.mkIf (builtins.pathExists secretsFile) {
    defaultSopsFile = secretsFile;

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    secrets = {
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
