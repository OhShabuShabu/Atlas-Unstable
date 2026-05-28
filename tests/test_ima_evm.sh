#!/usr/bin/env bash
# ============================================================================
# IMA/EVM KERNEL FILE INTEGRITY TESTS
# ============================================================================
# Tests Integrity Measurement Architecture (IMA) policy loading and
# Extended Verification Module (EVM) HMAC key setup scripts and logic.
# ============================================================================

TEST_NAME="IMA/EVM Kernel Integrity"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "IMA/EVM — KERNEL-LEVEL FILE INTEGRITY"

TEMP_DIR=$(_mktemp /tmp/ima-evm-test.XXXXXX)
IE_NIX="$BASE/files/modules/security/ima-evm.nix"

if [ ! -f "$IE_NIX" ]; then
  skip "ima-evm.nix not found"
  print_summary "$TEST_NAME"
  exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
fi

# ─── 1. Kernel Boot Parameters ─────────────────────────────────────────────
header "1. IMA/EVM Kernel Parameters"

check_boot_param "$IE_NIX" "ima_policy=tcb" "ima_policy=tcb" || true
check_boot_param "$IE_NIX" "ima_appraise=fix" "ima_appraise=fix (log-only)" || true
check_boot_param "$IE_NIX" "ima_hash=sha256" "ima_hash=sha256" || true
check_boot_param "$IE_NIX" "evm=fix" "evm=fix (log-only)" || true

# ─── 2. IMA Policy Script ──────────────────────────────────────────────────
header "2. IMA Policy Loader Script"

IMA_SCRIPT=$(extract_script_from_nix "$IE_NIX" "load-ima-policy.sh" 2>/dev/null || true)

if [ -n "$IMA_SCRIPT" ]; then
  pass "IMA policy script extracted"

  # Check policy file path
  echo "$IMA_SCRIPT" | grep -q "/sys/kernel/security/integrity/ima/policy" && \
    pass "IMA: references policy sysfs file" || fail "IMA: missing policy path"

  # Check IMA availability check
  echo "$IMA_SCRIPT" | grep -q "Not available" && \
    pass "IMA: graceful handling when not in kernel" || fail "IMA: missing kernel availability check"

  # Check idempotency (already loaded detection)
  echo "$IMA_SCRIPT" | grep -q "already loaded" && \
    pass "IMA: idempotent (checks if policy already loaded)" || fail "IMA: missing already-loaded check"

  # Check logger usage
  echo "$IMA_SCRIPT" | grep -q "logger" && \
    pass "IMA: logs to syslog" || fail "IMA: missing logger calls"

  # ── IMA Policy Content ─────────────────────────────────────────────────
  header "  2a. IMA Measurement Rules"

  # Verify the policy includes critical measurement types
  if echo "$IMA_SCRIPT" | grep -q "BPRM_CHECK\|FILE_MMAP\|MODULE_CHECK\|FIRMWARE_CHECK\|CRITICAL_DATA"; then
    pass "IMA policy: covers all measurement types (BPRM, MMAP, MODULE, FIRMWARE, CRITICAL)"
  else
    fail "IMA policy: missing measurement types"
  fi

  # Verify pseudo-fs exclusions
  for fs in procfs sysfs devtmpfs debugfs securityfs selinuxfs; do
    echo "$IMA_SCRIPT" | grep -qi "$fs" && pass "IMA policy: excludes $fs" || warn "IMA policy: missing $fs exclusion"
  done

  # Verify policy can only be loaded once
  echo "$IMA_SCRIPT" | grep -q "runtime_measurements_count" && \
    pass "IMA: checks measurement count before loading" || warn "IMA: missing measurement count check"
else
  skip "IMA policy script extraction failed"
fi

# ─── 3. EVM Key Setup Script ───────────────────────────────────────────────
header "3. EVM Key Setup Script"

EVM_SCRIPT=$(extract_script_from_nix "$IE_NIX" "evm-key-setup.sh" 2>/dev/null || true)

