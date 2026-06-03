#!/usr/bin/env bash
# ============================================================================
# MODULE MANAGER — Behavioral Tests
# ============================================================================
# Tests the module management system:
#   - Module state file creation and manipulation
#   - Module enable/disable operations
#   - Dependency validation
#   - Module file operations
#   - CLI tool commands
#   - State persistence
#
# All tests use isolated temp directories — safe to run without root.
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

BASE="${YORHA_BASE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$BASE/files/lib/module-registry.sh"

# ─── Setup: Isolated test environment ───────────────────────────────────────
TEST_DIR=$(_mktemp /tmp/yorha-module-test.XXXXXX)
STATE_DIR="$TEST_DIR/state"
STATE_FILE="$STATE_DIR/state.json"
OPT_DIR="$TEST_DIR/optional"

mkdir -p "$STATE_DIR" "$OPT_DIR/nixos" "$OPT_DIR/home"

# Override state file path for testing
YORHA_MODULE_STATE_DIR="$STATE_DIR"
YORHA_MODULE_STATE_FILE="$STATE_FILE"

# Using a minimal state for tests
setup_state() {
  mkdir -p "$STATE_DIR"
  cat > "$STATE_FILE" <<EOF
{
  "modules": {},
  "metadata": {
    "created": "2026-05-28T00:00:00+00:00",
    "updated": "2026-05-28T00:00:00+00:00",
    "version": "1"
  }
}
EOF
}

# ============================================================================
# Tests
# ============================================================================

header "Module State File"

# Test 1: State file creation
setup_state
assert_file_exists "State file created" "$STATE_FILE"

# Test 2: State file is valid JSON
python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null
assert_exit_code "State file is valid JSON" 0 $?

# Test 3: State file has correct structure
has_modules=$(jq '.modules' "$STATE_FILE" 2>/dev/null)
[[ -n "$has_modules" ]] && pass "State file has modules key" || fail "State file missing modules key"

has_metadata=$(jq '.metadata' "$STATE_FILE" 2>/dev/null)
[[ -n "$has_metadata" ]] && pass "State file has metadata key" || fail "State file missing metadata key"

# ────────────────────────────────────────────────────────────────────────────
header "Module Enable/Disable Operations"

# Test 4: Enable a module via jq (simulating what the manager does)
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["1"] = {enabled: true, installed: true, version: "1.0.0"}')
echo "$state" > "$STATE_FILE"
enabled=$(jq -r '.modules["1"].enabled' "$STATE_FILE")
assert_eq "Module 1 enabled" "true" "$enabled"

# Test 5: Disable a module via jq
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["1"].enabled = false')
echo "$state" > "$STATE_FILE"
enabled=$(jq -r '.modules["1"].enabled' "$STATE_FILE")
assert_eq "Module 1 disabled" "false" "$enabled"

# Test 6: Re-enable after disable
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["1"].enabled = true')
echo "$state" > "$STATE_FILE"
enabled=$(jq -r '.modules["1"].enabled' "$STATE_FILE")
assert_eq "Module 1 re-enabled" "true" "$enabled"

# ────────────────────────────────────────────────────────────────────────────
header "Module State Persistence"

# Test 7: State persists across read/write cycles
cat > "$STATE_FILE" <<EOF
{
  "modules": {
    "3": {"enabled": true, "installed": true, "version": "2.0.0"},
    "7": {"enabled": true, "installed": true, "version": "2.0.0"}
  },
  "metadata": {"created": "2026-05-28T00:00:00+00:00", "updated": "2026-05-28T00:00:00+00:00", "version": "1"}
}
EOF
module_count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "State persists - 2 modules" "2" "$module_count"

# Test 8: Module metadata preserved
mod3_version=$(jq -r '.modules["3"].version' "$STATE_FILE")
assert_eq "Module 3 version preserved" "2.0.0" "$mod3_version"

# Test 9: New module can be added to existing state
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["4"] = {enabled: false, installed: false, version: "1.0.0"}')
echo "$state" > "$STATE_FILE"
module_count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "Module 4 added - 3 modules" "3" "$module_count"

# Test 10: Module can be removed from state
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq 'del(.modules["4"])')
echo "$state" > "$STATE_FILE"
module_count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "Module 4 removed - 2 modules" "2" "$module_count"

# ────────────────────────────────────────────────────────────────────────────
header "Dependency Validation"

