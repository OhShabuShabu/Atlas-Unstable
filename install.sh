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
info()   { echo -e "  ${CYAN}→${NC} $1"; }
ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
spacer() { echo ""; }

# ─── Step Progress (refreshes in place) ──────────────────────────────
step() {
  local num=$1 total=$TOTAL_STEPS title="$2"
  local pct=$((num * 100 / total))
  local fill=$((num * 36 / total))
  printf -v bar '%*s' "$fill" ''; bar="${bar// /━}"
  printf -v rest '%*s' $((36-fill)) ''; rest="${rest// /─}"
  if [[ ${STEP_PRINTED:-0} -eq 1 ]]; then
    printf '\e[H\e[J'    # home + clear screen — reliable across scrolls
  fi
  echo
  echo -e "  ${CYAN}${bar}${DIM}${rest}${NC}  ${BOLD}${pct}%${NC}  ${DIM}Step ${num}/${total}${NC}"
  echo -e "  ${BOLD}${CYAN}▶${NC} ${BOLD}${title}${NC}"
  echo
  STEP_PRINTED=1
}

# ─── Braille Spinner ─────────────────────────────────────────────────────
SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spin() {
  local pid=$1 msg="${2:-Working...}"
  local i=0
  printf '\e[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${NC} %s " "${SPIN:$i:1}" "$msg"
    i=$(((i+1)%${#SPIN}))
    sleep 0.08
  done
  printf '\e[?25h'
  printf "\r  ${GREEN}✓${NC} %s\n" "$msg"
}

# ─── Elapsed Timer ──────────────────────────────────────────────────────
timer_until() {
  local pid=$1 start=$SECONDS label="${2:-Elapsed}"
  printf '\e[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    local e=$((SECONDS - start))
    printf "\r  ${CYAN}⏱${NC} ${label}: ${BOLD}%02d:%02d${NC}" $((e/60)) $((e%60))
    sleep 1
  done
  local e=$((SECONDS - start))
  printf "\r  ${GREEN}✓${NC} ${label}: ${BOLD}%02d:%02d${NC}\n" $((e/60)) $((e%60))
  printf '\e[?25h'
}

TOTAL_STEPS=9
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
  echo -e "    ${DIM}• LUKS-encrypted Btrfs partition (all remaining space)${NC}"
  echo -e "    ${DIM}  - Subvolumes: /nix, /persistent, /var${NC}"
  echo -e "    ${DIM}• tmpfs for /, /home, and /tmp${NC}"
  echo -e "    ${DIM}• Swap file on encrypted /persistent subvol${NC}"
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

(nix-collect-garbage 2>/dev/null || true) &
spin $! "Clearing Nix garbage on live ISO"
wait $!

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

# ─── LUKS Passphrase ────────────────────────────────────────────────────
echo -e "  ${BOLD}Set a LUKS encryption passphrase for ${DISK}:${NC}"
echo -e "  ${DIM}This passphrase will be needed at every boot.${NC}"
while :; do
  read -r -s -p "  ${CYAN}Passphrase:${NC} " LUKS_PW1
  echo
  read -r -s -p "  ${CYAN}Confirm:${NC}  " LUKS_PW2
  echo
  if [[ -z "$LUKS_PW1" ]]; then
    warn "Passphrase cannot be empty."
  elif [[ "$LUKS_PW1" != "$LUKS_PW2" ]]; then
    warn "Passphrases do not match."
  else
    break
  fi
done
echo -n "$LUKS_PW1" > /tmp/luks-passphrase
unset LUKS_PW1 LUKS_PW2
ok "LUKS passphrase confirmed"
spacer

# ─── Disko Config ───────────────────────────────────────────────────────
info "Writing partition layout via disko..."
info "  ${DIM}This will create: ESP (2G), LUKS+Btrfs (remaining), tmpfs for /, /home, /tmp${NC}"

cat > /tmp/disko-config.nix << EOF
{
  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = ["size=25%" "mode=755"];
    };
    nodev."/tmp" = {
      fsType = "tmpfs";
      mountOptions = ["size=25%" "mode=1777"];
    };
    nodev."/home" = {
      fsType = "tmpfs";
      mountOptions = ["size=25%" "mode=755"];
    };
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
          # No swap partition — everything on disk is inside LUKS.
          # Swap is a file on the LUKS-encrypted /persistent btrfs subvol.
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypt";
              settings.allowDiscards = true;
              passwordFile = "/tmp/luks-passphrase";
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "/nix" = { mountOptions = ["subvol=nix" "noatime"]; mountpoint = "/nix"; };
                  "/persistent" = { mountOptions = ["subvol=persistent" "noatime"]; mountpoint = "/persistent"; };
                  # /home is tmpfs — user data is persisted via bind mounts from
                  # /persistent/home/yusa/, configured in preservation.nix
                  "/var" = { mountOptions = ["subvol=var" "noatime"]; mountpoint = "/var"; };
                };
              };
            };
          };
        };
      };
    };
  };
}
EOF

