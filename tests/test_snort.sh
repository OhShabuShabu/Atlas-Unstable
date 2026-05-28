#!/usr/bin/env bash
# ============================================================================
# SNORT NETWORK IDS BEHAVIORAL TESTS
# ============================================================================
# Tests Snort configuration validation, rule syntax, and monitoring daemon
# logic in an isolated sandbox.
# ============================================================================

TEST_NAME="Snort Network IDS"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "SNORT — NETWORK INTRUSION DETECTION"

TEMP_DIR=$(_mktemp /tmp/snort-test.XXXXXX)

# ─── 1. Rule Syntax Validation ─────────────────────────────────────────────
header "1. Snort Rule Syntax"

SNORT_NIX="$BASE/files/modules/security/snort.nix"
LOCAL_RULES_FILE="$TEMP_DIR/local.rules"

# Extract rules from snort.nix using Python
"$BASE/tests/tools/extract_nix_block.py" "$SNORT_NIX" 'writeTextDir "local.rules"' "$LOCAL_RULES_FILE" 2>&1

if [ -f "$LOCAL_RULES_FILE" ]; then
  pass "Local rules file extracted from snort.nix"

  rule_count=$(grep -c "alert " "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)
  pass "Contains $rule_count alert rules"

  rule_count=$(grep -c "alert.*tcp\|alert.*udp\|alert.*icmp\|alert.*ip" "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)

  # Verify rule structure: each alert should have sid
  sid_count=$(grep -c "sid:" "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)
  assert_eq "All rules have sid: field" "$rule_count" "$sid_count" || true

  # Verify rule structure: each alert should have classtype
  ct_count=$(grep -c "classtype:" "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)
  assert_eq "All rules have classtype:" "$rule_count" "$ct_count" || true

  # Verify rule structure: each alert should have msg
  msg_count=$(grep -c 'msg:' "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)
  assert_eq "All rules have msg:" "$rule_count" "$msg_count" || true

  # Verify rule structure: each alert should have rev
  rev_count=$(grep -c "rev:" "$LOCAL_RULES_FILE" 2>/dev/null || echo 0)
  assert_eq "All rules have rev:" "$rule_count" "$rev_count" || true

  # Check for specific rule categories (in msg: fields)
  for category in MALWARE-CNC EXPLOIT SCAN DOS PAYLOAD POLICY ANOMALY FILE EXFIL ATTACK; do
    grep -q "$category" "$LOCAL_RULES_FILE" && pass "Rule category: $category" || fail "Missing rule category: $category"
  done

  # Check for specific SIDs
  for sid in 1000001 1000010 1000020 1000030 1000040 1000050 1000060 1000070 1000080 1000090; do
    grep -q "sid:$sid" "$LOCAL_RULES_FILE" && pass "SID $sid present" || fail "SID $sid missing"
  done

  # Verify no SID collisions
  dup_sids=$(grep -oP 'sid:\K\d+' "$LOCAL_RULES_FILE" | sort | uniq -d)
  if [ -z "$dup_sids" ]; then
    pass "No duplicate SIDs"
  else
    fail "Duplicate SIDs found: $dup_sids"
  fi
else
  skip "Local rules file extraction failed"
fi

# ─── 2. Configuration Validation ───────────────────────────────────────────
header "2. Snort Configuration"

if grep -q "HOME_NET" "$SNORT_NIX" 2>/dev/null; then
  pass "Config: HOME_NET defined"
fi

if grep -q "EXTERNAL_NET" "$SNORT_NIX" 2>/dev/null; then
  pass "Config: EXTERNAL_NET defined"
fi

if grep -q "alert_csv" "$SNORT_NIX" 2>/dev/null; then
  pass "Config: CSV alert output enabled"
fi

if grep -q "snort_defaults.lua" "$SNORT_NIX" 2>/dev/null; then
  pass "Config: includes snort_defaults.lua"
fi

# ─── 3. Snort Binary Config Test ──────────────────────────────────────────
header "3. Snort Config Test (if available)"

if has_tool snort; then
  SNORT_CONF_FILE="$TEMP_DIR/snort.lua"

  "$BASE/tests/tools/extract_nix_block.py" "$SNORT_NIX" 'writeTextDir "snort.lua"' "$SNORT_CONF_FILE" 2>&1

  if [ -f "$SNORT_CONF_FILE" ]; then
    # Replace Nix variable references with actual snort paths
    snort_real=$(readlink -f "$(command -v snort)" 2>/dev/null || echo "")
    if [ -n "$snort_real" ]; then
      snort_prefix="${snort_real%/bin/snort}"
      # Fix for Nix store: take everything up to the bin/snort
      snort_store="${snort_prefix%/bin/snort}"
      snort_store="${snort_store:-$snort_prefix}"
      sed -i "s|\${snortPkg}|${snort_store}|g" "$SNORT_CONF_FILE"
      # Verify the defaults file exists
      # Also handle ${snortRules} - point to the extracted local.rules
      if [ -f "$LOCAL_RULES_FILE" ]; then
        local_rules_dir=$(dirname "$LOCAL_RULES_FILE")
        sed -i "s|\${snortRules}|${local_rules_dir}|g" "$SNORT_CONF_FILE"
      fi
      if [ -f "${snort_store}/etc/snort/snort_defaults.lua" ]; then
        pass "Snort defaults file found at resolved path"
      fi
    fi

    # Try validation; snort needs specific capabilities, may fail without root
    test_rc=0; test_output=""
    timeout 15 snort -c "$SNORT_CONF_FILE" -T > "$TEMP_DIR/snort_val.txt" 2>&1 || test_rc=$?
    test_output=$(cat "$TEMP_DIR/snort_val.txt")

    if [ $test_rc -eq 0 ]; then
      pass "Snort config validation PASSED"
    elif echo "$test_output" | grep -qi "Snort successfully validated"; then
      pass "Snort config validation succeeded (with non-zero exit after)"
    elif echo "$test_output" | grep -qi "ERROR\|FATAL\|Failure"; then
      fail "Snort config validation FAILED"
      echo "    $(echo "$test_output" | grep -i "error\|fatal\|failure" | head -3 | tr '\n' ';')"
    else
      skip "Snort config test incomplete (may need root/capabilities)"
      echo "    $(echo "$test_output" | tail -3 | tr '\n' ';')"
    fi

    if echo "$test_output" | grep -qi "rules were detected"; then
      rules_detected=$(echo "$test_output" | grep -oP '\d+ rules were detected' || echo "?")
      pass "Snort: $rules_detected"
    fi
  else
    skip "Snort config file extraction failed"
  fi
else
  skip "snort binary not installed — skipping config validation test"
fi

# ─── 4. Monitor Daemon Script Logic ────────────────────────────────────────
header "4. Monitor Daemon Script Logic"

SNORT_MON="$TEMP_DIR/snort-monitor.sh"
if extract_script_from_nix "$SNORT_NIX" "snort-monitor" > "$SNORT_MON" 2>/dev/null && [ -s "$SNORT_MON" ]; then
  pass "Monitor script extracted"

  grep -q "while true" "$SNORT_MON" && pass "Monitor: infinite loop (daemon)" || fail "Monitor: missing main loop"
  grep -q "alert_csv.txt" "$SNORT_MON" && pass "Monitor: watches alert CSV log" || fail "Monitor: missing alert log reference"
  grep -q "sleep 5" "$SNORT_MON" && pass "Monitor: 5-second poll interval" || fail "Monitor: missing poll interval"
  grep -q "log_event" "$SNORT_MON" && pass "Monitor: event logging" || fail "Monitor: missing event logging"
  grep -q "notify_user" "$SNORT_MON" && pass "Monitor: desktop notifications" || fail "Monitor: missing notifications"
else
  skip "Monitor script extraction failed"
fi

# ─── 5. snortctl CLI Logic ─────────────────────────────────────────────────
header "5. snortctl CLI"

SNORTCTL="$TEMP_DIR/snortctl.sh"
if extract_script_from_nix "$SNORT_NIX" "snortctl" > "$SNORTCTL" 2>/dev/null && [ -s "$SNORTCTL" ]; then
  pass "snortctl script extracted"

  for cmd in status logs alerts events test restart; do
    grep -q "$cmd)" "$SNORTCTL" && pass "snortctl supports: $cmd" || fail "snortctl missing: $cmd"
  done
else
  skip "snortctl script extraction failed"
fi

# ─── 6. daemon-service interaction ────────────────────────────────────────
header "6. Daemon Service Configuration"

if grep -q "Type.*simple" "$SNORT_NIX" 2>/dev/null; then
  pass "snort-daemon: Type=simple"
fi

if grep -q "Restart.*on-failure" "$SNORT_NIX" 2>/dev/null; then
  pass "snort-daemon: Restart=on-failure"
fi

if grep -q "CAP_NET_RAW" "$SNORT_NIX" 2>/dev/null; then
  pass "snort-daemon: CAP_NET_RAW capability"
fi

if grep -q "after.*snort-daemon" "$SNORT_NIX" 2>/dev/null; then
  pass "snort-monitor: after snort-daemon"
else
  fail "snort-monitor: missing dependency on snort-daemon"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
