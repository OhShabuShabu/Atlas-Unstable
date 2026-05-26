{
  # Current btrfs filesystem layout — matches what disko creates
  # This is imported by the `atlas` output; NOT by `atlas-installer` (which uses disko)

  boot.initrd.luks.devices."crypt".device = "/dev/disk/by-partlabel/disk-main-root";

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=25%" "mode=755" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/crypt";
    fsType = "btrfs";
    options = [ "subvol=nix" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/persistent" = {
    device = "/dev/mapper/crypt";
    fsType = "btrfs";
    options = [ "subvol=persistent" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=25%" "mode=1777" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=25%" "mode=755" ];
    neededForBoot = true;
  };

  fileSystems."/var" = {
    device = "/dev/mapper/crypt";
    fsType = "btrfs";
    options = [ "subvol=var" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-main-esp";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap file on the LUKS-encrypted /persistent subvol — no bare swap partition
  swapDevices = [{
    device = "/persistent/swapfile";
    size = 8192;
  }];
}