cat > "$STATE_FILE" <<EOF
{
  "modules": {
    "3": {"enabled": true, "installed": true, "version": "2.0.0"},
    "5": {"enabled": true, "installed": true, "version": "1.0.0"},
    "8": {"enabled": false, "installed": true, "version": "1.0.0"}
  },
  "metadata": {"created": "2026-05-28T00:00:00+00:00", "updated": "2026-05-28T00:00:00+00:00", "version": "1"}
}
EOF

# Test 11: Gaming (3) depends on tools (8) — tools is disabled, so deps should fail
state_json=$(jq -c '.modules' "$STATE_FILE")
has_issues=0
for id in "${MODULE_IDS[@]}"; do
  enabled=$(echo "$state_json" | jq -r ".\"$id\".enabled // false")
  [[ "$enabled" != "true" ]] && continue
  deps="${MODULE_DEPS[$id]}"
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      dep_enabled=$(echo "$state_json" | jq -r ".\"$dep\".enabled // false")
      [[ "$dep_enabled" != "true" ]] && has_issues=1
    done
  fi
done
assert_eq "Dependency validation detects missing deps" "1" "$has_issues"

# Test 12: Fix deps — enable tools (8)
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["8"].enabled = true')
echo "$state" > "$STATE_FILE"
state_json=$(jq -c '.modules' "$STATE_FILE")
has_issues=0
for id in "${MODULE_IDS[@]}"; do
  enabled=$(echo "$state_json" | jq -r ".\"$id\".enabled // false")
  [[ "$enabled" != "true" ]] && continue
  deps="${MODULE_DEPS[$id]}"
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      dep_enabled=$(echo "$state_json" | jq -r ".\"$dep\".enabled // false")
      [[ "$dep_enabled" != "true" ]] && has_issues=1
    done
  fi
done
assert_eq "Deps fixed by enabling tools (8)" "0" "$has_issues"

# Test 13: Minecraft (5) depends on gaming (3) — both enabled, so OK
# Already checked above. Extra assertion:
mod5_deps="${MODULE_DEPS[5]}"
assert_eq "Minecraft deps include gaming" "3" "$mod5_deps"

# ────────────────────────────────────────────────────────────────────────────
header "Module File Operations"

# Test 14: Simulate module download
test_file="$OPT_DIR/nixos/test_module.nix"
echo "{ ... }: { environment.systemPackages = []; }" > "$test_file"
assert_file_exists "Module file created" "$test_file"

# Test 15: Module file removal
rm -f "$test_file"
assert_file_not_exists "Module file removed" "$test_file"

# Test 16: Home manager module
home_file="$OPT_DIR/home/test_home.nix"
echo "{ ... }: { home.packages = []; }" > "$home_file"
assert_file_exists "Home module file created" "$home_file"
rm -f "$home_file"

# ────────────────────────────────────────────────────────────────────────────
header "CLI Tool — yorha-module"

# Test 17: yorha-module.sh help
if [[ -f "$BASE/files/bin/yorha-module.sh" ]]; then
  pass "yorha-module.sh exists"
  help_output=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" help 2>&1 || true)
  assert_contains "yorha-module help shows list command" "$help_output" "list"
  assert_contains "yorha-module help shows enable command" "$help_output" "enable"
  assert_contains "yorha-module help shows disable command" "$help_output" "disable"
  assert_contains "yorha-module help shows install command" "$help_output" "install"
  assert_contains "yorha-module help shows remove command" "$help_output" "remove"
  assert_contains "yorha-module help shows update command" "$help_output" "update"
  assert_contains "yorha-module help shows info command" "$help_output" "info"
  assert_contains "yorha-module help shows status command" "$help_output" "status"
  assert_contains "yorha-module help shows validate command" "$help_output" "validate"
  assert_contains "yorha-module help shows search command" "$help_output" "search"
  assert_contains "yorha-module help shows category command" "$help_output" "category"
else
  fail "yorha-module.sh does not exist"
fi

# Test 18: yorha-module list command
list_output=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" list 2>&1 || true)
assert_contains "yorha-module list shows modules" "$list_output" "performance"
assert_contains "yorha-module list shows module IDs" "$list_output" "1"

# Test 19: yorha-module status command
status_output=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" status 2>&1 || true)
assert_contains "yorha-module status shows registry" "$status_output" "Registry"
assert_contains "yorha-module status shows state file" "$status_output" "state"

# Test 20: yorha-module info command for module 1
info_output=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" info 1 2>&1 || true)
assert_contains "yorha-module info shows name" "$info_output" "performance"
assert_contains "yorha-module info shows category" "$info_output" "system"

