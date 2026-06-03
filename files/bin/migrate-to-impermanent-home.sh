#!/usr/bin/env bash
# ==============================================================================
# migrate-to-impermanent-home.sh
# ==============================================================================
# One-time migration script: copies existing home data to /persistent/home/yusa/
# BEFORE rebooting into the impermanent /home (tmpfs) configuration.
#
# Usage:
#   # Dry-run (preview what will be copied)
#   bash migrate-to-impermanent-home.sh --dry-run
#
#   # Actual migration
#   bash migrate-to-impermanent-home.sh
#
#   # Force re-copy even if target exists
#   bash migrate-to-impermanent-home.sh --force
#
# Prerequisites:
#   1. Rebuild with the new config first (don't reboot yet):
#      sudo nixos-rebuild switch --flake .#yorha
#   2. Run this script
#   3. Reboot to test impermanent /home
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/files/lib/tui.sh"

SRC="$HOME"
DST="/persistent/home/yusa"
DRY_RUN=false
FORCE=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    --help)
      echo "Usage: $0 [--dry-run] [--force]"
      echo ""
      echo "  --dry-run    Preview what would be copied without copying"
      echo "  --force      Re-copy even if target already exists"
      exit 0
      ;;
  esac
done

# List of paths (directories and files) to migrate — must match preservation.nix
PATHS=(
  # Folder Structure dirs
  # NOTE: "Encrypted Storage" is NOT here — it uses gocryptfs.
  #       See files/bin/encrypted-storage.sh.
  "YoRHa"
  "Desktop"
  "Documents"
  "Downloads"
  "Games"
  "Music"
  "Pictures"
  "Public"
  "Templates"
  "Videos"

  # Critical dotfiles
  ".ssh"

  # Nix/HM state
  ".local/state/nix"
  ".local/state/home-manager"

  # App state
  ".local/share/keyrings"
  ".local/share/flatpak"
  ".steam"
  ".var"

  # Files
  ".bash_history"
)

tui_header "Impermanent Home Migration"
tui_kv "Source"      "$SRC"
tui_kv "Destination" "$DST"
tui_kv "Mode"        "$([ "$DRY_RUN" = true ] && echo "DRY-RUN" || echo "LIVE")"

if [ ! -d "$SRC" ]; then
  fail "Source directory $SRC does not exist!"
  exit 1
fi

# Create destination base if it doesn't exist
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$DST"
fi

MIGRATED=0
SKIPPED=0
ERRORS=0

migrate_item() {
  local src_path="$SRC/$1"
  local dst_path="$DST/$1"
  local dst_parent
  dst_parent=$(dirname "$dst_path")

  if [ ! -e "$src_path" ]; then
    warn "SKIP: $1 (does not exist in source)"
    ((SKIPPED++)) || true
    return 0
  fi

  if [ -e "$dst_path" ] && [ "$FORCE" = false ]; then
    ok "EXISTS: $1 (already in /persistent, use --force to re-copy)"
    ((SKIPPED++)) || true
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    if [ -d "$src_path" ]; then
      local size
      size=$(du -sh "$src_path" 2>/dev/null | cut -f1)
      info "DRY-RUN: would copy directory $1 ($size)"
    elif [ -f "$src_path" ]; then
      local size
      size=$(du -h "$src_path" 2>/dev/null | cut -f1)
      info "DRY-RUN: would copy file $1 ($size)"
    fi
    ((MIGRATED++)) || true
    return 0
  fi

  echo -n "  $(tui_arrow) Copying $1 ... "

  # Create parent directory
  mkdir -p "$dst_parent"

  # Copy with permissions, ownership, and recursion
  if [ -d "$src_path" ]; then
    # Remove existing if force re-copy
    if [ -e "$dst_path" ] && [ "$FORCE" = true ]; then
      rm -rf "$dst_path"
    fi
    cp -a --parents "$1" "$DST/" 2>/dev/null || cp -a "$src_path" "$dst_path" 2>/dev/null || {
      # Fallback: use rsync or tar
      if command -v rsync &>/dev/null; then
        rsync -aAX "$src_path/" "$dst_path/"
      else
        mkdir -p "$dst_path"
        (cd "$SRC" && tar cf - "$1") | (cd "$DST/.." && tar xf -) 2>/dev/null || {
          fail "FAILED (could not copy $1)"
          ((ERRORS++)) || true
          return 1
        }
      fi
    }
    ok "done"
  elif [ -f "$src_path" ]; then
    cp -a "$src_path" "$dst_path"
    ok "done"
  fi

  # Verify destination exists
  if [ ! -e "$dst_path" ]; then
    warn "$dst_path was not created!"
    ((ERRORS++)) || true
    return 1
  fi

  # Preserve ownership (run via sudo if needed)
  if [ "$(stat -c '%U:%G' "$src_path")" != "$(stat -c '%U:%G' "$dst_path" 2>/dev/null)" ]; then
    chown -R "$(stat -c '%U:%G' "$src_path")" "$dst_path" 2>/dev/null || {
      warn "Could not set ownership (may need sudo)"
    }
  fi

  ((MIGRATED++)) || true
}

for item in "${PATHS[@]}"; do
  migrate_item "$item"
done

tui_section "Summary"
tui_summary "Migrated" "$MIGRATED" GREEN "Skipped" "$SKIPPED" YELLOW "Errors" "$ERRORS" RED

if [ "$DRY_RUN" = true ]; then
  tui_hint "This was a dry-run. Run without --dry-run to perform the migration."
fi

tui_section "Important"
warn "After migration, REBOOT to activate the impermanent /home."
info "If something is missing, check: sudo mount /dev/mapper/crypt /mnt"
info "and look for leftover directories in the old btrfs home subvol."
