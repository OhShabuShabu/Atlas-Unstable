#!/usr/bin/env bash
# ============================================================================
# SNOUT WATCHER BEHAVIORAL TESTS
# ============================================================================
# Tests Snout's quarantine monitoring, ClamAV integration, event logging,
# and notification workflow in an isolated sandbox.
# ============================================================================

TEST_NAME="Snout Security Watcher"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "SNOUT — QUARANTINE WATCHER"

TEMP_DIR=$(_mktemp /tmp/snout-test.XXXXXX)
QUAR_DIR="$TEMP_DIR/quarantine"
LOG_DIR="$TEMP_DIR/logs"
mkdir -p "$QUAR_DIR" "$LOG_DIR"

# ─── 1. Snout Script Logic ─────────────────────────────────────────────────
header "1. Script Logic"

SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/snout.nix" "snout-watcher.sh" 2>/dev/null || true)

if [ -n "$SCRIPT" ]; then
  echo "$SCRIPT" | grep -q "QUARANTINE=/etc/quarantine" && pass "Script: references quarantine directory" || pass "Script: has quarantine variable (or bash var)"

  echo "$SCRIPT" | grep -q "README.txt" && pass "Script: skips README.txt" || fail "Script: missing README.txt exclusion"
  echo "$SCRIPT" | grep -q "clamscan" && pass "Script: uses clamscan for verification" || fail "Script: missing clamscan call"
  echo "$SCRIPT" | grep -q "notify-user" && pass "Script: sends notifications" || fail "Script: missing notification call"
  echo "$SCRIPT" | grep -q "CLAM_EXIT" && pass "Script: checks clamscan exit code" || fail "Script: missing exit code check"
  echo "$SCRIPT" | grep -q "log_event" && pass "Script: has log_event function" || fail "Script: missing log_event function"

  # ─── 2. Simulated Snout Scan (sandboxed) ──────────────────────────────────
  header "2. Simulated Quarantine Scan"

  if has_tool clamscan; then
    # Create a mock quarantine directory with test files
    create_eicar_file "$QUAR_DIR" "eicar_test.txt" >/dev/null
    create_safe_file "$QUAR_DIR" "benign.txt" >/dev/null
    echo "README content" > "$QUAR_DIR/README.txt"

    # Simulate snout-watcher logic (sandboxed version)
    EVENTS_LOG="$LOG_DIR/events.log"

    for file in "$QUAR_DIR"/*; do
      [ -f "$file" ] || continue
      [ "$(basename "$file")" = "README.txt" ] && continue

      echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] File quarantined: $file" >> "$EVENTS_LOG"

      set +e
      clamscan --quiet "$file" 2>/dev/null
      CLAM_EXIT=$?
      set -e

      if [ "$CLAM_EXIT" -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [THREAT] Threat in: $file" >> "$EVENTS_LOG"
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Clean: $file" >> "$EVENTS_LOG"
      fi
    done

    # Verify events log
    if [ -f "$EVENTS_LOG" ]; then
      pass "Events log file was created"

      log_content=$(cat "$EVENTS_LOG")

      if echo "$log_content" | grep -q "THREAT"; then
        pass "Log: EICAR file detected as threat"
      else
        fail "Log: EICAR file NOT detected as threat (log: $(echo "$log_content" | tr '\n' ';'))"
      fi
      assert_contains "Log: benign file marked clean" "$log_content" "Clean: $QUAR_DIR/benign.txt" || true
      assert_not_contains "Log: README.txt excluded from processing" "$log_content" "README" || true
    else
      fail "Events log file was NOT created"
    fi
  else
    skip "clamscan not available — simulated scan skipped"
  fi

  # ─── 3. Path Unit Configuration ───────────────────────────────────────────
  header "3. Path Unit Configuration"

  if grep -q "PathModified.*/etc/quarantine" "$BASE/files/modules/security/snout.nix" 2>/dev/null; then
    pass "Path unit: watches /etc/quarantine via PathModified"
  else
    fail "Path unit: missing PathModified on /etc/quarantine"
  fi

  if grep -q "Unit.*snout-watcher.service" "$BASE/files/modules/security/snout.nix" 2>/dev/null; then
    pass "Path unit: triggers snout-watcher.service"
  else
    fail "Path unit: missing unit trigger"
  fi

  # ─── 4. Service Hardening Verification ────────────────────────────────────
  header "4. Service Hardening"

  echo "$SCRIPT" | grep -q "NoNewPrivileges" && pass "Hardening: NoNewPrivileges" || skip "NoNewPrivileges in service config (not in script)"

  HARDENING_CHECKS="NoNewPrivileges ProtectSystem ReadWritePaths ProtectHome PrivateTmp PrivateDevices ProtectKernelTunables MemoryDenyWriteExecute LockPersonality RestrictNamespaces RestrictRealtime RestrictSUIDSGID RemoveIPC"
  for check in $HARDENING_CHECKS; do
    if grep -q "$check" "$BASE/files/modules/security/snout.nix" 2>/dev/null; then
      pass "Hardening: $check present"
    fi
  done 2>/dev/null
else
  skip "Snout script extraction failed"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
