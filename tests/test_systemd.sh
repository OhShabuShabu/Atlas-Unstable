#!/usr/bin/env bash
# ============================================================================
# SYSTEMD INTEGRATION TESTS
# ============================================================================
# Tests systemd service definitions: parsing, hardening, dependencies,
# timers, path units, and user services — all via static analysis.
# ============================================================================

TEST_NAME="Systemd Integration"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "SYSTEMD — SERVICE INTEGRATION"

# ─── 1. Custom System Services ─────────────────────────────────────────────
header "1. Custom System Services"

declare -a SYSTEM_SERVICES=(
  "snout-watcher.path|snout.nix"
  "snout-watcher.service|snout.nix"
  "snort-daemon|snort.nix"
  "snort-monitor|snort.nix"
  "clamav-daemon|clamav.nix"
  "clamav-daily-scan|clamav.nix"
  "clamav-tmp-scan|clamav.nix"
  "aide-init|aide.nix"
  "aide-check|aide.nix"
  "quarantine-setup|quarantine.nix"
  "quarantine-sanitizer|quarantine.nix"
  "quarantine-cleanup|quarantine.nix"
  "metadata-stripper-watcher|metadata-stripper.nix"
  "metadata-stripper-daily|metadata-stripper.nix"
  "acct|process-accounting.nix"
  "dram-wiper|memory-wipe.nix"
  "shutdown-wiper|memory-wipe.nix"
  "luks-keyfile-enroll|luks-keyfile.nix"
)

for entry in "${SYSTEM_SERVICES[@]}"; do
  svc="${entry%%|*}"
  file="${entry##*|}"
  if grep -q "services\.$svc\|services\.\"$svc\"" "$BASE/files/modules/security/$file" 2>/dev/null; then
    pass "Service: $svc (defined in $file)"
  else
    # Check without .service suffix for path units
    if echo "$svc" | grep -q "\.path$"; then
      svc_name="${svc%.path}"
      if grep -q "paths\.$svc_name\|paths\.\"$svc_name\"" "$BASE/files/modules/security/$file" 2>/dev/null; then
        pass "Path unit: $svc (defined in $file)"
      else
        fail "Service NOT FOUND: $svc in $file"
      fi
    elif echo "$svc" | grep -q "\.service$"; then
      svc_name="${svc%.service}"
      if grep -q "services\.$svc_name\|services\.\"$svc_name\"" "$BASE/files/modules/security/$file" 2>/dev/null; then
        pass "Service: $svc (defined in $file)"
      else
        fail "Service NOT FOUND: $svc in $file"
      fi
    else
      fail "Service NOT FOUND: $svc in $file"
    fi
  fi
done

# ─── 2. Systemd Timers ─────────────────────────────────────────────────────
header "2. Systemd Timers"

declare -a TIMERS=(
  "clamav-daily-scan|clamav.nix"
  "clamav-tmp-scan|clamav.nix"
  "aide-check|aide.nix"
  "metadata-stripper-daily|metadata-stripper.nix"
)

for entry in "${TIMERS[@]}"; do
  timer="${entry%%|*}"
  file="${entry##*|}"
  if grep -q "timers\.$timer\|timers\.\"$timer\"" "$BASE/files/modules/security/$file" 2>/dev/null; then
    pass "Timer: $timer (defined in $file)"
  else
    fail "Timer NOT FOUND: $timer in $file"
  fi
done

# ─── 3. Systemd Path Units ─────────────────────────────────────────────────
header "3. Systemd Path Units"

declare -a PATH_UNITS=(
  "snout-watcher|snout.nix"
  "quarantine-sanitizer|quarantine.nix"
  "metadata-stripper-watcher|metadata-stripper.nix"
)

for entry in "${PATH_UNITS[@]}"; do
  unit="${entry%%|*}"
  file="${entry##*|}"
  if grep -q "paths\.$unit\|paths\.\"$unit\"" "$BASE/files/modules/security/$file" 2>/dev/null; then
    pass "Path unit: $unit (defined in $file)"
  else
    fail "Path unit NOT FOUND: $unit in $file"
  fi
done

# ─── 4. User Services ─────────────────────────────────────────────────────
header "4. User Services"

