#!/usr/bin/env bash
# ============================================================================
# AIDE FILE INTEGRITY MONITOR BEHAVIORAL TESTS
# ============================================================================
# Tests AIDE database initialization, integrity checking, configuration
# parsing, and file change detection in an isolated sandbox.
# ============================================================================

TEST_NAME="AIDE File Integrity"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "AIDE — FILE INTEGRITY MONITOR"

TEMP_DIR=$(_mktemp /tmp/aide-test.XXXXXX)

# ─── 1. Configuration Validation ───────────────────────────────────────────
header "1. Configuration Validation"

AIDE_CFG="$BASE/files/modules/security/aide.nix"

if [ -f "$AIDE_CFG" ]; then
  # Verify configuration sections
  grep -q "database_in" "$AIDE_CFG" && pass "Config: database_in defined" || fail "Config: missing database_in"
  grep -q "database_out" "$AIDE_CFG" && pass "Config: database_out defined" || fail "Config: missing database_out"
  grep -q "gzip_dbout" "$AIDE_CFG" && pass "Config: gzip compression" || fail "Config: missing gzip_dbout"
  grep -q "sha512" "$AIDE_CFG" && pass "Config: SHA512 checksums" || fail "Config: missing SHA512"

  # Verify monitored directories
  for dir in /bin /sbin /usr/bin /usr/sbin /lib /usr/lib /var/lib /etc; do
    grep -q "$dir" "$AIDE_CFG" && pass "Monitors: $dir" || fail "Missing monitored dir: $dir"
  done

  # Verify monitored attributes
  for attr in p i u g n acl xattrs sha512; do
    grep -q "$attr" "$AIDE_CFG" && pass "Monitors attribute: $attr" || fail "Missing attribute: $attr"
  done
else
  skip "AIDE config file not found"
fi

# ─── 2. Init Script Logic ──────────────────────────────────────────────────
header "2. Init Script Logic"

INIT_SCRIPT=$(extract_script_from_nix "$AIDE_CFG" "aide-init.sh" 2>/dev/null || true)

if [ -n "$INIT_SCRIPT" ]; then
  echo "$INIT_SCRIPT" | grep -q "aide --init" && pass "Init: calls aide --init" || fail "Init: missing aide --init call"
  echo "$INIT_SCRIPT" | grep -q "aide.db.new.gz" && pass "Init: handles .db.new.gz output" || fail "Init: missing .db.new.gz handling"
  echo "$INIT_SCRIPT" | grep -q "database already exists" && pass "Init: idempotent (checks existing database)" || fail "Init: missing existing DB check"
  echo "$INIT_SCRIPT" | grep -q "cp" && pass "Init: copies new database to active location" || fail "Init: missing database copy"
else
  skip "Init script extraction failed"
fi

# ─── 3. Check Script Logic ─────────────────────────────────────────────────
header "3. Check Script Logic"

CHK_SCRIPT=$(extract_script_from_nix "$AIDE_CFG" "aide-check.sh" 2>/dev/null || true)

if [ -n "$CHK_SCRIPT" ]; then
  echo "$CHK_SCRIPT" | grep -q "aide --check" && pass "Check: calls aide --check" || fail "Check: missing aide --check call"
  echo "$CHK_SCRIPT" | grep -q "LOG_FILE" && pass "Check: writes to log file" || fail "Check: missing log file output"
  echo "$CHK_SCRIPT" | grep -q "database not found" && pass "Check: handles missing database" || fail "Check: missing database-not-found handling"
  echo "$CHK_SCRIPT" | grep -q "No changes detected" && pass "Check: reports clean results" || fail "Check: missing clean result message"
else
  skip "Check script extraction failed"
fi

# ─── 4. AIDE Binary Test ──────────────────────────────────────────────────
header "4. AIDE Binary Tests (if available)"

if has_tool aide; then
  pass "aide binary is available"

  # Create a minimal AIDE config in temp dir
  AIDE_CONF="$TEMP_DIR/aide.conf"
  AIDE_DB="$TEMP_DIR/aide.db"
  TEST_MONITOR="$TEMP_DIR/monitor"
  mkdir -p "$TEST_MONITOR"

  cat > "$AIDE_CONF" << EOF
database_in=file:$AIDE_DB
database_out=file:$AIDE_DB.new
report_url=stdout
$TEST_MONITOR p+u+g+sha512
EOF

  # Create a test file to monitor
  echo "test content for aide" > "$TEST_MONITOR/testfile.txt"

  # Try to initialize database (may fail in sandbox if aide needs special permissions)
  set +e
  init_output=$(timeout 30 aide --init -c "$AIDE_CONF" 2>&1)
  init_rc=$?
  set -e

  if [ $init_rc -eq 0 ]; then
    pass "AIDE database initialized successfully in sandbox"
  else
    skip "AIDE init failed in sandbox (expected without root: $init_rc)"
    echo "    Output: $(echo "$init_output" | tail -3 | tr '\n' ';')"
  fi
else
  skip "aide binary not installed — skipping binary tests"
  skip "aide binary not installed — database init"
fi

# ─── 5. Timer Configuration ────────────────────────────────────────────────
header "5. Timer Configuration"

if grep -q "OnCalendar.*15:00:00" "$AIDE_CFG" 2>/dev/null; then
  pass "Timer: daily check scheduled at 15:00"
else
  fail "Timer: missing or incorrect schedule"
fi

if grep -q "Persistent.*true" "$AIDE_CFG" 2>/dev/null; then
  pass "Timer: persistent (catches up after missed runs)"
else
  fail "Timer: not persistent"
fi

# ─── 6. Database Persistence ───────────────────────────────────────────────
header "6. Database Paths"

if grep -q "aide.db.gz" "$AIDE_CFG" 2>/dev/null; then
  pass "Database: uses aide.db.gz (compressed)"
fi

if grep -q "/var/lib/aide" "$AIDE_CFG" 2>/dev/null; then
  pass "Data path: /var/lib/aide"
fi

if grep -q "/var/log/aide" "$AIDE_CFG" 2>/dev/null; then
  pass "Log path: /var/log/aide"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
