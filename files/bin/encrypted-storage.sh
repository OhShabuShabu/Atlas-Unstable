#!/usr/bin/env bash
set -euo pipefail

CIPHER_DIR="/persistent/home/yusa/.encrypted-storage"
MOUNT_POINT="/home/yusa/Encrypted Storage"
GOCRYPTFS_OPTS="-quiet -nosyslog -deterministic-names"

if [ -n "${YORHA_LIB_DIR:-}" ]; then
  source "$YORHA_LIB_DIR/tui.sh"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
  source "$SCRIPT_DIR/files/lib/tui.sh"
fi

check_gocryptfs() {
  if ! command -v gocryptfs &>/dev/null; then
    fail "gocryptfs is not installed."
    echo "  Add gocryptfs to environment.systemPackages and rebuild."
    exit 1
  fi
}

check_not_mounted() {
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    warn "Already mounted at $MOUNT_POINT"
    exit 0
  fi
}

check_mounted() {
  if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    fail "Not mounted at $MOUNT_POINT"
    exit 1
  fi
}

is_initialized() {
  [[ -f "$CIPHER_DIR/gocryptfs.conf" ]]
}

cmd_init() {
  check_gocryptfs
  sudo -v
  if is_initialized; then
    warn "Encrypted storage already initialized at $CIPHER_DIR"
    echo "  Use 'encrypted-storage passwd' to change the password."
    exit 0
  fi

  tui_header "Initialize Encrypted Storage"
  echo "  Cipher directory: $CIPHER_DIR"
  echo "  Mount point:      $MOUNT_POINT"
  echo "  Method:           gocryptfs (AES-256-GCM, per-file encryption)"
  echo ""

  if [[ -d "$CIPHER_DIR" ]] && [[ "$(ls -A "$CIPHER_DIR" 2>/dev/null)" ]]; then
    warn "Cipher directory $CIPHER_DIR already exists and is not empty."
    echo "  If you want to re-initialize, remove it first:"
    echo "    sudo rm -rf '$CIPHER_DIR'"
    echo ""
    exit 1
  fi

  info "Creating cipher directory..."
  sudo mkdir -p "$CIPHER_DIR"
  sudo chown "$USER:" "$CIPHER_DIR"

  info "Initializing gocryptfs filesystem..."
  echo ""
  gocryptfs -init "$CIPHER_DIR"
  echo ""

  if is_initialized; then
    ok "Encrypted storage initialized."
    echo ""
    info "Run 'encrypted-storage mount' to mount it."
  else
    fail "Initialization failed."
    exit 1
  fi
}

cmd_mount() {
  check_gocryptfs
  check_not_mounted

  if ! is_initialized; then
    fail "Not initialized. Run 'encrypted-storage init' first."
    exit 1
  fi

  mkdir -p "$MOUNT_POINT"

  tui_header "Mount Encrypted Storage"
  info "Mounting $CIPHER_DIR → $MOUNT_POINT"
  echo ""

  if gocryptfs $GOCRYPTFS_OPTS "$CIPHER_DIR" "$MOUNT_POINT"; then
    echo ""
    ok "Mounted at $MOUNT_POINT"
    echo ""
    info "Use 'encrypted-storage umount' to unmount."
  else
    fail "Mount failed."
    exit 1
  fi
}

cmd_umount() {
  check_mounted

  echo ""
  info "Unmounting $MOUNT_POINT ..."
  fusermount -u "$MOUNT_POINT" 2>/dev/null || fusermount3 -u "$MOUNT_POINT" 2>/dev/null || {
    fail "Unmount failed. Is it still in use?"
    exit 1
  }
  ok "Unmounted."
  rmdir "$MOUNT_POINT" 2>/dev/null && info "Cleaned up mount point." || true
}

cmd_status() {
  tui_header "Encrypted Storage Status"

  if is_initialized; then
    ok "Initialized: $CIPHER_DIR"
    local conf_ver
    conf_ver=$(grep -oP 'Version: \K\d+' "$CIPHER_DIR/gocryptfs.conf" 2>/dev/null || echo "?")
    echo "  Config version: $conf_ver"
  else
    warn "Not initialized"
  fi

  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    ok "Mounted at: $MOUNT_POINT"
    df -h "$MOUNT_POINT" | tail -1 | awk '{print "  Size: " $2 "  Used: " $3 "  Avail: " $4 "  Use%: " $5}'
  else
    warn "Not mounted"
  fi
  echo ""
}

cmd_passwd() {
  check_gocryptfs
  if ! is_initialized; then
    fail "Not initialized. Run 'encrypted-storage init' first."
    exit 1
  fi

  tui_header "Change Encrypted Storage Password"
  gocryptfs -passwd "$CIPHER_DIR"
  echo ""
  ok "Password changed."
}

interactive_menu() {
  while true; do
    echo ""
    echo -e "${CYAN}┌─ Encrypted Storage Manager ──────────────────────┐${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo ""

    if is_initialized; then
      ok "Initialized"
    else
      warn "Not initialized"
    fi
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
      ok "Mounted at $MOUNT_POINT"
    else
      warn "Not mounted"
    fi

    tui_option 1 "Init    - Initialize encrypted storage"
    tui_option 2 "Mount   - Mount encrypted storage"
    tui_option 3 "Umount  - Unmount encrypted storage"
    tui_option 4 "Status  - Show status"
    tui_option 5 "Passwd  - Change password"
    tui_option 6 "Quit"
    tui_prompt "Select [1-6]" CYAN choice

    case "$choice" in
      1) cmd_init ;;
      2) cmd_mount ;;
      3) cmd_umount ;;
      4) cmd_status ;;
      5) cmd_passwd ;;
      6) echo ""; exit 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

case "${1:-}" in
  init)    cmd_init ;;
  mount)   cmd_mount ;;
  umount|unmount) cmd_umount ;;
  status)  cmd_status ;;
  passwd)  cmd_passwd ;;
  ""|menu) interactive_menu ;;
  *)
    echo "Usage: encrypted-storage <command>"
    echo ""
    echo "  init     Initialize the encrypted storage (first-time setup)"
    echo "  mount    Mount the encrypted storage (prompts for password)"
    echo "  umount   Unmount the encrypted storage"
    echo "  status   Show initialization and mount status"
    echo "  passwd   Change the encryption password"
    echo "  menu     Interactive TTY menu (default)"
    exit 1
    ;;
esac
