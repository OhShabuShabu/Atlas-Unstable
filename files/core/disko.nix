{ config, lib, pkgs, ... }:

let
  diskDevice = let
    env = builtins.getEnv "DISKO_DEVICE";
  in if env != "" then env else "/dev/REPLACE_ME";
in {
  # VM disk drivers (bare metal uses NVMe/AHCI from hardware-configuration.nix)
  boot.initrd.availableKernelModules = [ "virtio_blk" "virtio_pci" "virtio_scsi" "ata_piix" ];

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

    disk.main = {
      type = "disk";
      device = diskDevice;
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "1G";
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
          swap = {
            size = "8G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };
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
                  "/home" = {
                    mountOptions = [ "subvol=home" "noatime" ];
                    mountpoint = "/home";
                  };
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
