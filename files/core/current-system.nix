{ config, lib, ... }:

# ============================================================================
# CURRENT SYSTEM FILESYSTEM LAYOUT (impermanent)
# ============================================================================
# Btrfs + tmpfs layout — matches what disko creates during install.
# This is imported by the `atlas` output; NOT by `atlas-installer` (which uses disko).
#
# HARDWARE ADAPTATION:
#   - tmpfs sizes scale with detected RAM (percentage of total)
#   - swap file size scales with detected RAM
#   - Override via hardware.memory options
#     hardware.memory.totalMB = lib.mkForce 8192;
#     hardware.memory.swapSizeMB = lib.mkForce 4096;
# ============================================================================

let
  memMB = config.hardware.memory.totalMB;
  swapSize = config.hardware.memory.swapSizeMB;
  tmpfsPct = config.hardware.memory.tmpfsPercent;

  # Minimum tmpfs size in MB to avoid degenerate cases
  tmpfsSize = if memMB < 2048 then "50%"  # < 2GB: 50% (tight but functional)
    else "${toString tmpfsPct}%";
in {
  boot.initrd.luks.devices."crypt".device = "/dev/disk/by-partlabel/disk-main-root";

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=${tmpfsSize}" "mode=755" ];
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
    options = [ "size=${tmpfsSize}" "mode=1777" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=${tmpfsSize}" "mode=755" ];
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
  # Size scales with detected RAM (see hardware/memory.nix for defaults)
  # Override: hardware.memory.swapSizeMB = lib.mkForce 16384;
  swapDevices = [{
    device = "/persistent/swapfile";
    size = swapSize;
  }];
}
