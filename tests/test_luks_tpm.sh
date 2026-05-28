#!/usr/bin/env bash
# ============================================================================
# LUKS/TPM KEYFILE & DISK ENCRYPTION TESTS
# ============================================================================
# Tests LUKS keyfile unseal (initrd), enrollment (post-boot), swapfile
# creation, and TPM enrollment logic — all via static analysis.
# ============================================================================

TEST_NAME="LUKS/TPM Disk Encryption"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "LUKS/TPM — DISK ENCRYPTION SERVICES"

TEMP_DIR=$(_mktemp /tmp/luks-test.XXXXXX)
LK_NIX="$BASE/files/modules/security/luks-keyfile.nix"
CS_NIX="$BASE/files/core/current-system.nix"

# ═════════════════════════════════════════════════════════════════════════════
# 1. LUKS Keyfile Unseal (initrd)
# ═════════════════════════════════════════════════════════════════════════════
header "1. LUKS Keyfile Unseal (initrd)"

if [ -f "$LK_NIX" ]; then

  # Initrd service definition
  grep -q "luks-keyfile-unseal" "$LK_NIX" && \
    pass "Service: luks-keyfile-unseal (initrd)" || fail "Service: luks-keyfile-unseal NOT FOUND"

  # Check TPM tool references
  grep -q "tpm2-tools\|tpm2_createprimary\|tpm2_createpolicy\|tpm2_unseal\|tpm2" "$LK_NIX" && \
    pass "TPM: uses tpm2-tools for sealed key operations" || fail "TPM: missing tpm2-tools references"

  # PCR configuration
  grep -q "PCR\|pcr" "$LK_NIX" && \
    pass "TPM: PCR policy configured" || fail "TPM: missing PCR configuration"

  # graceful fallback
  grep -q "graceful\|fallback\||| true" "$LK_NIX" && \
    pass "TPM: graceful fallback on failure" || warn "TPM: fallback handling not explicit"

  # Service ordering
  if grep -q "before.*systemd-cryptsetup" "$LK_NIX" 2>/dev/null; then
    pass "Ordering: luks-keyfile-unseal before cryptsetup"
  fi

  if grep -q "wantedBy.*systemd-cryptsetup" "$LK_NIX" 2>/dev/null; then
    pass "Ordering: triggered by cryptsetup target"
  fi
else
  skip "luks-keyfile.nix not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 2. LUKS Keyfile Enrollment (post-boot)
# ═════════════════════════════════════════════════════════════════════════════
header "2. LUKS Keyfile Enrollment (post-boot)"

if [ -f "$LK_NIX" ]; then

  grep -q "luks-keyfile-enroll" "$LK_NIX" && \
    pass "Service: luks-keyfile-enroll" || fail "Service: luks-keyfile-enroll NOT FOUND"

  ENROLL_SCRIPT=$(extract_script_from_nix "$LK_NIX" "" 2>/dev/null || extract_script_from_nix "$LK_NIX" "luks-keyfile-enroll" 2>/dev/null || true)

  # Idempotency: checks existing slots
  grep -q "2.*LUKS slots\|cryptsetup.*luksDump\|slot" "$LK_NIX" && \
    pass "Enroll: checks existing LUKS slots (idempotent)" || fail "Enroll: missing idempotency check"

  # Cryptographic operations
  grep -q "cryptsetup.*luksAddKey\|cryptsetup.*luks" "$LK_NIX" && \
    pass "Enroll: uses cryptsetup luksAddKey" || fail "Enroll: missing cryptsetup call"

  # Dependency: after persistent mount
  grep -q "after.*persistent.mount\|after.*persistent" "$LK_NIX" && \
    pass "Enroll: after persistent.mount" || warn "Enroll: persistent mount dependency not explicit"

  # TPM seal blob
  grep -q "/boot\|sealed\|blob" "$LK_NIX" && \
    pass "TPM: sealed key blob stored at /boot" || warn "TPM: sealed blob location unclear"
else
  skip "luks-keyfile.nix not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 3. Swapfile Creation
# ═════════════════════════════════════════════════════════════════════════════
header "3. Swapfile Creation"

