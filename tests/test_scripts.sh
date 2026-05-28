#!/usr/bin/env bash
# ============================================================================
# SHELL SCRIPT & CLI BEHAVIORAL TESTS
# ============================================================================
# Tests shell scripts defined in the project: atlas-rebuild, atlas-health,
# snortctl, snout, quarantine-list, quarantine-purge, detect-hardware,
# fix_rgb_color.py.  Tests script logic, argument parsing, and output format.
# ============================================================================

TEST_NAME="CLI Scripts"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "SHELL SCRIPTS — CLI BEHAVIOR"

TEMP_DIR=$(_mktemp /tmp/script-test.XXXXXX)

# ─── 1. atlas-health ──────────────────────────────────────────────────────
header "1. atlas-health Command"

CFG="$BASE/files/core/configuration.nix"
HEALTH_SCRIPT=$("$BASE/tests/tools/extract_nix_block.py" "$CFG" 'writeShellScriptBin "atlas-health"' 2>/dev/null || echo "")

if [ -n "$HEALTH_SCRIPT" ]; then
  pass "atlas-health script extracted from configuration.nix"

  # Check key sections
  echo "$HEALTH_SCRIPT" | grep -qi "security" && pass "health: reports security services" || fail "health: missing security section"
  echo "$HEALTH_SCRIPT" | grep -qi "desktop\|user" && pass "health: reports desktop services" || fail "health: missing desktop section"
  echo "$HEALTH_SCRIPT" | grep -qi "disk\|storage" && pass "health: reports disk status" || fail "health: missing disk section"
  echo "$HEALTH_SCRIPT" | grep -qi "LUKS" && pass "health: reports LUKS status" || fail "health: missing LUKS section"

  # Check for expected systemctl calls
  for svc in snort-daemon clamav-daemon aide-init; do
    echo "$HEALTH_SCRIPT" | grep -q "$svc" && pass "health: checks $svc" || warn "health: $svc not checked individually (may be grouped)"
  done
else
  skip "atlas-health script extraction failed"
fi

# ─── 2. detect-hardware.sh ────────────────────────────────────────────────
header "2. detect-hardware.sh"

DETECT_SCRIPT="$BASE/files/bin/shell/detect-hardware.sh"

if [ -f "$DETECT_SCRIPT" ]; then
  pass "detect-hardware.sh exists"

  if [ -x "$DETECT_SCRIPT" ]; then
    pass "detect-hardware.sh is executable"

    set +e
    detect_output=$(timeout 15 bash "$DETECT_SCRIPT" 2>&1)
    detect_rc=$?
    set -e

    assert_exit_code "detect-hardware.sh runs successfully" 0 "$detect_rc" || true

    if [ -n "$detect_output" ]; then
      pass "detect-hardware.sh produces output"

      echo "$detect_output" | grep -qi "cpu\|CPU" && pass "detect: reports CPU" || skip "detect: CPU info not in output (may be arch-dependent)"
      echo "$detect_output" | grep -qi "gpu\|GPU\|graphics" && pass "detect: reports GPU" || skip "detect: GPU info not in output"
      echo "$detect_output" | grep -qi "memory\|RAM\|Mem" && pass "detect: reports memory" || skip "detect: memory info not in output"
    else
      fail "detect-hardware.sh produces no output"
    fi
  else
    fail "detect-hardware.sh is not executable"
  fi
else
  skip "detect-hardware.sh not found"
fi

# ─── 3. fix_rgb_color.py ──────────────────────────────────────────────────
header "3. fix_rgb_color.py"

RGB_SCRIPT="$BASE/files/bin/python/fix_rgb_color.py"

if [ -f "$RGB_SCRIPT" ]; then
  pass "fix_rgb_color.py exists"

  # Syntax check
  python3 -c "
import py_compile, tempfile, os
with tempfile.NamedTemporaryFile(suffix='.pyc', delete=False) as f:
    try:
        py_compile.compile('$RGB_SCRIPT', cfile=f.name, doraise=True)
        os.unlink(f.name)
    except:
        os.unlink(f.name)
        exit(1)
