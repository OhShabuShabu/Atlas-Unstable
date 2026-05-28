#!/usr/bin/env bash
# ============================================================================
# ATLAS PERSISTENCE VALIDATION — Runtime checks for impermanence setup
# ============================================================================
# This script verifies that persistence is actually working on a running system.
# Run AFTER a rebuild + reboot to confirm state survives.
# Usage: sudo bash tests/validate-persistence.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0

header() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }
pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $1"; }
warn() { WARN=$((WARN+1)); echo -e "  ${YELLOW}⚠${NC} $1"; }

USER="yusa"
USER_HOME="/home/${USER}"
PERSISTENT="/persistent"

# ============================================================================
# 1. FILESYSTEM MOUNTS VERIFICATION
# ============================================================================
header "1. FILESYSTEM MOUNTS"

# Root should be tmpfs
if mountpoint -q / && grep -q 'tmpfs' /proc/mounts /; then
  pass "/ is on tmpfs (ephemeral root)"
else
  fail "/ is NOT on tmpfs"
fi

# /home should be tmpfs
if mountpoint -q /home && grep -q 'tmpfs' /proc/mounts /home; then
  pass "/home is on tmpfs (ephemeral home)"
else
  fail "/home is NOT on tmpfs"
fi

# /persistent should be btrfs on LUKS
if mountpoint -q /persistent; then
  FSTYPE=$(findmnt -n -o FSTYPE /persistent)
  SOURCE=$(findmnt -n -o SOURCE /persistent)
  if [ "$FSTYPE" = "btrfs" ]; then
    pass "/persistent is btrfs (device: $SOURCE)"
  else
    warn "/persistent filesystem: $FSTYPE (expected btrfs)"
  fi
else
  fail "/persistent is not mounted"
fi

# /var should be btrfs (persistent subvol)
if mountpoint -q /var; then
  pass "/var is mounted"
else
  fail "/var is not mounted"
fi

# /nix should be btrfs
if mountpoint -q /nix; then
  pass "/nix is mounted"
else
  fail "/nix is not mounted"
fi

# /tmp should be tmpfs
if mountpoint -q /tmp && grep -q 'tmpfs' /proc/mounts /tmp; then
  pass "/tmp is on tmpfs"
else
  fail "/tmp is NOT on tmpfs"
fi

# ============================================================================
# 2. PRESERVATION BIND-MOUNTS
# ============================================================================
header "2. BIND-MOUNTS"

PERSISTENT_MOUNTS=$(mount | grep "/persistent${USER_HOME}" | wc -l)
if [ "$PERSISTENT_MOUNTS" -gt 0 ]; then
  pass "Preservation bind-mounts active: $PERSISTENT_MOUNTS mounts"
else
  warn "No preservation bind-mounts detected (may not be logged in)"
fi

# Check specific known bind-mounts
for dir in .ssh .gnupg .password-store .local/share/keyrings .local/state/nix .local/state/home-manager; do
  PERSISTED="${PERSISTENT}${USER_HOME}/${dir}"
  if [ -d "$PERSISTED" ] || [ -L "$PERSISTED" ]; then
    pass "Persistent store exists: $dir"
  elif [ -f "$PERSISTED" ]; then
    pass "Persistent store exists (file): $dir"
  else
    warn "Persistent store missing: $dir (will be created on first activation)"
  fi
done

# ============================================================================
# 3. SYSTEM IDENTITY PERSISTENCE
# ============================================================================
header "3. SYSTEM IDENTITY"

# SSH host keys
if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
  pass "SSH host key present: /etc/ssh/ssh_host_ed25519_key"
else
  fail "SSH host key missing — will regenerate on every boot!"
fi

# Machine ID
if [ -f /etc/machine-id ] && [ "$(cat /etc/machine-id)" != "uninitialized" ]; then
  MACHINE_ID=$(cat /etc/machine-id)
  pass "Machine ID: $MACHINE_ID"
else
  fail "Machine ID missing or uninitialized"
fi

# Check the persistent backing
if [ -f "${PERSISTENT}/etc/machine-id" ]; then
  PERSIST_ID=$(cat "${PERSISTENT}/etc/machine-id")
  if [ "$PERSIST_ID" = "$MACHINE_ID" ]; then
    pass "Machine ID matches persistent store"
  else
    warn "Machine ID differs from persistent store"
  fi
fi

# ============================================================================
# 4. SERVICE STATE PERSISTENCE (/var on persistent subvol)
# ============================================================================
header "4. SERVICE STATE ON /var"

# ClamAV virus DB
if [ -d /var/lib/clamav ]; then
  DB_FILES=$(find /var/lib/clamav -name "*.cvd" -o -name "*.cld" 2>/dev/null | wc -l)
  if [ "$DB_FILES" -gt 0 ]; then
    pass "ClamAV virus DB present: $DB_FILES database files"
  else
    warn "ClamAV virus DB directory exists but no database files (will download on next update)"
  fi
else
  warn "ClamAV directory not found at /var/lib/clamav"
fi

# AIDE database
if [ -f /var/lib/aide/aide.db.gz ]; then
  pass "AIDE database present"
else
  warn "AIDE database not found (will initialize on next boot)"
fi

# NetworkManager state
if [ -d /var/lib/NetworkManager ]; then
  pass "NetworkManager state directory present"
else
  warn "NetworkManager state directory not found"
fi

# Systemd state
if [ -d /var/lib/systemd ]; then
  pass "systemd state directory present"
