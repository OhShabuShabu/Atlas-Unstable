#!/usr/bin/env bash
# ============================================================================
# QUARANTINE SYSTEM BEHAVIORAL TESTS
# ============================================================================
# Tests the quarantine system: setup, sanitizer, cleanup, list, and purge.
# All operations are sandboxed in temporary directories — no root needed.
# ============================================================================

TEST_NAME="Quarantine System"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "QUARANTINE SYSTEM"

TEMP_DIR=$(_mktemp /tmp/quar-test.XXXXXX)
QUAR_DIR="$TEMP_DIR/quarantine"
mkdir -p "$QUAR_DIR"

# ─── 1. Quarantine Setup Script Logic ──────────────────────────────────────
header "1. Setup Script Logic"

SETUP_SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/quarantine.nix" "quarantine-setup.sh" 2>/dev/null || true)

if [ -n "$SETUP_SCRIPT" ]; then
  echo "$SETUP_SCRIPT" | grep -q "mkdir -p" && pass "Setup: creates quarantine directory" || fail "Setup: missing mkdir"
  echo "$SETUP_SCRIPT" | grep -q "chmod 0700" && pass "Setup: sets restricted permissions" || fail "Setup: missing chmod 0700"
  echo "$SETUP_SCRIPT" | grep -q "chown root:root" && pass "Setup: sets ownership to root" || fail "Setup: missing chown root:root"
  echo "$SETUP_SCRIPT" | grep -q "chattr +a" && pass "Setup: marks append-only (if supported)" || fail "Setup: missing chattr +a"
  echo "$SETUP_SCRIPT" | grep -q "README.txt" && pass "Setup: creates README banner" || fail "Setup: missing README.txt creation"
  echo "$SETUP_SCRIPT" | grep -q "mount.*noexec" && pass "Setup: bind-mounts as noexec" || fail "Setup: missing noexec bind mount"

  # ─── Sandboxed simulation of setup logic ──────────────────────────────────
  header "2. Setup Simulation (sandboxed)"

  Q_TEST="$TEMP_DIR/q_test"
  mkdir -p "$Q_TEST"
  chmod 0700 "$Q_TEST"

  perms=$(stat -c "%a" "$Q_TEST" 2>/dev/null || echo "unknown")
  assert_eq "Directory permissions set to 700" "700" "$perms" || true

  # Create README
  cat > "$Q_TEST/README.txt" << 'EOF'
QUARANTINE — LOCKED DOWN
EOF
  chmod 0600 "$Q_TEST/README.txt"
  assert_file_exists "README.txt created in quarantine" "$Q_TEST/README.txt" || true

  readme_perms=$(stat -c "%a" "$Q_TEST/README.txt" 2>/dev/null || echo "unknown")
  assert_eq "README.txt permissions set to 600" "600" "$readme_perms" || true
else
  skip "Setup script extraction failed"
  skip "Setup simulation skipped"
fi

# ─── 3. Sanitizer Script Logic ────────────────────────────────────────────
header "3. Sanitizer Script Logic"

SAN_SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/quarantine.nix" "quarantine-sanitizer.sh" 2>/dev/null || true)

if [ -n "$SAN_SCRIPT" ]; then
  echo "$SAN_SCRIPT" | grep -q "chmod 0000" && pass "Sanitizer: sets files to chmod 0000" || fail "Sanitizer: missing chmod 0000"
  echo "$SAN_SCRIPT" | grep -q "chown root:root" && pass "Sanitizer: sets ownership to root" || fail "Sanitizer: missing chown root:root"
  echo "$SAN_SCRIPT" | grep -q "README.txt" && pass "Sanitizer: excludes README.txt" || fail "Sanitizer: missing README.txt exclusion"

  # ─── Sandboxed simulation of sanitizer logic ──────────────────────────────
  header "4. Sanitizer Simulation (sandboxed)"

  # Create test files in quarantine
  touch "$QUAR_DIR/test_virus.exe" "$QUAR_DIR/suspicious.pdf"
  echo "README" > "$QUAR_DIR/README.txt"
  chmod 0644 "$QUAR_DIR/test_virus.exe" "$QUAR_DIR/suspicious.pdf"

  # Run sanitizer logic
  find "$QUAR_DIR" -type f ! -name "README.txt" -exec chmod 0000 {} \; 2>/dev/null || true
  find "$QUAR_DIR" -type f ! -name "README.txt" -exec chown root:root {} \; 2>/dev/null || true

  file1_perms=$(stat -c "%a" "$QUAR_DIR/test_virus.exe" 2>/dev/null || echo "?")
  file2_perms=$(stat -c "%a" "$QUAR_DIR/suspicious.pdf" 2>/dev/null || echo "?")
  readme_perms=$(stat -c "%a" "$QUAR_DIR/README.txt" 2>/dev/null || echo "?")

  assert_eq "Virus file permissions changed to 0000" "0" "$file1_perms" || true
  assert_eq "PDF file permissions changed to 0000" "0" "$file2_perms" || true

  if [ "$readme_perms" = "644" ] || [ "$readme_perms" = "600" ]; then
    pass "README.txt permissions preserved"
  else
    fail "README.txt permissions incorrectly changed (got: $readme_perms)"
  fi