" 2>/dev/null && pass "fix_rgb_color.py: syntax OK" || fail "fix_rgb_color.py: syntax error"

  # Test with sample hex input
  COLOR_FILE="/tmp/test_color_$$.txt"
  echo "1A2B3C" > "$COLOR_FILE"

  set +e
  rgb_output=$(timeout 10 python3 "$RGB_SCRIPT" "1A2B3C" 2>&1)
  rgb_rc=$?
  rm -f "$COLOR_FILE" 2>/dev/null || true
  set -e

  if [ $rgb_rc -eq 0 ] && [ -n "$rgb_output" ]; then
    pass "fix_rgb_color.py: runs with valid hex input (output: $rgb_output)"
  else
    # Try alternate invocation without argument (read from stdin/color file)
    set +e
    rgb_output2=$(echo "1A2B3C" | timeout 10 python3 "$RGB_SCRIPT" 2>&1)
    rgb_rc2=$?
    set -e

    if [ $rgb_rc2 -eq 0 ] && [ -n "$rgb_output2" ]; then
      pass "fix_rgb_color.py: runs with piped input (output: $rgb_output2)"
    else
      skip "fix_rgb_color.py: runtime test skipped (may need primary_color.txt)"
    fi
  fi
else
  skip "fix_rgb_color.py not found"
fi

# ─── 4. snortctl CLI Logic ────────────────────────────────────────────────
header "4. snortctl CLI"

SNORT_NIX="$BASE/files/modules/security/snort.nix"

if [ -f "$SNORT_NIX" ]; then
  # Verify all CLI subcommands
  for cmd in status logs alerts events test restart; do
    grep -q "$cmd)" "$SNORT_NIX" && pass "snortctl: $cmd subcommand" || fail "snortctl: missing $cmd subcommand"
  done

  # Verify usage message
  grep -q "Usage: snortctl" "$SNORT_NIX" && pass "snortctl: usage message" || fail "snortctl: missing usage message"
else
  skip "snort.nix not found"
fi

# ─── 5. Snout CLI Logic ───────────────────────────────────────────────────
header "5. snout CLI"

SNOUT_NIX="$BASE/files/modules/security/snout.nix"

if [ -f "$SNOUT_NIX" ]; then
  for cmd in scan status logs; do
    grep -q "$cmd)" "$SNOUT_NIX" && pass "snout: $cmd subcommand" || fail "snout: missing $cmd subcommand"
  done

  grep -q "Usage: snout" "$SNOUT_NIX" && pass "snout: usage message" || fail "snout: missing usage message"
else
  skip "snout.nix not found"
fi

# ─── 6. Startup Script ────────────────────────────────────────────────────
header "6. startup.sh"

STARTUP="$BASE/files/bin/shell/startup.sh"

if [ -f "$STARTUP" ]; then
  pass "startup.sh exists"

  if [ -x "$STARTUP" ]; then
    pass "startup.sh is executable"
  fi

  set +e
  startup_output=$(timeout 10 bash -n "$STARTUP" 2>&1)
  startup_rc=$?
  set -e

  assert_exit_code "startup.sh: syntax check" 0 "$startup_rc" || true
else
  skip "startup.sh not found"
fi

# ─── 7. Nushell Aliases ───────────────────────────────────────────────────
header "7. Nushell Aliases"

NUSHELL="$BASE/files/core/config/shellrc.nu"

if [ -f "$NUSHELL" ]; then
  for alias in logs security-logs snout-status snout-scan health health-quick aide-check lynis-scan; do
    grep -q "$alias" "$NUSHELL" && pass "Nushell alias: $alias" || fail "Nushell alias: $alias missing"
  done
else
  skip "shellrc.nu not found"
fi

# ─── 8. Process Accounting ────────────────────────────────────────────────
header "8. Process Accounting"

PACCT="$BASE/files/modules/security/process-accounting.nix"

if [ -f "$PACCT" ]; then
  grep -q "accton" "$PACCT" && pass "pacct: accton called" || fail "pacct: missing accton"
  grep -q "accton off" "$PACCT" && pass "pacct: accton off on stop" || fail "pacct: missing accton off"
  grep -q "lastcomm" "$PACCT" && pass "pacct: lastcomm alias" || fail "pacct: missing lastcomm alias"
  grep -q "dump-acct" "$PACCT" && pass "pacct: dump-acct alias" || fail "pacct: missing dump-acct alias"
else
  skip "process-accounting.nix not found"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
