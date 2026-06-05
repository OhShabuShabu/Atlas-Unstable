{ config, pkgs, lib, ... }:

let
  secretsFile = ../../secrets/secrets.yaml;

  # Check if yusa-password-hash exists in the (possibly sops-encrypted) file.
  # SOPS keeps keys visible in plaintext even when values are encrypted, so we
  # can check for the key without needing decryption access at eval time.
  hasPasswordHash = builtins.pathExists secretsFile &&
    (builtins.match ".*yusa-password-hash:.*"
      (builtins.replaceStrings ["\n"] [" "] (builtins.readFile secretsFile)) != null);

in {
  sops = lib.mkIf (builtins.pathExists secretsFile) {
    defaultSopsFile = secretsFile;

    age = {
      sshKeyPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_rsa_key"
      ];
    };

    secrets = {
      yusa-password-hash = lib.mkIf hasPasswordHash {
        neededForUsers = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    sops
    ssh-to-age
  ];
}