# ─── Run disko ─────────────────────────────────────────────────────────
info "Running disko to partition and format..."
nix run "nixpkgs#disko" \
  --extra-experimental-features "nix-command flakes" \
  --accept-flake-config \
  -- --mode disko /tmp/disko-config.nix > /tmp/disko-format.log 2>&1 &
DISKO_PID=$!
spin $DISKO_PID "Partitioning & formatting disk"
if wait $DISKO_PID 2>/dev/null; then
  ok "Disk partitioned and formatted"
else
  DISKO_EXIT=$?
  rm -f /tmp/luks-passphrase
  fail "disko partitioning failed (exit $DISKO_EXIT)"
  echo -e "  ${DIM}Last output:${NC}"
  tail -5 /tmp/disko-format.log 2>/dev/null | sed 's/^/  /'
  exit 1
fi
rm -f /tmp/luks-passphrase

# ═══════════════════════════════════════════════════════════════════════════
# STEP 6: Mounting & Installing NixOS
# ═══════════════════════════════════════════════════════════════════════════
step 6 "Mounting & Installing NixOS"
spacer

TARGET=/mnt

# Accept flake config prompts automatically (avoids Noctilia GUI dialog on desktop)
export NIX_ACCEPT_FLAKE_CONFIG=1

# ─── Detect partitions ─────────────────────────────────────────────────────────
sub_header() { echo -e "  ${CYAN}▸${NC} ${BOLD}$1${NC}"; }

sub_header "Detecting partitions"
LUKS_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep crypto_LUKS | awk '{print $1}')
BOOT_PART=$(lsblk -lno PATH,FSTYPE "$DISK" | grep vfat | awk '{print $1}')
LUKS_UUID=$(blkid -o value -s UUID "$LUKS_PART" 2>/dev/null || true)
ok "LUKS root:  ${BOLD}$LUKS_PART${NC}  (UUID: $LUKS_UUID)"
ok "ESP boot:   ${BOLD}$BOOT_PART${NC}"
spacer

# ─── LUKS unlock ───────────────────────────────────────────────────────────────
sub_header "Unlocking LUKS encryption"
if ! cryptsetup status crypt &>/dev/null; then
  echo -e "  ${DIM}Enter your LUKS passphrase to unlock:${NC}"
  echo -e "  ${DIM}  Device: ${BOLD}$LUKS_PART${NC}${DIM}  UUID: $LUKS_UUID${NC}"
  cryptsetup open "$LUKS_PART" crypt
fi
ok "LUKS device opened"
spacer

# ─── Mount subvolumes ──────────────────────────────────────────────────────────
sub_header "Mounting Btrfs subvolumes"
mount -t btrfs -o subvol=nix,noatime /dev/mapper/crypt "$TARGET/nix"
ok "Mounted /nix"
mount -t btrfs -o subvol=persistent,noatime /dev/mapper/crypt "$TARGET/persistent"
ok "Mounted /persistent"
mkdir -p "$TARGET/home"
ok "Prepared /home (tmpfs — will be mounted at boot)"
mount -t btrfs -o subvol=var,noatime /dev/mapper/crypt "$TARGET/var"
ok "Mounted /var"
mount "$BOOT_PART" "$TARGET/boot"
ok "Mounted /boot (ESP)"
spacer

# ─── Password Prompt & Injection ──────────────────────────────────────────────
sub_header "Configuring user password"
if [[ "$AUTO" -eq 0 ]]; then
  info "Set a password for user '${BOLD}yusa${NC}':"
  while :; do
    read -r -s -p "  ${CYAN}Password:${NC} " PW1
    echo
    read -r -s -p "  ${CYAN}Confirm:${NC}  " PW2
    echo
    if [[ -z "$PW1" ]]; then
      warn "Password cannot be empty."
    elif [[ "$PW1" != "$PW2" ]]; then
      warn "Passwords do not match."
    else
      break
    fi
  done
  PW="${PW1}"
else
  PW="atlas"
  info "Auto-mode: using default password"
fi
ok "Password set"
spacer

