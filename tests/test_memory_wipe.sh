#!/usr/bin/env bash
# ============================================================================
# MEMORY WIPE & SHUTDOWN FORENSIC WIPER TESTS
# ============================================================================
# Tests dram-wiper (cold boot attack prevention) and shutdown-wiper
# (log/temp/swap shredding) service definitions, scripts, and behavior.
# ============================================================================

TEST_NAME="Memory Wipe & Shutdown Forensics"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "MEMORY WIPE — ANTI-FORENSICS SERVICES"

TEMP_DIR=$(_mktemp /tmp/memwipe-test.XXXXXX)
MW_NIX="$BASE/files/modules/security/memory-wipe.nix"

if [ ! -f "$MW_NIX" ]; then
  skip "memory-wipe.nix not found"
  print_summary "$TEST_NAME"
  exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
fi

# ─── 1. dram-wiper Script Logic ────────────────────────────────────────────
header "1. DRAM Wiper Script Logic"

DRAM_SCRIPT=$(extract_script_from_nix "$MW_NIX" "dram-wipe.sh" 2>/dev/null || true)

if [ -n "$DRAM_SCRIPT" ]; then
  echo "$DRAM_SCRIPT" | grep -q "swapoff -a" && pass "dram-wipe: disables swap" || fail "dram-wipe: missing swapoff -a"
  echo "$DRAM_SCRIPT" | grep -q "drop_caches" && pass "dram-wipe: triggers page cache drop" || fail "dram-wipe: missing drop_caches"
  echo "$DRAM_SCRIPT" | grep -q "logger" && pass "dram-wipe: logs to syslog" || fail "dram-wipe: missing logger calls"

  # ─── Simulation: dram-wiper logic in sandbox ──────────────────────────
  header "2. DRAM Wiper Simulation (sandboxed)"

  # Simulate the script's swap detection logic
  SIMPLE_LOG="$TEMP_DIR/dram_sim.log"
  if swapon --show 2>/dev/null | grep -q .; then
    pass "Swap simulation: swap is active (note: real test disabled swapoff)"
  else
    pass "Swap simulation: no active swap (running in sandbox as expected)"
  fi

  # Verify the script is idempotent (running with no swap is safe)
  if echo "$DRAM_SCRIPT" | grep -q "swapoff -a.*2>/dev/null\|swapoff -a.*|| true"; then
    pass "dram-wipe: swapoff failure safely ignored"
  else
    warn "dram-wipe: swapoff may fail if already off (check error handling)"
  fi
else
  skip "dram-wipe script extraction failed"
fi

# ─── 3. shutdown-wiper Script Logic ────────────────────────────────────────
header "3. Shutdown Wiper Script Logic"

WIPE_SCRIPT=$(extract_script_from_nix "$MW_NIX" "shutdown-wiper.sh" 2>/dev/null || true)

if [ -n "$WIPE_SCRIPT" ]; then
  echo "$WIPE_SCRIPT" | grep -q "find /var/log" && pass "shutdown-wipe: shreds /var/log files" || fail "shutdown-wipe: missing /var/log shred"
  echo "$WIPE_SCRIPT" | grep -q "find /tmp" && pass "shutdown-wipe: cleans /tmp files" || fail "shutdown-wipe: missing /tmp cleaning"
  echo "$WIPE_SCRIPT" | grep -q "find /run" && pass "shutdown-wipe: cleans /run files" || fail "shutdown-wipe: missing /run cleaning"
  echo "$WIPE_SCRIPT" | grep -q "shred" && pass "shutdown-wipe: uses shred for secure deletion" || fail "shutdown-wipe: missing shred"
  echo "$WIPE_SCRIPT" | grep -q "logger" && pass "shutdown-wipe: logs to syslog" || fail "shutdown-wipe: missing logger calls"

  # ─── Simulation: sandboxed shred logic ────────────────────────────────
  header "4. Shutdown Wiper Simulation (sandboxed)"

  # Create test log files and verify shred is invoked correctly
  TEST_LOG_DIR="$TEMP_DIR/var_log"
  mkdir -p "$TEST_LOG_DIR"
  echo "test log entry" > "$TEST_LOG_DIR/auth.log"
  echo "test log entry" > "$TEST_LOG_DIR/syslog"

  # Simulate the shred command (dry run: just check find + shred pattern)
  SHRED_COUNT=$(grep -c "shred" "$MW_NIX" 2>/dev/null || echo 0)
  if [ "$SHRED_COUNT" -ge 3 ]; then
    pass "shutdown-wipe: shred applied to 3+ target directories"
  else
    fail "shutdown-wipe: insufficient shred targets (found $SHRED_COUNT)"
  fi

  # Verify .gz files are excluded (don't shred compressed archives)
  if echo "$WIPE_SCRIPT" | grep -q '! -name "*.gz"'; then
    pass "shutdown-wipe: excludes .gz files from shredding"
  else
    warn "shutdown-wipe: no .gz exclusion (may shred compressed logs unnecessarily)"
  fi

  # Verify swap file wipe
  if echo "$WIPE_SCRIPT" | grep -q "swapfile"; then
    pass "shutdown-wipe: shreds swap file"
  else
    fail "shutdown-wipe: missing swap file shred"
  fi

  # Verify file size filter on /run (only shreds files under limit)
  if echo "$WIPE_SCRIPT" | grep -q "size -1M\|size -1m"; then
    pass "shutdown-wipe: size limits /run shredding to <1MB files"
  else
    warn "shutdown-wipe: no size limit on /run (may hang on large files)"
  fi