else
  warn "systemd state directory not found"
fi

# USBGuard state
if [ -d /var/lib/usbguard ]; then
  pass "USBGuard state directory present"
else
  warn "USBGuard state directory not found"
fi

# Audit logs
if [ -d /var/log/audit ]; then
  pass "Audit log directory present"
else
  warn "Audit log directory not found"
fi

# Snort logs
if [ -d /var/log/snort ]; then
  pass "Snort log directory present"
else
  warn "Snort log directory not found"
fi

# Process accounting
if [ -d /var/account ]; then
  pass "Process accounting directory present"
else
  warn "Process accounting directory not found"
fi

# ============================================================================
# 5. USER CREDENTIALS PERSISTENCE
# ============================================================================
header "5. USER CREDENTIALS"

# Check at the persistent store level (bind-mounts may not be active during boot)
for cred in ".ssh" ".gnupg" ".password-store"; do
  CRED_PATH="${PERSISTENT}${USER_HOME}/${cred}"
  LIVE_PATH="${USER_HOME}/${cred}"
  if [ -d "$CRED_PATH" ]; then
    pass "Persistent store: ${cred}"
    if [ -d "$LIVE_PATH" ]; then
      pass "Active mount: ${cred}"
    fi
  else
    warn "Persistent store missing: ${cred}"
  fi
done

# ============================================================================
# 6. FLATPAK & GAMING PERSISTENCE
# ============================================================================
header "6. APPLICATION STATE"

for app_dir in ".var" ".steam" ".local/share/flatpak"; do
  APP_PATH="${PERSISTENT}${USER_HOME}/${app_dir}"
  if [ -d "$APP_PATH" ]; then
    pass "Persistent store: ${app_dir}"
  else
    warn "Persistent store missing: ${app_dir}"
  fi
done

# Mullvad VPN
if [ -d "${PERSISTENT}${USER_HOME}/.local/share/mullvad-vpn" ]; then
  pass "Persistent store: .local/share/mullvad-vpn/"
fi

# ============================================================================
# 7. PERMISSIONS VERIFICATION
# ============================================================================
header "7. PERMISSIONS"

check_perms() {
  local path="$1" expected_perms="$2" expected_owner="$3" desc="$4"
  if [ ! -e "$path" ]; then
    warn "Path missing: $path ($desc)"
    return
  fi
  local actual_perms actual_owner
  actual_perms=$(stat -c "%a" "$path" 2>/dev/null || echo "unknown")
  actual_owner=$(stat -c "%U:%G" "$path" 2>/dev/null || echo "unknown")
  if [ "$actual_perms" = "$expected_perms" ]; then
    pass "Perms OK ($expected_perms): $desc"
  else
    warn "Perms MISMATCH on $desc: expected $expected_perms, got $actual_perms"
  fi
}

# Check sensitive paths
if [ -d "${PERSISTENT}${USER_HOME}/.ssh" ]; then
  SSH_PERMS=$(stat -c "%a" "${PERSISTENT}${USER_HOME}/.ssh" 2>/dev/null || echo "unknown")
  if [ "$SSH_PERMS" = "700" ]; then
    pass "~/.ssh permissions: 700 (correct)"
  else
    warn "~/.ssh permissions: $SSH_PERMS (should be 700)"
  fi
fi

if [ -d "${PERSISTENT}${USER_HOME}/.gnupg" ]; then
  GPG_PERMS=$(stat -c "%a" "${PERSISTENT}${USER_HOME}/.gnupg" 2>/dev/null || echo "unknown")
  if [ "$GPG_PERMS" = "700" ]; then
    pass "~/.gnupg permissions: 700 (correct)"
  else
    warn "~/.gnupg permissions: $GPG_PERMS (should be 700)"
  fi
fi

# SSH host key permissions
if [ -f /etc/ssh/ssh_host_ed25519_key ]; then
  HOST_KEY_PERMS=$(stat -c "%a" /etc/ssh/ssh_host_ed25519_key 2>/dev/null || echo "unknown")
  if [ "$HOST_KEY_PERMS" = "600" ]; then
    pass "SSH host key permissions: 600 (correct)"
  else
    warn "SSH host key permissions: $HOST_KEY_PERMS (should be 600)"
  fi
fi

# Machine-id permissions
if [ -f /etc/machine-id ]; then
  MID_PERMS=$(stat -c "%a" /etc/machine-id 2>/dev/null || echo "unknown")
  if [ "$MID_PERMS" = "444" ]; then
    pass "machine-id permissions: 444 (correct)"
  else
    warn "machine-id permissions: $MID_PERMS (should be 444)"
  fi
fi

# ============================================================================
# SUMMARY
# ============================================================================
header "PERSISTENCE VALIDATION RESULTS"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo -e "  Total: $TOTAL"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n  ${RED}CRITICAL FAILURES — persistence may not be working correctly.${NC}"
  echo -e "  ${RED}Review the failures above and fix before rebuilding.${NC}"
  exit 1
elif [ "$WARN" -gt 5 ]; then
  echo -e "\n  ${YELLOW}Several warnings — most paths will populate after first login and app use.${NC}"
  exit 0
elif [ "$WARN" -gt 0 ]; then
  echo -e "\n  ${YELLOW}Minor warnings — first-boot paths that haven't been created yet.${NC}"
  exit 0
else
  echo -e "\n  ${GREEN}ALL PERSISTENCE CHECKS PASSED.${NC}"
  exit 0
fi