declare -a USER_SERVICES=(
  "atlas-awww"
  "atlas-vicinae"
  "atlas-xwayland-satellite"
  "atlas-startup-sound"
  "atlas-openrgb"
)

CFG="$BASE/files/core/configuration.nix"

for svc in "${USER_SERVICES[@]}"; do
  if grep -q "user.services.$svc\|user.services\.\"$svc\"" "$CFG" 2>/dev/null; then
    pass "User service: $svc"
  else
    fail "User service NOT FOUND: $svc"
  fi
done

# ─── 5. Service Hardening Consistency ─────────────────────────────────────
header "5. Service Hardening Consistency"

declare -A HARDENING_DIRECTIVES=(
  ["NoNewPrivileges"]="NoNewPrivileges"
  ["ProtectSystem"]="ProtectSystem.*=.*\"full\""
  ["PrivateTmp"]="PrivateTmp"
  ["PrivateDevices"]="PrivateDevices"
  ["ProtectKernelTunables"]="ProtectKernelTunables"
  ["RestrictNamespaces"]="RestrictNamespaces"
  ["RestrictRealtime"]="RestrictRealtime"
  ["RestrictSUIDSGID"]="RestrictSUIDSGID"
  ["RemoveIPC"]="RemoveIPC"
)

for name in "${!HARDENING_DIRECTIVES[@]}"; do
  pattern="${HARDENING_DIRECTIVES[$name]}"
  count=$(grep -r "$pattern" "$BASE/files/modules/security/" --include="*.nix" 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    pass "Hardening: $name used in $count services"
  else
    fail "Hardening: $name NOT USED in any service"
  fi
done

# ─── 6. Service Dependency Chains ──────────────────────────────────────────
header "6. Service Dependency Chains"

# Verify key dependency chains
if grep -q "after.*clamav-daemon" "$BASE/files/modules/security/clamav.nix" 2>/dev/null; then
  pass "Dep: clamav-daily-scan after clamav-daemon"
else
  fail "Dep: clamav-daily-scan missing dependency on clamav-daemon"
fi

if grep -q "after.*snort-daemon" "$BASE/files/modules/security/snort.nix" 2>/dev/null; then
  pass "Dep: snort-monitor after snort-daemon"
else
  fail "Dep: snort-monitor missing dependency on snort-daemon"
fi

if grep -q "before.*snout-watcher" "$BASE/files/modules/security/quarantine.nix" 2>/dev/null; then
  pass "Dep: quarantine-setup before snout-watcher"
fi

if grep -q "after.*dram-wiper" "$BASE/files/modules/security/memory-wipe.nix" 2>/dev/null; then
  pass "Dep: shutdown-wiper after dram-wiper"
fi

# ─── 7. Timer Schedule Validation ──────────────────────────────────────────
header "7. Timer Schedule Validation"

# Verify all timer schedules are valid OnCalendar expressions
declare -A TIMER_SCHEDULES=(
  ["clamav-daily-scan"]="03:00:00"
  ["clamav-tmp-scan"]="*:0/5"
  ["aide-check"]="15:00:00"
  ["metadata-stripper-daily"]="daily"
)

for timer in "${!TIMER_SCHEDULES[@]}"; do
  expected="${TIMER_SCHEDULES[$timer]}"
  if grep -q "$expected" "$BASE/files/modules/security/"*.nix 2>/dev/null; then
    pass "Schedule: $timer → $expected"
  else
    fail "Schedule NOT FOUND: $timer → $expected"
  fi
done

# ─── 8. State Version Consistency ─────────────────────────────────────────
header "8. State Version Consistency"

CFG="$BASE/files/core/configuration.nix"
HM="$BASE/files/core/home.nix"

sys_ver=$(grep -oP 'stateVersion\s*=\s*"\K[^"]+' "$CFG" 2>/dev/null || echo "unknown")
hm_ver=$(grep -oP 'stateVersion\s*=\s*"\K[^"]+' "$HM" 2>/dev/null || echo "unknown")

assert_eq "system.stateVersion = 25.11" "25.11" "$sys_ver" || true
assert_eq "home.stateVersion = 25.11" "25.11" "$hm_ver" || true

if [ "$sys_ver" = "$hm_ver" ]; then
  pass "State versions match (both $sys_ver)"
else
  fail "State version MISMATCH: system=$sys_ver home=$hm_ver"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