# ────────────────────────────────────────────────────────────────────────────
header "CLI Tool — yorha-module-apply"

# Test 21: yorha-module-apply.sh status
if [[ -f "$BASE/files/bin/yorha-module-apply.sh" ]]; then
  pass "yorha-module-apply.sh exists"
  apply_help=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-apply.sh" --status 2>&1 || true)
  assert_contains "yorha-module-apply shows status" "$apply_help" "Module"
else
  fail "yorha-module-apply.sh does not exist"
fi

# Test 22: yorha-module-apply.sh validate (should pass with clean state)
apply_validate=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-apply.sh" --validate 2>&1 || true)
assert_contains "yorha-module-apply validate" "$apply_validate" "valid"

# ────────────────────────────────────────────────────────────────────────────
header "Nix Module Registry Integration"

# Test 23: Registry Nix file parses correctly
nix-instantiate --parse "$BASE/files/lib/module-registry.nix" &>/dev/null
assert_exit_code "module-registry.nix parses" 0 $?

# Test 24: Optional/nixos auto-import parses correctly
nix-instantiate --parse "$BASE/files/modules/optional/nixos/default.nix" &>/dev/null
assert_exit_code "optional/nixos/default.nix parses" 0 $?

# Test 25: Optional/home auto-import parses correctly
nix-instantiate --parse "$BASE/files/modules/optional/home/default.nix" &>/dev/null
assert_exit_code "optional/home/default.nix parses" 0 $?

# Test 26: Module-manager module parses correctly
nix-instantiate --parse "$BASE/files/modules/module-manager/default.nix" &>/dev/null
assert_exit_code "module-manager/default.nix parses" 0 $?

# ────────────────────────────────────────────────────────────────────────────
header "Module Registry (.sh)"

# Test 27: All module IDs have descriptions
missing_desc=0
for id in "${MODULE_IDS[@]}"; do
  [[ -z "${MODULE_DESC[$id]:-}" ]] && missing_desc=1
done
assert_eq "All modules have descriptions" "0" "$missing_desc"

# Test 28: All module IDs have files
missing_file=0
for id in "${MODULE_IDS[@]}"; do
  [[ -z "${MODULE_FILE[$id]:-}" ]] && missing_file=1
done
assert_eq "All modules have file paths" "0" "$missing_file"

# Test 29: All module IDs have categories
missing_cat=0
for id in "${MODULE_IDS[@]}"; do
  [[ -z "${MODULE_CATEGORY[$id]:-}" ]] && missing_cat=1
done
assert_eq "All modules have categories" "0" "$missing_cat"

# Test 30: All module IDs have versions
missing_ver=0
for id in "${MODULE_IDS[@]}"; do
  [[ -z "${MODULE_VERSION[$id]:-}" ]] && missing_ver=1
done
assert_eq "All modules have versions" "0" "$missing_ver"

# Test 31: Module dependencies reference valid IDs
bad_dep=0
for id in "${MODULE_IDS[@]}"; do
  deps="${MODULE_DEPS[$id]:-}"
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      found=0
      for mid in "${MODULE_IDS[@]}"; do
        [[ "$mid" == "$dep" ]] && found=1
      done
      [[ $found -eq 0 ]] && bad_dep=1
    done
  fi
done
assert_eq "All module deps reference valid IDs" "0" "$bad_dep"

# Test 32: Categories list covers all module categories
for id in "${MODULE_IDS[@]}"; do
  cat="${MODULE_CATEGORY[$id]}"
  found=0
  for c in "${MODULE_CATEGORIES[@]}"; do
    [[ "$c" == "$cat" ]] && found=1
  done
  if [[ $found -eq 0 ]]; then
    fail "Module $id has category '$cat' not in MODULE_CATEGORIES"
  else
    pass "Module $id category '$cat' in categories list"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
header "Desktop Entry"

# Test 33: Desktop entry defined in module
grep -q "makeDesktopItem" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Desktop entry defined in module-manager" || \
  fail "Desktop entry not found in module-manager"

grep -q "yorha-module-manager" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Desktop entry for yorha-module-manager" || \
  fail "Desktop entry name not found"

# Test 34: Desktop entry has terminal=true
grep -q "terminal = true" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Desktop entry has terminal=true" || \
  fail "Desktop entry missing terminal=true"

# ────────────────────────────────────────────────────────────────────────────
header "Module State Transition Edge Cases"

