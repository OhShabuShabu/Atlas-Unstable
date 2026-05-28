{ config, lib, pkgs, ... }:

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
  boot.initrd.luks.devices."crypt" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
  };

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
  # NOTE: On btrfs, swapfile needs nodatacow (chattr +C) before any writes.
  #       We create it via a systemd service that handles this correctly.
  swapDevices = [{
    device = "/persistent/swapfile";
  }];

  systemd.services."create-swapfile" = {
    description = "Create btrfs-compatible swapfile";
    before = [ "persistent-swapfile.swap" "swap.target" ];
    requiredBy = [ "persistent-swapfile.swap" "swap.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-swapfile" ''
        set -euo pipefail
        if [ -f /persistent/swapfile ] && ${pkgs.util-linux}/bin/swapon --show 2>/dev/null | grep -q /persistent/swapfile; then
          exit 0
        fi
        rm -f /persistent/swapfile
        truncate -s 0 /persistent/swapfile
        ${pkgs.e2fsprogs}/bin/chattr +C /persistent/swapfile
        ${pkgs.util-linux}/bin/fallocate -l ${toString swapSize}M /persistent/swapfile
        chmod 0600 /persistent/swapfile
        ${pkgs.util-linux}/bin/mkswap /persistent/swapfile
      '';
      TimeoutStartSec = "30s";
    };
  };

  systemd.services."atlas-tpm-enroll" = {
    description = "Enroll TPM2 key into LUKS (one-time first-boot)";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    requires = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "atlas-tpm-enroll" ''
        set -euo pipefail

        LUKS_DEVICE="/dev/disk/by-partlabel/disk-main-root"
        PASSWORD_FILE="/etc/luks-tpm-password"
        DONE_FILE="/persistent/.tpm-enrolled"

        if [ -f "$DONE_FILE" ]; then
          exit 0
        fi

        if [ ! -f "$PASSWORD_FILE" ]; then
          echo "atlas-tpm-enroll: no $PASSWORD_FILE — skipping"
          exit 0
        fi

        if [ ! -e /dev/tpm0 ] && [ ! -e /dev/tpmrm0 ]; then
          echo "atlas-tpm-enroll: no TPM device found — skipping"
          exit 0
        fi

        if ${pkgs.cryptsetup}/bin/cryptsetup luksDump "$LUKS_DEVICE" | grep -q "systemd-tpm2"; then
          echo "atlas-tpm-enroll: TPM2 token already present"
          rm -f "$PASSWORD_FILE"
          touch "$DONE_FILE"
          exit 0
        fi

        echo "atlas-tpm-enroll: enrolling TPM2 for $LUKS_DEVICE ..."
        ${pkgs.systemd}/bin/systemd-cryptenroll \
          --tpm2-device=auto \
          --tpm2-pcrs=0+7 \
          --password-file="$PASSWORD_FILE" \
          "$LUKS_DEVICE"

        rm -f "$PASSWORD_FILE"
        touch "$DONE_FILE"
        echo "atlas-tpm-enroll: TPM2 enrollment complete"
      '';
      TimeoutStartSec = "120s";
    };
  };
}
