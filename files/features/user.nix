{ ... }: {
  flake.modules.nixos.user = { config, pkgs, lib, ... }: {
    users.users.yusa = {
      isNormalUser = true;
      description = "yusa";
      hashedPasswordFile = lib.mkIf (config.sops.secrets ? yusa-password-hash) config.sops.secrets.yusa-password-hash.path;
      extraGroups = [
        "networkmanager" "wheel" "docker" "mullvad"
      ];
      homeMode = "0750";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZUNUi+15sIyPF4CrpeVjsfRE2JlYwIQlDtaCifRuvA yusa@yorha"
      ];
    };

    users.users.yusa.home = "/home/yusa";
  };
}
