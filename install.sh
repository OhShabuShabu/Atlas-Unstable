#!/usr/bin/env bash
set -euo pipefail

ROOTDIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Colors ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

# ─── Config ─────────────────────────────────────────────────────────────────
AUTO=0
CACHE_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)   AUTO=1; shift ;;
    -c|--cache) CACHE_URL="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

# ─── Helpers ────────────────────────────────────────────────────────────────
step()   { echo -e "\n${CYAN}${BOLD}═══ Step ${1}/${TOTAL_STEPS}: ${2} ═══${NC}"; }
info()   { echo -e "  ${CYAN}→${NC} $1"; }
ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
spacer() { echo ""; }

TOTAL_STEPS=8
SCRIPT_START=$(date +%s)

# ═══════════════════════════════════════════════════════════════════════════
# STEP 1: Environment Checks
# ═══════════════════════════════════════════════════════════════════════════
step 1 "Checking Environment"
spacer

if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root."
  echo -e "  ${DIM}You're in a NixOS live ISO; use: sudo ./install.sh${NC}"
  exit 1
fi
ok "Running as root"

if ! command -v nix &>/dev/null; then
  fail "nix command not found."
  echo -e "  ${DIM}Are you in a NixOS live ISO?${NC}"
  exit 1
fi
ok "Nix is available"

TOTAL_MEM=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
ok "Detected ${TOTAL_MEM}MB RAM"

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ $AUTO -eq 0 ]]; then
    warn "Running from a desktop session."
    echo -e "  ${YELLOW}The install is memory-intensive and your DE may kill the${NC}"
    echo -e "  ${YELLOW}terminal (OOM). Switch to a TTY for best results:${NC}"
    echo -e "  ${BOLD}    Ctrl+Alt+F3   then run:  sudo ./install.sh${NC}"
    spacer
    read -rp "$(echo -e ${YELLOW}"  Continue anyway? (y/N): "${NC})" ANS
    if [[ "$ANS" != "y" && "$ANS" != "Y" ]]; then
      echo -e "  ${RED}Aborted by user.${NC}"
      exit 1
    fi
  else
    warn "Running from desktop (auto-mode, continuing)"
  fi
fi
ok "Environment checks passed"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 2: Disk Selection
# ═══════════════════════════════════════════════════════════════════════════
step 2 "Selecting Target Disk"
spacer

AVAILABLE=($(lsblk -dpno NAME,TYPE 2>/dev/null | awk '/disk/ {print $1}'))
if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
  fail "No disks detected."
  echo -e "  ${DIM}Check that a drive is connected and visible to the system.${NC}"
  exit 1
fi

