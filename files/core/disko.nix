{ config, lib, pkgs, ... }:

let
  diskDevice = let
    env = builtins.getEnv "DISKO_DEVICE";
  in if env != "" then env else "/dev/REPLACE_ME";

  lukUuidFile = ../.luk-uuid;
  lukUuid = if builtins.pathExists lukUuidFile then builtins.readFile lukUuidFile else "";
  lukUuidClean = lib.strings.removeSuffix "\n" (lib.strings.removeSuffix "\r" lukUuid);
  lukDevice = if lukUuidClean != "" then "/dev/disk/by-uuid/${lukUuidClean}" else "/dev/disk/by-partlabel/disk-main-root";
in {
  # VM disk drivers (bare metal uses NVMe/AHCI from hardware-configuration.nix)
  boot.initrd.availableKernelModules = [ "virtio_blk" "virtio_pci" "virtio_scsi" "ata_piix" ];
  boot.initrd.luks.devices."crypt" = {
    device = lib.mkForce lukDevice;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };

  fileSystems = {
    "/nix".neededForBoot = true;
    "/persistent".neededForBoot = true;
    "/home".neededForBoot = true;
    "/var".neededForBoot = true;
  };

  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=25%"
        "mode=755"
      ];
    };

    nodev."/tmp" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=25%"
        "mode=1777"
      ];
    };

    nodev."/home" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=25%"
        "mode=755"
      ];
    };

    disk.main = {
      type = "disk";
      device = diskDevice;
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
            };
          };
          # Swap is a file on the LUKS-encrypted /persistent btrfs subvol.
          # No separate swap partition — everything on disk is inside LUKS.
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypt";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/nix" = {
                    mountOptions = [ "subvol=nix" "noatime" ];
                    mountpoint = "/nix";
                  };
                  "/persistent" = {
                    mountOptions = [ "subvol=persistent" "noatime" ];
                    mountpoint = "/persistent";
                  };
                  # /home is tmpfs — user data is persisted via bind mounts from
                  # /persistent/home/<user>/, configured in preservation.nix
                  # The subvol entry is kept (commented) for reference only —
                  # a fresh install with disko creates a clean btrfs without it.
                  "/var" = {
                    mountOptions = [ "subvol=var" "noatime" ];
                    mountpoint = "/var";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