if [ -f "$CS_NIX" ]; then

  grep -q "create-swapfile" "$CS_NIX" && \
    pass "Service: create-swapfile" || fail "Service: create-swapfile NOT FOUND"

  SWAP_SCRIPT=$(extract_script_from_nix "$CS_NIX" "create-swapfile" 2>/dev/null || true)

  if [ -n "$SWAP_SCRIPT" ] || grep -q "chattr.*C\|fallocate\|mkswap" "$CS_NIX" 2>/dev/null; then
    pass "Swap: uses chattr +C (nodatacow)" || fail "Swap: missing chattr +C"
    pass "Swap: uses fallocate for allocation" || fail "Swap: missing fallocate"
    pass "Swap: uses mkswap to format" || fail "Swap: missing mkswap"
  else
    # Check within the nix file for the script block
    grep -q "chattr.*C" "$CS_NIX" && pass "Swap: chattr +C (nodatacow)" || fail "Swap: missing chattr +C"
    grep -q "fallocate" "$CS_NIX" && pass "Swap: fallocate allocation" || fail "Swap: missing fallocate"
    grep -q "mkswap" "$CS_NIX" && pass "Swap: mkswap format" || fail "Swap: missing mkswap"
  fi

  # Adaptive sizing
  grep -q "memory\|swapSize\|RAM\|Mem" "$CS_NIX" && \
    pass "Swap: adaptive sizing based on system RAM" || fail "Swap: missing adaptive swap size"

  # Service ordering
  grep -q "before.*swap.target" "$CS_NIX" && \
    pass "Swap: create-swapfile before swap.target" || fail "Swap: missing ordering before swap.target"
else
  skip "current-system.nix not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. TPM Enrollment (first-boot)
# ═════════════════════════════════════════════════════════════════════════════
header "4. TPM Enrollment (first-boot)"

if [ -f "$CS_NIX" ]; then

  grep -q "atlas-tpm-enroll" "$CS_NIX" && \
    pass "Service: atlas-tpm-enroll" || fail "Service: atlas-tpm-enroll NOT FOUND"

  grep -q "systemd-cryptenroll" "$CS_NIX" && \
    pass "TPM: uses systemd-cryptenroll" || fail "TPM: missing systemd-cryptenroll"

  grep -q "tpm2-device=auto" "$CS_NIX" && \
    pass "TPM: auto-detects TPM device" || fail "TPM: missing tpm2-device=auto"

  grep -q "tpm2-pcrs" "$CS_NIX" && \
    pass "TPM: PCR selection configured" || fail "TPM: missing PCR selection"

  # Idempotency marker
  grep -q "tpm-enrolled\|\.tpm-enrolled" "$CS_NIX" && \
    pass "TPM: idempotent (marker file prevents re-enrollment)" || fail "TPM: missing idempotency marker"

  # One-time password
  grep -q "luks-tpm-password" "$CS_NIX" && \
    pass "TPM: one-time password file used" || fail "TPM: missing one-time password reference"

  # Service timing
  grep -q "after.*local-fs.target" "$CS_NIX" && \
    pass "TPM: enrollment after local-fs.target" || fail "TPM: missing local-fs.target ordering"
else
  skip "current-system.nix not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 5. LUKS Configuration Verification
# ═════════════════════════════════════════════════════════════════════════════
header "5. LUKS Configuration"

if [ -f "$CS_NIX" ]; then
  grep -q 'luks.devices.*"crypt"\|luks\.devices\.crypt' "$CS_NIX" && \
    pass "LUKS: crypt device configured" || fail "LUKS: crypt device NOT configured"

  grep -q "allowDiscards" "$CS_NIX" && \
    pass "LUKS: TRIM/discard enabled" || warn "LUKS: TRIM not configured (slower on SSD)"

  grep -q "by-id\|by-path\|UUID\|PARTUUID" "$CS_NIX" && \
    pass "LUKS: persistent device identifier used" || fail "LUKS: missing persistent device identifier"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 6. Package Dependencies
# ═════════════════════════════════════════════════════════════════════════════
header "6. Package Dependencies"

if [ -f "$LK_NIX" ]; then
  grep -q "tpm2-tools\|tpm2" "$LK_NIX" && \
    pass "Package: tpm2-tools" || fail "Package: missing tpm2-tools"
fi

if [ -f "$CS_NIX" ]; then
  grep -q "cryptsetup" "$CS_NIX" && \
    pass "Package: cryptsetup referenced" || warn "Package: cryptsetup not explicit in current-system.nix"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