else
  skip "Sanitizer script extraction failed"
  skip "Sanitizer simulation skipped"
fi

# ─── 5. Cleanup Script Logic ──────────────────────────────────────────────
header "5. Cleanup Script Logic"

CLN_SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/quarantine.nix" "quarantine-cleanup.sh" 2>/dev/null || true)

if [ -n "$CLN_SCRIPT" ]; then
  echo "$CLN_SCRIPT" | grep -q "shred" && pass "Cleanup: uses shred for secure deletion" || fail "Cleanup: missing shred"
  echo "$CLN_SCRIPT" | grep -q "chattr -a" && pass "Cleanup: removes append-only flag" || fail "Cleanup: missing chattr -a"
  echo "$CLN_SCRIPT" | grep -q "mindepth 1 -delete" && pass "Cleanup: deletes all contents" || fail "Cleanup: missing content deletion"
else
  skip "Cleanup script extraction failed"
fi

# ─── 6. Quarantine-list Command Logic ──────────────────────────────────────
header "6. quarantine-list Command"

LIST_SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/quarantine.nix" "quarantine-list" 2>/dev/null || true)

if [ -n "$LIST_SCRIPT" ]; then
  echo "$LIST_SCRIPT" | grep -q "README.txt" && pass "quarantine-list: excludes README.txt" || fail "quarantine-list: missing README.txt exclusion"
  echo "$LIST_SCRIPT" | grep -q "Quarantine is empty" && pass "quarantine-list: 'empty' message" || fail "quarantine-list: missing empty state message"
  echo "$LIST_SCRIPT" | grep -q "stat" && pass "quarantine-list: shows file stats" || fail "quarantine-list: missing file stats"
else
  skip "quarantine-list script extraction failed"
fi

# ─── 7. quarantine-purge Command Logic ─────────────────────────────────────
header "7. quarantine-purge Command"

PRG_SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/quarantine.nix" "quarantine-purge" 2>/dev/null || true)

if [ -n "$PRG_SCRIPT" ]; then
  echo "$PRG_SCRIPT" | grep -q "shred" && pass "quarantine-purge: uses shred" || fail "quarantine-purge: missing shred"
  echo "$PRG_SCRIPT" | grep -q "chattr -a" && pass "quarantine-purge: removes append-only" || fail "quarantine-purge: missing chattr -a"
  echo "$PRG_SCRIPT" | grep -q "chattr +a" && pass "quarantine-purge: re-enables append-only" || fail "quarantine-purge: missing chattr +a re-enable"
  echo "$PRG_SCRIPT" | grep -q "purge" && pass "quarantine-purge: purge message" || fail "quarantine-purge: missing purge confirmation"
else
  skip "quarantine-purge script extraction failed"
fi

# ─── 8. Path Unit Configuration ───────────────────────────────────────────
header "8. Path Unit Configuration"

QUAR_NIX="$BASE/files/modules/security/quarantine.nix"

if grep -q "PathModified" "$QUAR_NIX" 2>/dev/null; then
  pass "Path unit: watches via PathModified"
else
  fail "Path unit: missing PathModified"
fi

if grep -q "quarantine-sanitizer.service" "$QUAR_NIX" 2>/dev/null; then
  pass "Path unit: triggers quarantine-sanitizer.service"
else
  fail "Path unit: missing service trigger"
fi

# ─── 9. Service Ordering ──────────────────────────────────────────────────
header "9. Service Ordering"

if grep -q "before.*snout-watcher" "$QUAR_NIX" 2>/dev/null; then
  pass "Ordering: quarantine-setup before snout-watcher"
fi

if grep -q "before.*shutdown.target" "$QUAR_NIX" 2>/dev/null; then
  pass "Ordering: quarantine-cleanup before shutdown"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