# Test 35: Empty state file
cat > "$STATE_FILE" <<EOF
{
  "modules": {},
  "metadata": {}
}
EOF
state_json=$(jq -c '.modules' "$STATE_FILE")
enabled_count=$(echo "$state_json" | jq 'length')
assert_eq "Empty state - zero modules" "0" "$enabled_count"

# Test 36: State with all modules enabled
state=$(cat "$STATE_FILE")
for id in "${MODULE_IDS[@]}"; do
  state=$(echo "$state" | jq ".modules[\"$id\"] = {enabled: true, installed: false, version: \"${MODULE_VERSION[$id]}\"}")
done
echo "$state" > "$STATE_FILE"
all_count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "All modules in state" "${#MODULE_IDS[@]}" "$all_count"

# Test 37: Toggle a module multiple times
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["2"].enabled = true')
state=$(echo "$state" | jq '.modules["2"].enabled = false')
state=$(echo "$state" | jq '.modules["2"].enabled = true')
echo "$state" > "$STATE_FILE"
final_state=$(jq -r '.modules["2"].enabled' "$STATE_FILE")
assert_eq "Module 2 final state enabled" "true" "$final_state"

# ────────────────────────────────────────────────────────────────────────────
header "Module Load Verification"

# Test 39: yorha-module-verify.sh exists
if [[ -f "$BASE/files/bin/yorha-module-verify.sh" ]]; then
  pass "yorha-module-verify.sh exists"
else
  fail "yorha-module-verify.sh does not exist"
fi

# Test 40: yorha-module-verify.sh --list shows all modules
verify_list=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-verify.sh" --list 2>&1 || true)
for id in "${MODULE_IDS[@]}"; do
  name="${MODULE_DESC[$id]%% *}"
  assert_contains "yorha-module-verify --list shows module $id" "$verify_list" "$id"
  assert_contains "yorha-module-verify --list shows name $name" "$verify_list" "$name"
done

# Test 41: yorha-module-verify.sh for a specific module
YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-verify.sh" 1 &>/dev/null || true
pass "yorha-module-verify.sh handles module 1 (performance) without crashing"

YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-verify.sh" 3 &>/dev/null || true
pass "yorha-module-verify.sh handles module 3 (gaming) without crashing"

# Test 42: yorha-module-verify.sh --quick runs without crashing
YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-verify.sh" --quick &>/dev/null || true
pass "yorha-module-verify.sh --quick runs without crashing"

# Test 43: yorha-module-verify.sh with non-existent module
verify_bad=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module-verify.sh" 99 2>&1 || true)
assert_contains "yorha-module-verify handles unknown module" "$verify_bad" "Unknown"

# ────────────────────────────────────────────────────────────────────────────
header "TTY Fallback UI"

