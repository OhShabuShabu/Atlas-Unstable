{
  # Current ext4 filesystem layout — keeps the running system bootable
  # This is imported by the `atlas` output; NOT by `atlas-installer` (which uses disko)

  fileSystems."/" = {
    device = "/dev/mapper/luks-9e21658b-4fcf-4f61-b95b-6e53e78880ca";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."luks-9e21658b-4fcf-4f61-b95b-6e53e78880ca".device = "/dev/disk/by-uuid/9e21658b-4fcf-4f61-b95b-6e53e78880ca";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/121D-E2E5";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/mapper/luks-9f6c7cfc-4ae0-42c1-b4a3-80723993f898"; }
  ];
}
