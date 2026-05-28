#!/usr/bin/env bash
# ============================================================================
# ATLAS DAEMON BEHAVIORAL TEST SUITE
# ============================================================================
# Run: bash tests/run.sh
#
# Tests all custom daemons and services for correct behavior:
#   - ClamAV virus detection (EICAR test)
#   - Metadata stripper (EXIF removal)
#   - Snout quarantine watcher
#   - Quarantine system (setup, sanitizer, cleanup)
#   - AIDE file integrity (config, init, check)
#   - Snort NIDS (config, rules, monitor)
#   - Systemd integration (services, timers, paths)
#   - CLI scripts (atlas-health, detect-hardware, etc.)
#
# All tests use isolated temp directories — safe to run without root.
# ============================================================================

set -uo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE" || exit 1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0
EXIT_CODE=0
TEST_DIR="$BASE/tests"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        ATLAS DAEMON BEHAVIORAL TEST SUITE                   ║${NC}"
echo -e "${CYAN}║        $TIMESTAMP${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Base:      ${YELLOW}$BASE${NC}"
echo -e "  Test dir:  ${YELLOW}$TEST_DIR${NC}"
echo ""

# ─── Test Modules ──────────────────────────────────────────────────────────
declare -a TEST_MODULES=(
  "test_clamav.sh:ClamAV / Virus Detection"
  "test_metadata.sh:Metadata Stripper"
  "test_snout.sh:Snout Security Watcher"
  "test_quarantine.sh:Quarantine System"
  "test_aide.sh:AIDE File Integrity"
  "test_snort.sh:Snort Network IDS"
  "test_systemd.sh:Systemd Integration"
  "test_scripts.sh:CLI Scripts"
)

for entry in "${TEST_MODULES[@]}"; do
  file="${entry%%:*}"
  name="${entry##*:}"
  script="$TEST_DIR/$file"

  if [ ! -f "$script" ]; then
    echo -e "  ${YELLOW}⚠ Test module not found: $file${NC}"
    continue
  fi

  echo -e "\n${CYAN}────────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}  RUNNING: $name${NC}"
  echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

  # Run in a subshell with its own PASS/FAIL/SKIP tracking
  set +e
  output=$(ATLAS_BASE="$BASE" bash "$script" 2>&1)
  rc=$?
  set -e

  # Extract PASS/FAIL/SKIP counts from machine-parseable line
  module_line=$(echo "$output" | grep "^MODULE_RESULT:" | tail -1 || echo "")
  if [ -n "$module_line" ]; then
    module_pass=$(echo "$module_line" | grep -oP 'PASS=\K\d+' || echo "0")
    module_fail=$(echo "$module_line" | grep -oP 'FAIL=\K\d+' || echo "0")
    module_skip=$(echo "$module_line" | grep -oP 'SKIP=\K\d+' || echo "0")
  else
    module_pass=0; module_fail=0; module_skip=0
  fi

  TOTAL_PASS=$((TOTAL_PASS + module_pass))
  TOTAL_FAIL=$((TOTAL_FAIL + module_fail))
  TOTAL_SKIP=$((TOTAL_SKIP + module_skip))

  # Print the module output (indented)
  echo "$output" | while IFS= read -r line; do
    echo "  $line"
  done

  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
    EXIT_CODE=1
  fi
done

# ─── Summary ────────────────────────────────────────────────────────────────
TOTAL=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))

echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  FINAL SUMMARY                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "  ${GREEN}PASS:${NC}  $TOTAL_PASS"
echo -e "  ${RED}FAIL:${NC}  $TOTAL_FAIL"
echo -e "  ${YELLOW}SKIP:${NC}  $TOTAL_SKIP"
echo -e "  Total: $TOTAL"

if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo -e "\n  ${RED}✗ ${TOTAL_FAIL} TEST(S) FAILED — review output above.${NC}"
  exit 1
elif [ "$TOTAL_PASS" -eq 0 ] && [ "$TOTAL_SKIP" -gt 0 ]; then
  echo -e "\n  ${YELLOW}⊘ All tests skipped (no tools available?)${NC}"
  exit 2
else
  echo -e "\n  ${GREEN}✓ ALL ${TOTAL_PASS} TESTS PASSED${NC}"
  exit 0
fi