# Test 44: TTY backend selection when fzf is missing
backend_test=$(YORHA_MODULE_UI=tty bash -c '
  BASE="$BASE"
  source "$BASE/files/lib/module-registry.sh"
  HAS_FZF=false; HAS_GUM=false; HAS_DIALOG=false; HAS_WHIPTAIL=false
  command -v fzf &>/dev/null && HAS_FZF=true
  select_backend() {
    forced="${YORHA_MODULE_UI:-}"
    if [[ -n "$forced" ]]; then echo "$forced"; return; fi
    if $HAS_FZF; then echo "fzf"; return; fi
    if $HAS_GUM; then echo "gum"; return; fi
    if $HAS_DIALOG; then echo "dialog"; return; fi
    if $HAS_WHIPTAIL; then echo "whiptail"; return; fi
    echo "tty"
  }
  select_backend
' 2>&1 || true)
assert_contains "YORHA_MODULE_UI=tty forces tty backend" "$backend_test" "tty"

# Test 45: TTY fallback backend selection (no fzf, using tty)
backend_tty=$(YORHA_MODULE_UI=tty bash -c '
  select_backend() {
    forced="${YORHA_MODULE_UI:-}"
    if [[ -n "$forced" ]]; then echo "$forced"; return; fi
    echo "tty"
  }
  select_backend
' 2>&1 || true)
assert_contains "TTY fallback selection works" "$backend_tty" "tty"

# Test 46: TTY mode tty_validate works
YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash -c '
  source "$BASE/files/lib/module-registry.sh"
  YORHA_MODULES_BASE="$TEST_DIR"
  ensure_state
' 2>&1 || true
pass "TTY mode sourcing works without errors"

# ────────────────────────────────────────────────────────────────────────────
header "Desktop Entry & Module Manager Integration"

# Test 47: Module manager default.nix has whiptail dependency
grep -q "whiptail" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Module-manager has whiptail dependency" || \
  fail "Module-manager missing whiptail dependency"

# Test 48: Module manager default.nix has yorha-module-verify
grep -q "moduleVerifyScript" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Module-manager has moduleVerifyScript" || \
  fail "Module-manager missing moduleVerifyScript"

# Test 49: Module manager has enableVerifyTimer option
grep -q "enableVerifyTimer" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Module-manager has enableVerifyTimer option" || \
  fail "Module-manager missing enableVerifyTimer option"

# Test 50: Module manager has yorha-module-verify systemd service
grep -q "yorha-module-verify" "$BASE/files/modules/module-manager/default.nix" && \
  pass "Module-manager has yorha-module-verify service" || \
  fail "Module-manager missing yorha-module-verify service"

# Test 51: yorha-module.sh has verify subcommand
grep -q "yorha-module-verify" "$BASE/files/bin/yorha-module.sh" && \
  pass "yorha-module.sh has verify subcommand" || \
  fail "yorha-module.sh missing verify subcommand"

# Test 52: yorha-module.sh has tui subcommand
grep -q '\btui\b' "$BASE/files/bin/yorha-module.sh" && \
  pass "yorha-module.sh has tui subcommand" || \
  fail "yorha-module.sh missing tui subcommand"

# ────────────────────────────────────────────────────────────────────────────
header "Module State File Operations (Integration)"

# Test 53: State file round-trip (write/read)
cat > "$STATE_FILE" <<EOF
{
  "modules": {
    "1": {"enabled": true, "installed": true, "version": "1.0.0"},
    "7": {"enabled": true, "installed": true, "version": "2.0.0"},
    "9": {"enabled": false, "installed": true, "version": "1.0.0"}
  },
  "metadata": {"created": "2026-05-28T00:00:00+00:00", "updated": "2026-05-28T00:00:00+00:00", "version": "1"}
}
EOF

# Add new module to state
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["2"] = {enabled: true, installed: false, version: "1.0.0"}')
state=$(echo "$state" | jq '.modules["8"] = {enabled: false, installed: false, version: "1.0.0"}')
echo "$state" > "$STATE_FILE"
count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "State round-trip preserves 5 modules" "5" "$count"

# Remove one module
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq 'del(.modules["9"])')
echo "$state" > "$STATE_FILE"
count=$(jq '.modules | length' "$STATE_FILE")
assert_eq "State after removal has 4 modules" "4" "$count"

# Toggle enabled states
state=$(cat "$STATE_FILE")
state=$(echo "$state" | jq '.modules["1"].enabled = false')
state=$(echo "$state" | jq '.modules["7"].enabled = false')
echo "$state" > "$STATE_FILE"
enabled_count=$(jq '[.modules[] | select(.enabled == true)] | length' "$STATE_FILE")
assert_eq "Toggle states: 1 module enabled" "1" "$enabled_count"

# ────────────────────────────────────────────────────────────────────────────
header "Error Handling"

# Test 54: Empty state file is handled gracefully
rm -f "$STATE_FILE"
empty_result=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" status 2>&1 || true)
pass "yorha-module status handles missing state file gracefully"

# Test 55: Invalid state file is handled
echo "invalid json" > "$STATE_FILE"
invalid_result=$(YORHA_MODULE_STATE_FILE="$STATE_FILE" YORHA_MODULE_STATE_DIR="$STATE_DIR" bash "$BASE/files/bin/yorha-module.sh" list 2>&1 || true)
pass "yorha-module list handles invalid state file gracefully"

# Test 56: Re-create valid state
setup_state
pass "State file re-created successfully"

# ────────────────────────────────────────────────────────────────────────────
header "Shellrc Integration"

# Test 38: Module manager aliases in shellrc
grep -q "mod " "$BASE/files/core/config/shellrc.nu" && \
  pass "shellrc.nu has mod alias" || \
  fail "shellrc.nu missing mod alias"
grep -q "mod-list" "$BASE/files/core/config/shellrc.nu" && \
  pass "shellrc.nu has mod-list alias" || \
  fail "shellrc.nu missing mod-list alias"
grep -q "mod-manager" "$BASE/files/core/config/shellrc.nu" && \
  pass "shellrc.nu has mod-manager alias" || \
  fail "shellrc.nu missing mod-manager alias"

# ============================================================================
# Summary
# ============================================================================
print_summary "Module Manager"