# ─── Inject password into config ──────────────────────────────────────────────
sub_header "Injecting password into Nix configuration"
PW_SAFE="${PW//\"/\\\"}"
sed -i '/description = "yusa";/a\    initialPassword = "'"$PW_SAFE"'";' \
  "$ROOTDIR/files/core/configuration.nix" && \
  ok "Password injected (NixOS will hash on first boot)" || \
  warn "Could not inject password into configuration.nix"
spacer

# ─── nixos-install ─────────────────────────────────────────────────────────────
sub_header "Running nixos-install"
info "${DIM}Installing NixOS to disk — this takes 5-30 minutes.${NC}"
echo

export DISKO_DEVICE="$DISK"
echo "$LUKS_UUID" > "$ROOTDIR/.luk-uuid"

trap 'rm -f "$ROOTDIR/.luk-uuid"' EXIT

if [[ -n "$CACHE_URL" ]]; then
  SUBSTITUTERS="$CACHE_URL https://cache.nixos.org"
else
  SUBSTITUTERS="https://cache.nixos.org"
fi

INSTALL_START=$SECONDS

nixos-install --flake "$ROOTDIR#atlas-installer" \
  --root "$TARGET" \
  --no-root-passwd \
  --show-trace \
  --option substituters "$SUBSTITUTERS" \
  > /tmp/nixos-install.log 2>&1 &
NIX_PID=$!

printf '\e[?25l'
while kill -0 "$NIX_PID" 2>/dev/null; do
  ELAPSED=$((SECONDS - INSTALL_START))
  STATUS=$(tail -1 /tmp/nixos-install.log 2>/dev/null | tr '\n' ' ' | head -c 65)
  printf "\r  ⏱ %02d:%02d  ${DIM}%s${NC}\033[K" $((ELAPSED/60)) $((ELAPSED%60)) "$STATUS"
  sleep 5
done
printf '\r\033[K\e[?25h'

# Guard against set -e — wait kills the script silently if nixos-install fails
if wait "$NIX_PID" 2>/dev/null; then
  NIX_EXIT=0
else
  NIX_EXIT=$?
fi
TOTAL=$((SECONDS - INSTALL_START))

sed -i '/initialPassword\|initialHashedPassword/d' "$ROOTDIR/files/core/configuration.nix" 2>/dev/null || true

if [[ $NIX_EXIT -eq 0 ]]; then
  echo
  ok "NixOS base system installed (${BOLD}$((TOTAL/60))m $((TOTAL%60))s${NC})"
else
  echo
  fail "nixos-install failed (exit $NIX_EXIT)"
  echo -e "  ${DIM}Full log (last 30 lines):${NC}"
  tail -30 /tmp/nixos-install.log 2>/dev/null | sed 's/^/  /'
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 7: Copy Configuration to Installed System
# ═══════════════════════════════════════════════════════════════════════════
step 7 "Copying Configuration"
spacer

info "Persisting machine-id..."
mkdir -p "$TARGET/persistent/etc"
cp "$TARGET/etc/machine-id" "$TARGET/persistent/etc/machine-id" 2>/dev/null || true
ok "Machine-id saved"

info "Copying configuration to installed system (persistent storage)..."
mkdir -p "$TARGET/persistent/home/yusa"
cp -r "$ROOTDIR" "$TARGET/persistent/home/yusa/Atlas"
chown -R 1000:100 "$TARGET/persistent/home/yusa/Atlas" 2>/dev/null || true
ok "Config copied to /persistent/home/yusa/Atlas"

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
MODULE_DESC[9]="extras     — AI/ML (Ollama ROCm), animated wallpapers"

declare -A MODULE_FILE
MODULE_FILE[1]="performance.nix"
MODULE_FILE[2]="privacy/privacy.nix"
MODULE_FILE[3]="gaming/gaming.nix"
MODULE_FILE[4]="virtualisation.nix"
MODULE_FILE[5]="minecraft.nix"
MODULE_FILE[6]="flatpak.nix"
MODULE_FILE[7]="dev/dev.nix"
MODULE_FILE[8]="tools.nix"
MODULE_FILE[9]="extras.nix"

declare -A MODULE_DIR
MODULE_DIR[1]="nixos"
MODULE_DIR[2]="nixos"
MODULE_DIR[3]="nixos"
MODULE_DIR[4]="nixos"
MODULE_DIR[5]="nixos"
MODULE_DIR[6]="nixos"
MODULE_DIR[7]="home"
MODULE_DIR[8]="home"
MODULE_DIR[9]="nixos"