if [[ ${#AVAILABLE[@]} -eq 1 ]]; then
  DISK="${AVAILABLE[0]}"
  info "Single disk detected: ${BOLD}$DISK${NC} ($(lsblk -dno SIZE "$DISK" 2>/dev/null || echo "?"))"
elif [[ $AUTO -eq 1 ]]; then
  DISK="${AVAILABLE[0]}"
  warn "Multiple disks detected — using first: ${BOLD}$DISK${NC}"
else
  echo -e "  ${BOLD}Available disks:${NC}"
  for i in "${!AVAILABLE[@]}"; do
    DEV="${AVAILABLE[$i]}"
    SIZE=$(lsblk -dno SIZE "$DEV" 2>/dev/null || echo "?")
    MODEL=$(lsblk -dno MODEL "$DEV" 2>/dev/null || echo "")
    echo -e "    $((i+1)). ${DEV}  ${DIM}(${SIZE})${NC}  ${MODEL}"
  done
  spacer
  while [[ -z "${DISK:-}" ]]; do
    read -rp "$(echo -e ${CYAN}"  Select disk number [1-${#AVAILABLE[@]}]: "${NC})" SEL
    if [[ "$SEL" =~ ^[0-9]+$ ]] && [[ "$SEL" -ge 1 ]] && [[ "$SEL" -le "${#AVAILABLE[@]}" ]]; then
      DISK="${AVAILABLE[$((SEL-1))]}"
    else
      echo -e "  ${RED}Invalid selection.${NC}"
    fi
  done
fi

spacer
echo -e "  ${BOLD}Selected disk:${NC} $DISK"
lsblk "$DISK" | sed 's/^/    /'

# ═══════════════════════════════════════════════════════════════════════════
# STEP 3: Confirmation (Destructive Action)
# ═══════════════════════════════════════════════════════════════════════════
step 3 "Confirm Installation"
spacer

if [[ $AUTO -eq 0 ]]; then
  warn "${BOLD}This will ERASE ALL DATA on $DISK${NC}"
  echo -e "  ${YELLOW}The disk will be repartitioned and encrypted with LUKS.${NC}"
  echo -e "  ${YELLOW}This action ${BOLD}cannot${NC}${YELLOW} be undone.${NC}"
  spacer
  echo -e "  ${DIM}What will be created:${NC}"
  echo -e "    ${DIM}• 2GB EFI System Partition (ESP)${NC}"
  echo -e "    ${DIM}• 8GB Swap partition${NC}"
  echo -e "    ${DIM}• LUKS-encrypted Btrfs partition (remaining space)${NC}"
  echo -e "    ${DIM}  - Subvolumes: /nix, /persistent, /home, /var${NC}"
  echo -e "    ${DIM}• tmpfs for / and /tmp${NC}"
  spacer
  read -rp "$(echo -e ${RED}"  Type 'yes' to continue: "${NC})" CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "  ${YELLOW}Installation cancelled.${NC}"
    exit 1
  fi
else
  info "Auto-mode enabled — skipping confirmation"
fi
ok "Proceeding with installation"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 4: Preparing System Resources
# ═══════════════════════════════════════════════════════════════════════════
step 4 "Preparing System Resources"
spacer

info "Clearing Nix garbage on live ISO..."
nix-collect-garbage 2>/dev/null || true
ok "Garbage collection done"

# Expand live ISO writable store so nix has room to build
for MP in /nix/.rw-store / ; do
  if mountpoint -q "$MP" 2>/dev/null; then
    FS_TYPE=$(findmnt -n -o FSTYPE "$MP")
    if [[ "$FS_TYPE" == "tmpfs" ]]; then
      NEW_SIZE=$((TOTAL_MEM * 9 / 10))M
      mount -o remount,size="$NEW_SIZE" "$MP" 2>/dev/null && info "Expanded $MP to $NEW_SIZE"
    fi
  fi
done
ok "Live ISO store expanded"

# Create zram swap if low memory
if [[ "$TOTAL_MEM" -lt 8192 ]] && ! swapon --show | grep -q .; then
  info "Low memory (${TOTAL_MEM}MB) — creating compressed swap..."
  modprobe zram 2>/dev/null || true
  echo "$((TOTAL_MEM / 2))M" > /sys/block/zram0/disksize 2>/dev/null || true
  mkswap /dev/zram0 2>/dev/null || true
  swapon /dev/zram0 -p 10 2>/dev/null || true
  ok "zram swap enabled ($((TOTAL_MEM / 2))MB, compressed)"
fi

info "Freeing page cache..."
sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
ok "System resources ready"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 5: Partitioning & Formatting
# ═══════════════════════════════════════════════════════════════════════════
step 5 "Partitioning & Formatting $DISK"
spacer

info "Writing partition layout via disko..."
info "  ${DIM}This will create: ESP (2G), Swap (8G), LUKS+Btrfs (remaining)${NC}"

# Write the disko config as Nix
cat > /tmp/disko-config.nix << EOF
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "$DISK";
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

info "Running disko (this may prompt for LUKS passphrase)..."
nix run "nixpkgs#disko" \
  --extra-experimental-features "nix-command flakes" \
  -- --mode disko /tmp/disko-config.nix
ok "Disk partitioned and formatted"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: Mounting & Installing NixOS
# ═══════════════════════════════════════════════════════════════════════════
step 6 "Mounting & Installing NixOS"
spacer

TARGET=/mnt

LUKS_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep crypto_LUKS | awk '{print $1}')
BOOT_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep vfat | awk '{print $1}')
LUKS_UUID=$(blkid -o value -s UUID "$LUKS_PART" 2>/dev/null || true)

info "LUKS root:  ${BOLD}$LUKS_PART${NC}  (UUID: $LUKS_UUID)"
info "ESP boot:   ${BOLD}$BOOT_PART${NC}"
spacer

if ! cryptsetup status crypt &>/dev/null; then
  info "Opening LUKS device (enter your passphrase)..."
  cryptsetup open "$LUKS_PART" crypt
fi
ok "LUKS device opened"

info "Mounting Btrfs subvolumes..."
mount -t btrfs -o subvol=nix,noatime /dev/mapper/crypt "$TARGET/nix"
mount -t btrfs -o subvol=persistent,noatime /dev/mapper/crypt "$TARGET/persistent"
mount -t btrfs -o subvol=home,noatime /dev/mapper/crypt "$TARGET/home"
mount -t btrfs -o subvol=var,noatime /dev/mapper/crypt "$TARGET/var"
mount "$BOOT_PART" "$TARGET/boot"
ok "Subvolumes mounted"

# ─── Password Prompt & Injection ──────────────────────────────────────────────
if [[ "$AUTO" -eq 0 ]]; then
  spacer
  echo -e "  ${BOLD}Set a password for user 'yusa':${NC}"
  while :; do
    read -r -s -p "  ${CYAN}Password:${NC} " PW1
    echo
    read -r -s -p "  ${CYAN}Confirm:${NC}  " PW2
    echo
    if [[ -z "$PW1" ]]; then
      echo -e "  ${YELLOW}Password cannot be empty.${NC}"
    elif [[ "$PW1" != "$PW2" ]]; then
      echo -e "  ${YELLOW}Passwords do not match.${NC}"
    else
      break
    fi
  done
  PW="${PW1}"
else
  PW="atlas"
fi

info "Injecting password into Nix config..."
PW_SAFE="${PW//\"/\\\"}"
sed -i '/description = "yusa";/a\    initialPassword = "'"$PW_SAFE"'";' \
  "$ROOTDIR/files/core/configuration.nix" && \
  ok "Password injected (NixOS will hash on first boot)" || \
  warn "Could not inject password into configuration.nix"

info "Running nixos-install (this will take 5-30 minutes)..."
export DISKO_DEVICE="$DISK"
echo "$LUKS_UUID" > "$ROOTDIR/.luk-uuid"

trap 'rm -f "$ROOTDIR/.luk-uuid"' EXIT

if [[ -n "$CACHE_URL" ]]; then
  SUBSTITUTERS="$CACHE_URL https://cache.nixos.org"
else
  SUBSTITUTERS="https://cache.nixos.org"
fi

nixos-install --flake "$ROOTDIR#atlas-installer" \
  --root "$TARGET" \
  --no-root-passwd \
  --option substituters "$SUBSTITUTERS"
ok "NixOS base system installed"

sed -i '/initialPassword\|initialHashedPassword/d' "$ROOTDIR/files/core/configuration.nix" || true
ok "Password cleaned from source config"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7: Copy Configuration to Installed System
# ═══════════════════════════════════════════════════════════════════════════
step 7 "Copying Configuration"
spacer

info "Persisting machine-id..."
mkdir -p "$TARGET/persistent/etc"
cp "$TARGET/etc/machine-id" "$TARGET/persistent/etc/machine-id" 2>/dev/null || true
ok "Machine-id saved"

info "Copying configuration to installed system..."
mkdir -p "$TARGET/home/yusa"
cp -r "$ROOTDIR" "$TARGET/home/yusa/atlas"
chown -R 1000:100 "$TARGET/home/yusa/atlas" 2>/dev/null || true
ok "Config copied to /home/yusa/atlas"

# ═══════════════════════════════════════════════════════════════════════════
# STEP 8: Optional Modules (multi-select)
# ═══════════════════════════════════════════════════════════════════════════
step 8 "Optional Modules (Gaming, Dev, Privacy, etc.)"
spacer

RAW_URL="https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main"
OPT_DIR="$TARGET/home/yusa/atlas/files/modules/optional"
SELECTED_MODULES=()

declare -A MODULE_DESC
MODULE_DESC[1]="performance — CPU governor, TCP BBR, Nix GC tuning"
MODULE_DESC[2]="privacy    — Mullvad VPN, metadata cleaner"
MODULE_DESC[3]="gaming     — Steam, MangoHUD overlay"
MODULE_DESC[4]="virtualisation — Docker, Podman, libvirt"
MODULE_DESC[5]="minecraft  — PrismLauncher, Blockbench"
MODULE_DESC[6]="flatpak    — Flathub repository"
MODULE_DESC[7]="dev        — Neovim, VSCodium, bun, opencode"
MODULE_DESC[8]="tools      — yt-dlp, mpv"

declare -A MODULE_FILE
MODULE_FILE[1]="performance.nix"
MODULE_FILE[2]="privacy/privacy.nix"
MODULE_FILE[3]="gaming/gaming.nix"
MODULE_FILE[4]="virtualisation.nix"
MODULE_FILE[5]="minecraft.nix"
MODULE_FILE[6]="flatpak.nix"
MODULE_FILE[7]="dev/dev.nix"
MODULE_FILE[8]="tools.nix"

declare -A MODULE_DIR
MODULE_DIR[1]="nixos"
MODULE_DIR[2]="nixos"
MODULE_DIR[3]="nixos"
MODULE_DIR[4]="nixos"
MODULE_DIR[5]="nixos"
MODULE_DIR[6]="nixos"
MODULE_DIR[7]="home"
MODULE_DIR[8]="home"

if [[ "$AUTO" -eq 0 ]]; then
  TOGGLED=(0 0 0 0 0 0 0 0 0)

  echo -e "  ${BOLD}Select optional modules to install:${NC}"
  echo -e "  ${DIM}(type a number to toggle it on/off, press Enter when done)${NC}"
  spacer

  while :; do
    for i in 1 2 3 4 5 6 7 8; do
      MARK="${TOGGLED[$i]:-0}"
      if [[ "$MARK" -eq 1 ]]; then
        echo -e "    ${GREEN}[x]${NC} ${CYAN}$i${NC}) ${MODULE_DESC[$i]}"
      else
        echo -e "    ${DIM}[ ]${NC} ${CYAN}$i${NC}) ${MODULE_DESC[$i]}"
      fi
    done
    spacer
    read -rp "$(echo -e ${CYAN}"  Toggle number (or Enter to confirm): "${NC})" ANS
    if [[ -z "$ANS" ]]; then
      break
    elif [[ "$ANS" =~ ^[0-8]$ ]]; then
      TOGGLED[$ANS]=$((1 - ${TOGGLED[$ANS]:-0}))
    fi
    echo -en "\033[10A"
  done

  for i in 1 2 3 4 5 6 7 8; do
    if [[ "${TOGGLED[$i]:-0}" -eq 1 ]]; then
      SELECTED_MODULES+=("$i")
    fi
  done
else
  SELECTED_MODULES=(1 2 3 4 5 6 7 8)
fi

if [[ ${#SELECTED_MODULES[@]} -gt 0 ]]; then
  info "Downloading selected modules from $RAW_URL ..."

  if command -v curl &>/dev/null; then
    CURL="curl"
  else
    CURL="nix run nixpkgs#curl --"
  fi

  for s in "${SELECTED_MODULES[@]}"; do
    TYPE="${MODULE_DIR[$s]}"
    FILE="${MODULE_FILE[$s]}"
    FILENAME=$(basename "$FILE")
    DEST="$OPT_DIR/$TYPE/$FILENAME"

    mkdir -p "$OPT_DIR/$TYPE"
    $CURL -sSo "$DEST" "$RAW_URL/$FILE" 2>&1 | sed 's/^/    /'
    ok "Downloaded ${FILENAME}"
  done

  chown -R 1000:100 "$OPT_DIR" 2>/dev/null || true

  selected_names=()
  for s in "${SELECTED_MODULES[@]}"; do
    selected_names+=("${MODULE_DESC[$s]%% -*}")
  done
  ok "Enabled: ${selected_names[*]}"
else
  info "No modules selected — you can add them later by downloading .nix files to files/modules/optional/"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - SCRIPT_START ))
header "Install Complete!"
echo -e "  ${GREEN}${BOLD}Atlas has been installed successfully!${NC}"
echo -e "  ${DIM}Total time: ${ELAPSED}s${NC}"
spacer
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. ${CYAN}Reboot${NC} and remove the install media"
echo -e "    2. Boot into your new system"
echo -e "    3. Log in with ${YELLOW}username: yusa${NC}"
echo -e "    4. After login, apply the full configuration:"
echo -e "       ${DIM}sudo nixos-rebuild switch --flake /home/yusa/atlas#atlas${NC}"
if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
  echo -e "    5. To add optional modules later:"
  echo -e "       ${DIM}Download .nix files to /home/yusa/atlas/files/modules/optional/nixos/ or home/${NC}"
  echo -e "       ${DIM}They're auto-imported from the directory.${NC}"
fi
spacer
echo -e "  ${DIM}For detailed documentation, see: /home/yusa/atlas/README.md${NC}"
