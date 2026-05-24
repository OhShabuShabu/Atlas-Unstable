#!/usr/bin/env bash
set -euo pipefail

ROOTDIR="$(cd "$(dirname "$0")" && pwd)"

AUTO=0
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  AUTO=1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Must be run as root (you're in a NixOS live ISO, use sudo)." >&2
  exit 1
fi

if ! command -v nix &>/dev/null; then
  echo "nix not found. Are you in a NixOS live ISO?" >&2
  exit 1
fi

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] && [[ $AUTO -eq 0 ]]; then
  echo "WARNING: Running from a desktop session. The install uses a lot of memory"
  echo "and GNOME may kill the terminal (OOM). Switch to a TTY first:"
  echo "  Ctrl+Alt+F3   then run:  sudo ./install.sh"
  echo ""
  read -rp 'Continue anyway? (y/N): ' ANS
  if [[ "$ANS" != "y" && "$ANS" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "=== Atlas Installer ==="
echo ""

AVAILABLE=($(lsblk -dpno NAME,TYPE 2>/dev/null | awk '/disk/ {print $1}'))
if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
  echo "No disks detected." >&2
  exit 1
fi

if [[ ${#AVAILABLE[@]} -eq 1 ]]; then
  DISK="${AVAILABLE[0]}"
  echo "Disk: $DISK  ($(lsblk -dno SIZE "$DISK" 2>/dev/null || echo "?"))"
elif [[ $AUTO -eq 1 ]]; then
  DISK="${AVAILABLE[0]}"
  echo "WARNING: Multiple disks, using first: $DISK"
else
  echo "Available disks:"
  for i in "${!AVAILABLE[@]}"; do
    DEV="${AVAILABLE[$i]}"
    SIZE=$(lsblk -dno SIZE "$DEV" 2>/dev/null || echo "?")
    MODEL=$(lsblk -dno MODEL "$DEV" 2>/dev/null || echo "")
    echo "  $((i+1)). $DEV  ($SIZE)  $MODEL"
  done
  echo ""
  while [[ -z "${DISK:-}" ]]; do
    read -rp "Select disk number [1-${#AVAILABLE[@]}]: " SEL
    if [[ "$SEL" =~ ^[0-9]+$ ]] && [[ "$SEL" -ge 1 ]] && [[ "$SEL" -le "${#AVAILABLE[@]}" ]]; then
      DISK="${AVAILABLE[$((SEL-1))]}"
    else
      echo "Invalid selection." >&2
    fi
  done
fi

echo ""
echo "Selected: $DISK"
echo ""
lsblk "$DISK"

TOTAL_MEM=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)

# Free up space on the live ISO
echo "Clearing nix garbage on live ISO..."
nix-collect-garbage 2>/dev/null || true

# Expand live ISO writable store so nix has room to build
for MP in /nix/.rw-store / ; do
  if mountpoint -q "$MP" 2>/dev/null; then
    FS_TYPE=$(findmnt -n -o FSTYPE "$MP")
    if [[ "$FS_TYPE" == "tmpfs" ]]; then
      NEW_SIZE=$((TOTAL_MEM * 9 / 10))M
      mount -o remount,size="$NEW_SIZE" "$MP" 2>/dev/null && echo "Expanded $MP to $NEW_SIZE"
    fi
  fi
done

# Create zram swap if low memory and no swap active
if [[ "$TOTAL_MEM" -lt 8192 ]] && ! swapon --show | grep -q .; then
  echo ""
  echo "Low memory detected (${TOTAL_MEM}MB). Creating compressed swap..."
  modprobe zram 2>/dev/null || true
  echo "$((TOTAL_MEM / 2))M" > /sys/block/zram0/disksize 2>/dev/null || true
  mkswap /dev/zram0 2>/dev/null || true
  swapon /dev/zram0 -p 10 2>/dev/null || true
  echo "zram swap enabled ($((TOTAL_MEM / 2))MB, compressed)."
fi

echo ""
echo "Freeing page cache..."
sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

echo ""
echo "=== Step 2: Partitioning $DISK ==="
echo ""

# Write the disko config as Nix (disko evaluates configs via nix-instantiate)
cat > /tmp/disko-config.nix <<EOF
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "$DISK";
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
              mountOptions = ["fmask=0077" "dmask=0077"];
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
                extraArgs = ["-f"];
                subvolumes = {
                  "/nix" = { mountOptions = ["subvol=nix" "noatime"]; mountpoint = "/nix"; };
                  "/persistent" = { mountOptions = ["subvol=persistent" "noatime"]; mountpoint = "/persistent"; };
                  "/home" = { mountOptions = ["subvol=home" "noatime"]; mountpoint = "/home"; };
                  "/var" = { mountOptions = ["subvol=var" "noatime"]; mountpoint = "/var"; };
                };
              };
            };
          };
        };
      };
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = ["size=25%" "mode=755"];
    };
    nodev."/tmp" = {
      fsType = "tmpfs";
      mountOptions = ["size=25%" "mode=1777"];
    };
  };
}
EOF

# Build and run disko from pinned nixpkgs
nix run "nixpkgs#disko" \
  --extra-experimental-features "nix-command flakes" \
  -- --mode disko /tmp/disko-config.nix

echo ""
echo "=== Step 3: Mounting target ==="
echo ""

TARGET=/mnt

LUKS_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep crypto_LUKS | awk '{print $1}')
BOOT_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep vfat | awk '{print $1}')
LUKS_UUID=$(blkid -o value -s UUID "$LUKS_PART" 2>/dev/null || true)

echo "LUKS root:  $LUKS_PART  (UUID: $LUKS_UUID)"
echo "ESP boot:   $BOOT_PART"
echo ""

if ! cryptsetup status crypt &>/dev/null; then
  cryptsetup open "$LUKS_PART" crypt
fi

mount -t btrfs -o subvol=nix,noatime /dev/mapper/crypt "$TARGET/nix"
mount -t btrfs -o subvol=persistent,noatime /dev/mapper/crypt "$TARGET/persistent"
mount -t btrfs -o subvol=home,noatime /dev/mapper/crypt "$TARGET/home"
mount -t btrfs -o subvol=var,noatime /dev/mapper/crypt "$TARGET/var"
mount "$BOOT_PART" "$TARGET/boot"

echo ""
echo "=== Step 4: Installing NixOS ==="
echo ""

export DISKO_DEVICE="$DISK"
echo "$LUKS_UUID" > "$ROOTDIR/.luk-uuid"

trap 'rm -f "$ROOTDIR/.luk-uuid"' EXIT

nixos-install --flake "$ROOTDIR#atlas-installer" \
  --root "$TARGET" \
  --no-root-passwd \
  --option substituters "https://cache.nixos.org"

echo ""
echo "=== Step 5: Setting user password ==="
echo ""

if [[ $AUTO -eq 1 ]]; then
  echo "root:root" | nixos-enter --root "$TARGET" --command 'chpasswd' 2>/dev/null || true
  echo "yusa:atlas"   | nixos-enter --root "$TARGET" --command 'chpasswd' 2>/dev/null || true
  echo "Passwords set to root:root / yusa:atlas (change on first login)."
else
  echo "Set root password:"
  read -s ROOT_PW
  echo "root:$ROOT_PW" | nixos-enter --root "$TARGET" --command 'chpasswd'
  echo "Set yusa password:"
  read -s YUSA_PW
  echo "yusa:$YUSA_PW" | nixos-enter --root "$TARGET" --command 'chpasswd'
fi

echo ""
echo "=== Install complete! ==="
echo "Reboot and remove the install media."
echo ""