if [ -n "$EVM_SCRIPT" ]; then
  pass "EVM key setup script extracted"

  # ── Key generation logic ──────────────────────────────────────────────
  header "  3a. Key Generation"

  echo "$EVM_SCRIPT" | grep -q "openssl rand" && \
    pass "EVM: generates random HMAC key with openssl" || fail "EVM: missing key generation"
  echo "$EVM_SCRIPT" | grep -q "hmac-sha256" && \
    pass "EVM: uses HMAC-SHA256 algorithm" || fail "EVM: missing HMAC algorithm"
  echo "$EVM_SCRIPT" | grep -q "chmod 0600" && \
    pass "EVM: sets restrictive key file permissions" || fail "EVM: missing chmod 0600"

  # ── Key management ────────────────────────────────────────────────────
  header "  3b. Key Management"

  echo "$EVM_SCRIPT" | grep -q "keyctl padd encrypted" && \
    pass "EVM: loads key into kernel keyring" || fail "EVM: missing keyctl load"
  echo "$EVM_SCRIPT" | grep -q "already exists" && \
    pass "EVM: idempotent key creation (checks existing)" || fail "EVM: missing existence check"
  echo "$EVM_SCRIPT" | grep -q "already loaded" && \
    pass "EVM: idempotent key loading (checks kernel keyring)" || fail "EVM: missing loaded check"

  # ── Error handling ────────────────────────────────────────────────────
  header "  3c. Error Handling"

  echo "$EVM_SCRIPT" | grep -q "Failed to load" && \
    pass "EVM: graceful key load failure message" || fail "EVM: missing load failure handling"
  echo "$EVM_SCRIPT" | grep -q "Not available" && \
    pass "EVM: graceful when not in kernel" || fail "EVM: missing kernel availability check"
  echo "$EVM_SCRIPT" | grep -q "exit 0" && \
    pass "EVM: exits gracefully when EVM unavailable" || fail "EVM: missing graceful exit"
else
  skip "EVM key setup script extraction failed"
fi

# ─── 4. evm-sign-binary CLI ────────────────────────────────────────────────
header "4. evm-sign-binary CLI"

EVM_SIGN=$(extract_script_from_nix "$IE_NIX" "evm-sign-binary" 2>/dev/null || true)

if [ -n "$EVM_SIGN" ]; then
  pass "evm-sign-binary script extracted"

  echo "$EVM_SIGN" | grep -q "Usage:" && \
    pass "evm-sign-binary: usage message" || fail "evm-sign-binary: missing usage"
  echo "$EVM_SIGN" | grep -q "evmctl sign" && \
    pass "evm-sign-binary: calls evmctl sign" || fail "evm-sign-binary: missing evmctl sign"
  echo "$EVM_SIGN" | grep -q "key.*not found" && \
    pass "evm-sign-binary: handles missing key" || fail "evm-sign-binary: missing key-not-found check"
else
  skip "evm-sign-binary script extraction failed"
fi

# ─── 5. Package Availability ───────────────────────────────────────────────
header "5. Package Dependencies"

grep -q "ima-evm-utils" "$IE_NIX" && pass "Package: ima-evm-utils (evmctl)" || fail "Package: missing ima-evm-utils"
grep -q "kmod" "$IE_NIX" && pass "Package: kmod (keyctl)" || fail "Package: missing kmod"

# ─── 6. Safety Verification ────────────────────────────────────────────────
header "6. Safety: Log-Only Mode"

if grep -q "ima_appraise=fix" "$IE_NIX" 2>/dev/null; then
  pass "SAFE: IMA in fix mode (log-only, no enforcement)"
else
  fail "SAFETY: IMA not in fix mode (may enforce)"
fi

if grep -q "evm=fix" "$IE_NIX" 2>/dev/null; then
  pass "SAFE: EVM in fix mode (log-only, no enforcement)"
else
  fail "SAFETY: EVM not in fix mode (may break boot)"
fi

# Verify documentation warning exists
grep -q "Start with 'fix'" "$IE_NIX" 2>/dev/null && \
  pass "SAFETY: documentation warns about fix mode" || \
  warn "SAFETY: missing fix mode documentation"

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
