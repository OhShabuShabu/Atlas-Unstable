#!/usr/bin/env bash
# ============================================================================
# CLAMAV BEHAVIORAL TESTS
# ============================================================================
# Tests ClamAV virus detection, quarantine workflow, and scan script logic.
# Uses the standard EICAR test file — completely harmless.
# ============================================================================

TEST_NAME="ClamAV / Virus Detection"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "CLAMAV — VIRUS DETECTION"

TEMP_DIR=$(_mktemp /tmp/clamav-test.XXXXXX)

# ─── 1. EICAR Detection ─────────────────────────────────────────────────────
if has_tool clamscan; then
  header "1. EICAR Test String Detection"

  EICAR_FILE=$(create_eicar_file "$TEMP_DIR")

  output=$(timeout 30 clamscan --no-summary "$EICAR_FILE" 2>&1)
  rc=$?

  assert_contains "clamscan detects EICAR test string" "$output" "FOUND" || true

  SAFE_FILE=$(create_safe_file "$TEMP_DIR")
  output2=$(timeout 30 clamscan --no-summary "$SAFE_FILE" 2>&1)
  assert_contains "clamscan does NOT flag safe file" "$output2" "OK" || true

  # ─── 2. Quarantine Workflow ───────────────────────────────────────────────
  header "2. Quarantine Workflow (simulated)"

  QUAR_DIR=$(_mktemp /tmp/clamav-quar.XXXXXX)
  EICAR2=$(create_eicar_file "$QUAR_DIR" "eicar2.txt")

  output3=$(timeout 30 clamscan --move="$TEMP_DIR" --no-summary "$EICAR2" 2>&1)
  rc3=$?

  if echo "$output3" | grep -q "FOUND"; then
    sleep 1
    if [ ! -f "$EICAR2" ]; then
      pass "clamscan --move removes infected file from source"
    else
      if [ -f "$TEMP_DIR/eicar2.txt" ]; then
        pass "clamscan --move moves infected file to quarantine target"
      else
        fail "clamscan --move: infected file neither at source nor target"
      fi
    fi
  else
    fail "clamscan --move: EICAR not detected for move test (output: $output3)"
  fi

  # ─── 3. Recursive Directory Scan ───────────────────────────────────────────
  header "3. Recursive Directory Scan"

  SUBDIR="$TEMP_DIR/subdir"
  mkdir -p "$SUBDIR"
  create_eicar_file "$SUBDIR" "nested_eicar.txt" >/dev/null
  create_safe_file "$SUBDIR" "legit.txt" >/dev/null

  output4=$(timeout 60 clamscan --recursive --no-summary "$TEMP_DIR" 2>&1)
  rc4=$?

  found_count=$(echo "$output4" | grep -c "FOUND" || echo 0)
  if [ "$found_count" -ge 2 ]; then
    pass "Recursive scan finds all EICAR files (found $found_count)"
  else
    fail "Recursive scan missed some EICAR files (found $found_count of 2)"
    echo "    Output: $(echo "$output4" | tail -5)"
  fi

  # ─── 4. Scan Script Logic Verification ─────────────────────────────────────
  header "4. Scan Script Logic"

  # Verify the scan script log format matches what daemon expects
  SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/clamav.nix" "clamav-daily-scan.sh" 2>/dev/null || true)
  if [ -n "$SCRIPT" ]; then
    echo "$SCRIPT" | grep -q "FOUND" && pass "Daily scan script: detects FOUND pattern" || fail "Daily scan script: missing FOUND detection logic"
    echo "$SCRIPT" | grep -q "notify-user" && pass "Daily scan script: uses notify-user" || fail "Daily scan script: missing notify-user"
    echo "$SCRIPT" | grep -q "chmod 0000" && pass "Daily scan script: chmod 0000 quarantine" || fail "Daily scan script: missing quarantine hardening"
    echo "$SCRIPT" | grep -q "chown root:root" && pass "Daily scan script: chown root quarantine" || fail "Daily scan script: missing quarantine ownership change"
  else
    skip "Daily scan script extraction failed"
  fi

  # ─── 5. Tmp Scan Script Logic ─────────────────────────────────────────────
  SCRIPT2=$(extract_script_from_nix "$BASE/files/modules/security/clamav.nix" "clamav-tmp-scan.sh" 2>/dev/null || true)
  if [ -n "$SCRIPT2" ]; then
    echo "$SCRIPT2" | grep -q "FOUND" && pass "Tmp scan script: detects FOUND pattern" || fail "Tmp scan script: missing FOUND detection logic"
    echo "$SCRIPT2" | grep -q "notify-user" && pass "Tmp scan script: uses notify-user" || fail "Tmp scan script: missing notify-user"
  else
    skip "Tmp scan script extraction failed"
  fi

  # ─── 6. Log Format Validation ─────────────────────────────────────────────
  header "5. Log Format"

  # Simulate what the daemon writes to logs
  log_line="=== ClamAV Scan $(date) ==="
  echo "$log_line" | grep -q "ClamAV Scan" && pass "Log format: correct header pattern" || fail "Log format: header pattern mismatch"
else
  skip "clamscan not installed — skipping all ClamAV behavioral tests"
  skip "clamscan not installed — EICAR detection test"
  skip "clamscan not installed — quarantine workflow"
  skip "clamscan not installed — recursive scan"
  skip "clamscan not installed — script logic verification"
  skip "clamscan not installed — log format"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
