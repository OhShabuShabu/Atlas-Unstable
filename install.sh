#!/usr/bin/env bash
set -euo pipefail

ROOTDIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Must be run as root (you're in a NixOS live ISO, use sudo)." >&2
  exit 1
fi

if ! command -v nix &>/dev/null; then
  echo "nix not found. Are you in a NixOS live ISO?" >&2
  exit 1
fi

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
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

AVAILABLE=($(lsblk -dpno NAME 2>/dev/null | grep -E '/dev/(sd|nvme|vd|mmcblk)' || true))
if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
  echo "No disks detected." >&2
  exit 1
fi

echo "Available disks:"
for i in "${!AVAILABLE[@]}"; do
  DEV="${AVAILABLE[$i]}"
  SIZE=$(lsblk -dno SIZE "$DEV" 2>/dev/null || echo "?")
  MODEL=$(lsblk -dno MODEL "$DEV" 2>/dev/null || echo "")
  echo "  $((i+1)). $DEV  ($SIZE)  $MODEL"
done
echo ""

DISK=""
while [[ -z "$DISK" ]]; do
  read -rp "Select disk number [1-${#AVAILABLE[@]}]: " SEL
  if [[ "$SEL" =~ ^[0-9]+$ ]] && [[ "$SEL" -ge 1 ]] && [[ "$SEL" -le "${#AVAILABLE[@]}" ]]; then
    DISK="${AVAILABLE[$((SEL-1))]}"
  else
    echo "Invalid selection." >&2
  fi
done

echo ""
echo "Selected: $DISK"
echo ""
lsblk "$DISK"
echo ""
echo "WARNING: ALL DATA on $DISK will be DESTROYED."
read -rp 'Type "YES" to continue: ' CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

# Create swap file if memory is low
TOTAL_MEM=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
if [[ "$TOTAL_MEM" -lt 4096 ]]; then
  echo ""
  echo "Low memory detected (${TOTAL_MEM}MB). Creating 4G swap file..."
  fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "Swap enabled."
fi

echo ""
echo "=== Running disko-install ==="
echo ""

nix --extra-experimental-features "nix-command flakes" \
  --max-jobs 1 --cores 0 \
  run 'github:nix-community/disko/latest#disko-install' -- \
  --flake "$ROOTDIR#atlas-installer" \
  --disk main "$DISK"