if [[ "$AUTO" -eq 0 ]]; then
  TOGGLED=(0 0 0 0 0 0 0 0 0 0)

  echo -e "  ${BOLD}Select optional modules to install:${NC}"
  echo -e "  ${DIM}(type a number to toggle it on/off, press Enter when done)${NC}"
  spacer

  while :; do
    for i in 1 2 3 4 5 6 7 8 9; do
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
    elif [[ "$ANS" =~ ^[0-9]$ ]]; then
      TOGGLED[$ANS]=$((1 - ${TOGGLED[$ANS]:-0}))
    fi
    echo -en "\033[10A"
  done

  for i in 1 2 3 4 5 6 7 8 9; do
    if [[ "${TOGGLED[$i]:-0}" -eq 1 ]]; then
      SELECTED_MODULES+=("$i")
    fi
  done
else
  SELECTED_MODULES=(1 2 3 4 5 6 7 8 9)
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
    ($CURL -sSo "$DEST" "$RAW_URL/$FILE" 2>/dev/null) &
    spin $! "Downloading ${FILENAME}"
    wait $!
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

# ─── GPU Detection (auto) ─────────────────────────────────────────────────
# Detect GPU vendor and download ONLY the matching initrd module.
# Bundling GPU firmware for hardware that doesn't exist fills up /boot.
spacer
info "Detecting GPU for initrd configuration..."

VENDOR=$(head -1 /sys/class/drm/*/device/vendor 2>/dev/null | tr -d '\n')
case "$VENDOR" in
  "0x1002") GPU_MODULE="gpu-amd.nix"   ; GPU_NAME="AMD" ;;
  "0x8086") GPU_MODULE="gpu-intel.nix" ; GPU_NAME="Intel" ;;
  "0x10de") GPU_MODULE="gpu-nvidia.nix"; GPU_NAME="NVIDIA" ;;
  *) GPU_MODULE="" ; GPU_NAME="" ;;
esac

if [[ -n "$GPU_MODULE" ]]; then
  info "Detected ${GPU_NAME} GPU — downloading matching initrd module..."
  mkdir -p "$OPT_DIR/nixos"
  ($CURL -sSo "$OPT_DIR/nixos/gpu.nix" "$RAW_URL/$GPU_MODULE" 2>/dev/null) &
  spin $! "Downloading ${GPU_MODULE}"
  wait $!
  ok "GPU initrd module installed: ${GPU_MODULE}"
else
  warn "No supported GPU detected — initrd will use basic framebuffer (no KMS)."
  warn "You can manually download gpu-amd.nix, gpu-intel.nix, or gpu-nvidia.nix"
  warn "from the atlas-modules repo to files/modules/optional/nixos/gpu.nix"
fi

# ═══════════════════════════════════════════════════════════════════════════
# STEP 9: Apply Full Configuration (includes optional modules)
# ═══════════════════════════════════════════════════════════════════════════
step 9 "Applying Full Configuration"
spacer

info "Running nixos-rebuild switch to activate the configuration..."
info "${DIM}This installs all selected optional modules.${NC}"
echo

if command -v nixos-enter &>/dev/null; then
  nixos-enter --root "$TARGET" -c "nixos-rebuild switch --flake /persistent/home/yusa/Atlas#atlas" \
    > /tmp/nixos-rebuild.log 2>&1 &
  REBUILD_PID=$!
  timer_until $REBUILD_PID "nixos-rebuild"
  if wait $REBUILD_PID 2>/dev/null; then
    ok "Full configuration applied (including optional modules)"
  else
    warn "nixos-rebuild had issues — run it manually after first boot:"
    echo -e "       ${DIM}sudo nixos-rebuild switch --flake /home/yusa/Atlas#atlas${NC}"
  fi
else
  warn "nixos-enter not found — run nixos-rebuild manually after first boot:"
  echo -e "       ${DIM}sudo nixos-rebuild switch --flake /home/yusa/Atlas#atlas${NC}"
fi

# ─── Next Steps ──────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - SCRIPT_START ))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

spacer
echo -e "  ${BOLD}Install complete (${ELAPSED_MIN}m ${ELAPSED_SEC}s)${NC}"
echo
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    ${CYAN}1.${NC} Reboot and remove the install media"
echo -e "    ${CYAN}2.${NC} Boot into your new system"
echo -e "    ${CYAN}3.${NC} Log in with ${YELLOW}username: yusa${NC}"
if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
  echo -e "    ${CYAN}4.${NC} Apply the full configuration and add optional modules:"
  echo -e "       ${DIM}sudo nixos-rebuild switch --flake /home/yusa/Atlas#atlas${NC}"
fi
echo
echo -e "  ${DIM}For detailed documentation, see: /home/yusa/Atlas/README.md${NC}"