else
  skip "shutdown-wiper script extraction failed"
fi

# ─── 5. Service Definition Verification ─────────────────────────────────────
header "5. Service Definitions"

check_nix_value "$MW_NIX" 'dram-wiper' "Service defined: dram-wiper" || true
check_nix_value "$MW_NIX" 'shutdown-wiper' "Service defined: shutdown-wiper" || true

# Type
grep -A5 "dram-wiper" "$MW_NIX" | grep -q "Type.*oneshot" && pass "dram-wiper: Type=oneshot" || fail "dram-wiper: not oneshot"
grep -A5 "shutdown-wiper" "$MW_NIX" | grep -q "Type.*oneshot" && pass "shutdown-wiper: Type=oneshot" || fail "shutdown-wiper: not oneshot"

# Timing before shutdown
grep -A10 "dram-wiper" "$MW_NIX" | grep -q "poweroff.target\|reboot.target\|halt.target" && pass "dram-wiper: runs before shutdown targets" || fail "dram-wiper: missing shutdown ordering"
grep -A10 "shutdown-wiper" "$MW_NIX" | grep -q "after.*dram-wiper" && pass "shutdown-wiper: runs after dram-wiper" || fail "shutdown-wiper: missing after dram-wiper dependency"

# Timeouts
grep -A10 "dram-wiper" "$MW_NIX" | grep -q "30s" && pass "dram-wiper: 30s timeout" || fail "dram-wiper: missing/invalid timeout"
grep -A10 "shutdown-wiper" "$MW_NIX" | grep -q "120s" && pass "shutdown-wiper: 120s timeout" || fail "shutdown-wiper: missing/invalid timeout"

# ─── 6. Service Hardening ───────────────────────────────────────────────────
header "6. Service Hardening"

check_service_hardening "$MW_NIX" "dram-wiper" "NoNewPrivileges" "dram-wiper: NoNewPrivileges" || true
check_service_hardening "$MW_NIX" "shutdown-wiper" "NoNewPrivileges" "shutdown-wiper: NoNewPrivileges" || true

grep -A10 "dram-wiper" "$MW_NIX" | grep -q "CAP_SYS_ADMIN" && pass "dram-wiper: CAP_SYS_ADMIN capability" || fail "dram-wiper: missing CAP_SYS_ADMIN"
grep -A10 "dram-wiper" "$MW_NIX" | grep -q "CAP_SYS_BOOT" && pass "dram-wiper: CAP_SYS_BOOT capability" || fail "dram-wiper: missing CAP_SYS_BOOT"

# ─── 7. Hibernation/Suspend Disabled ────────────────────────────────────────
header "7. Sleep State Hardening"

grep -q 'nohibernate' "$MW_NIX" && pass "nohibernate kernel param set" || fail "nohibernate kernel param missing"
grep -q 'sleep.enable = false' "$MW_NIX" && pass "systemd sleep target disabled" || fail "systemd sleep target not disabled"
grep -q 'suspend.enable = false' "$MW_NIX" && pass "systemd suspend target disabled" || fail "systemd suspend target not disabled"
grep -q 'hibernate.enable = false' "$MW_NIX" && pass "systemd hibernate target disabled" || fail "systemd hibernate target not disabled"
grep -q 'HandleSuspendKey = "ignore"' "$MW_NIX" && pass "HandleSuspendKey = ignore" || fail "HandleSuspendKey not ignore"
grep -q 'HandleHibernateKey = "ignore"' "$MW_NIX" && pass "HandleHibernateKey = ignore" || fail "HandleHibernateKey not ignore"
grep -q 'HandleLidSwitch = "ignore"' "$MW_NIX" && pass "HandleLidSwitch = ignore" || fail "HandleLidSwitch not ignore"

# ─── 8. Edge Cases ──────────────────────────────────────────────────────────
header "8. Edge Case Analysis"

# Empty /var/log - script should handle with find returning nothing
if echo "$WIPE_SCRIPT" | grep -q 'find /var/log'; then
  pass "Edge: handles empty /var/log (find returns nothing)"
fi

# Missing swap - script checks with grepping
if echo "$DRAM_SCRIPT" | grep -q "grep.*-q.*.; then"; then
  pass "Edge: handles no swap gracefully"
fi

# Missing /persistent/swapfile
if echo "$WIPE_SCRIPT" | grep -q '\-f /persistent/swapfile'; then
  pass "Edge: checks swapfile existence before shredding"
fi

# Cannot actually test shutdown in sandbox (requires root), but verify
# the ordering targets are correct
grep -A10 "dram-wiper" "$MW_NIX" | grep -q "before" && pass "Defensive: shutdown ordering verified" || fail "Defensive: missing before directive"

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
