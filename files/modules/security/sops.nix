{ config, pkgs, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  environment.systemPackages = with pkgs; [
    sops
    ssh-to-age
  ];
}
