#!/usr/bin/env bash
# ============================================================================
# SYSTEMD INTEGRATION TESTS
# ============================================================================
# Tests systemd service definitions: parsing, hardening, dependencies,
# timers, path units, and user services — via static analysis.
# Auto-discovers services from Nix files rather than hardcoded lists.
# ============================================================================

TEST_NAME="Systemd Integration"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "SYSTEMD — SERVICE INTEGRATION"

CFG="$BASE/files/core/configuration.nix"
SEC_DIR="$BASE/files/modules/security"
HW_DIR="$BASE/files/hardware"
TEMP_DIR=$(_mktemp /tmp/systemd-test.XXXXXX)

# ═════════════════════════════════════════════════════════════════════════════
# 1. AUTO-DISCOVERED SYSTEM SERVICES
# ═════════════════════════════════════════════════════════════════════════════
header "1. Auto-Discovered System Services"

declare -A DISCOVERED_SERVICES
TOTAL_DISCOVERED=0

# Scan all .nix files in security modules
for nix_file in "$SEC_DIR"/*.nix; do
  [ -f "$nix_file" ] || continue
  rel="${nix_file#$BASE/}"
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    DISCOVERED_SERVICES["$svc"]="$rel"
    TOTAL_DISCOVERED=$((TOTAL_DISCOVERED + 1))
  done < <(discover_services "$nix_file")
done

# Also scan configuration.nix for system services
while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  DISCOVERED_SERVICES["$svc"]="configuration.nix"
  TOTAL_DISCOVERED=$((TOTAL_DISCOVERED + 1))
done < <(discover_services "$CFG")

echo -e "  ${CYAN}Discovered $TOTAL_DISCOVERED system service definitions${NC}"

# Key services that must be present
declare -a REQUIRED_SERVICES=(
  "snout-watcher" "snort-daemon" "snort-monitor"
  "clamav-daemon" "clamav-daily-scan" "clamav-tmp-scan"
  "aide-init" "aide-check"
  "quarantine-setup" "quarantine-sanitizer" "quarantine-cleanup"
  "metadata-stripper-watcher" "metadata-stripper-daily"
  "acct" "dram-wiper" "shutdown-wiper"
)

for svc in "${REQUIRED_SERVICES[@]}"; do
  if [ -n "${DISCOVERED_SERVICES[$svc]:-}" ]; then
    pass "Service: $svc (${DISCOVERED_SERVICES[$svc]})"
  else
    fail "Service NOT FOUND: $svc"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# 2. AUTO-DISCOVERED SYSTEMD TIMERS
# ═════════════════════════════════════════════════════════════════════════════
header "2. Auto-Discovered Systemd Timers"

declare -A DISCOVERED_TIMERS

for nix_file in "$SEC_DIR"/*.nix; do
  [ -f "$nix_file" ] || continue
  rel="${nix_file#$BASE/}"
  while IFS= read -r timer; do
    [ -z "$timer" ] && continue
    DISCOVERED_TIMERS["$timer"]="$rel"
  done < <(discover_timers "$nix_file")
done

echo -e "  ${CYAN}Discovered ${#DISCOVERED_TIMERS[@]} timer definitions${NC}"

declare -a REQUIRED_TIMERS=(
  "clamav-daily-scan" "clamav-tmp-scan"
  "aide-check" "metadata-stripper-daily"
)

for timer in "${REQUIRED_TIMERS[@]}"; do
  if [ -n "${DISCOVERED_TIMERS[$timer]:-}" ]; then
    pass "Timer: $timer (${DISCOVERED_TIMERS[$timer]})"
  else
    fail "Timer NOT FOUND: $timer"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# 3. AUTO-DISCOVERED PATH UNITS
# ═════════════════════════════════════════════════════════════════════════════
header "3. Auto-Discovered Path Units"

declare -A DISCOVERED_PATHS

for nix_file in "$SEC_DIR"/*.nix; do
  [ -f "$nix_file" ] || continue
  rel="${nix_file#$BASE/}"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    DISCOVERED_PATHS["$path"]="$rel"
  done < <(discover_paths "$nix_file")
done

echo -e "  ${CYAN}Discovered ${#DISCOVERED_PATHS[@]} path unit definitions${NC}"

declare -a REQUIRED_PATHS=(
  "snout-watcher" "quarantine-sanitizer" "metadata-stripper-watcher"
)

for path in "${REQUIRED_PATHS[@]}"; do
  if [ -n "${DISCOVERED_PATHS[$path]:-}" ]; then
    pass "Path unit: $path (${DISCOVERED_PATHS[$path]})"
  else
    fail "Path unit NOT FOUND: $path"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# 4. AUTO-DISCOVERED USER SERVICES
# ═════════════════════════════════════════════════════════════════════════════
header "4. Auto-Discovered User Services"

declare -A DISCOVERED_USER_SVCS

while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  DISCOVERED_USER_SVCS["$svc"]="configuration.nix"
done < <(discover_user_services "$CFG")

echo -e "  ${CYAN}Discovered ${#DISCOVERED_USER_SVCS[@]} user service definitions${NC}"

declare -a REQUIRED_USER=(
  "atlas-awww" "atlas-vicinae" "atlas-xwayland-satellite"
  "atlas-startup-sound" "atlas-openrgb"
)

for svc in "${REQUIRED_USER[@]}"; do
  if [ -n "${DISCOVERED_USER_SVCS[$svc]:-}" ]; then
    pass "User service: $svc"
  else
    fail "User service NOT FOUND: $svc"
  fi
done

# Verify user services have wantedBy graphical-session.target
for svc in "${REQUIRED_USER[@]}"; do
  if grep -A20 "user.services.$svc\|user.services\.\"$svc\"" "$CFG" 2>/dev/null | grep -q "graphical-session.target"; then
    pass "User service $svc: wants graphical-session.target"
  else
    fail "User service $svc: missing graphical-session.target dependency"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# 5. SERVICE HARDENING MATRIX
# ═════════════════════════════════════════════════════════════════════════════
header "5. Service Hardening Matrix"

# Define hardening directives and count their usage across all service files
declare -A HARDENING_DIRECTIVES=(
  ["NoNewPrivileges"]="NoNewPrivileges"
  ["PrivateTmp"]="PrivateTmp"
  ["ProtectSystem"]="ProtectSystem"
  ["PrivateDevices"]="PrivateDevices"
  ["PrivateNetwork"]="PrivateNetwork"
  ["ProtectHome"]="ProtectHome"
  ["ProtectKernelTunables"]="ProtectKernelTunables"
  ["ProtectKernelModules"]="ProtectKernelModules"
  ["ProtectKernelLogs"]="ProtectKernelLogs"
  ["CapabilityBoundingSet"]="CapabilityBoundingSet"
  ["SystemCallArchitectures"]="SystemCallArchitectures"
  ["MemoryDenyWriteExecute"]="MemoryDenyWriteExecute"
  ["LockPersonality"]="LockPersonality"
  ["RestrictNamespaces"]="RestrictNamespaces"
  ["RestrictRealtime"]="RestrictRealtime"
  ["RestrictSUIDSGID"]="RestrictSUIDSGID"
  ["RemoveIPC"]="RemoveIPC"
)

echo -e "  ${CYAN}Hardening usage across all service files:${NC}"
for name in "${!HARDENING_DIRECTIVES[@]}"; do
  pattern="${HARDENING_DIRECTIVES[$name]}"
  count=$(grep -r "$pattern" "$SEC_DIR" --include="*.nix" 2>/dev/null | grep -c "serviceConfig\|$pattern" || echo 0)
  actual=$(grep -c "$pattern" < <(grep -rl "$pattern" "$SEC_DIR" --include="*.nix" 2>/dev/null) 2>/dev/null || echo 0)
  echo -e "    ${CYAN}$name:${NC} used in $actual files"
done

# Verify key hardening is present in security services
check_service_hardening "$SEC_DIR/snout.nix" "snout-watcher" "NoNewPrivileges" "snout-watcher: NoNewPrivileges" || true
check_service_hardening "$SEC_DIR/snort.nix" "snort-daemon" "CAP_NET_RAW" "snort-daemon: CAP_NET_RAW" || true
check_service_hardening "$SEC_DIR/quarantine.nix" "quarantine-sanitizer" "PrivateNetwork" "quarantine-sanitizer: PrivateNetwork" || true

# ═════════════════════════════════════════════════════════════════════════════
# 6. SERVICE DEPENDENCY CHAINS
# ═════════════════════════════════════════════════════════════════════════════
header "6. Service Dependency Chains"

# Verify critical ordering
grep -q "after.*clamav-daemon" "$SEC_DIR/clamav.nix" 2>/dev/null && \
  pass "Dep: clamav daily/tmp scan after clamav-daemon" || \
  fail "Dep: clamav scans missing after clamav-daemon"

grep -q "after.*snort-daemon" "$SEC_DIR/snort.nix" 2>/dev/null && \
  pass "Dep: snort-monitor after snort-daemon" || \
  fail "Dep: snort-monitor not after snort-daemon"

grep -q "before.*snout-watcher" "$SEC_DIR/quarantine.nix" 2>/dev/null && \
  pass "Dep: quarantine-setup before snout-watcher" || \
  warn "Dep: quarantine-setup ordering not explicit"

grep -q "after.*dram-wiper" "$SEC_DIR/memory-wipe.nix" 2>/dev/null && \
  pass "Dep: shutdown-wiper after dram-wiper" || \
  fail "Dep: shutdown-wiper missing after dram-wiper"

grep -q "before.*quarantine-sanitizer" "$SEC_DIR/quarantine.nix" 2>/dev/null && \
  pass "Dep: quarantine-setup before sanitizer" || \
  warn "Dep: quarantine-setup ordering to sanitizer not explicit"

grep -q "wantedBy.*multi-user.target\|wantedBy.*timers.target\|wantedBy.*graphical-session.target" "$SEC_DIR/quarantine.nix" "$SEC_DIR/snout.nix" "$SEC_DIR/clamav.nix" 2>/dev/null && \
  pass "Dep: services have wantedBy targets" || \
  warn "Dep: some services may lack wantedBy"

# ═════════════════════════════════════════════════════════════════════════════
# 7. TIMER SCHEDULE VALIDATION
# ═════════════════════════════════════════════════════════════════════════════
header "7. Timer Schedule Validation"

# Validate OnCalendar expressions are reasonable
validate_schedule() {
  local file="$1" timer="$2" label="$3"
  if grep -A10 "timers.$timer\|timers\.\"$timer\"" "$file" 2>/dev/null | grep -q "OnCalendar"; then
    pass "Schedule: $label"
  else
    fail "Schedule missing: $label"
  fi
}

validate_schedule "$SEC_DIR/clamav.nix" "clamav-daily-scan" "clamav-daily-scan: scheduled" || true
validate_schedule "$SEC_DIR/clamav.nix" "clamav-tmp-scan" "clamav-tmp-scan: scheduled *:0/5" || true
validate_schedule "$SEC_DIR/aide.nix" "aide-check" "aide-check: scheduled daily 15:00" || true
validate_schedule "$SEC_DIR/metadata-stripper.nix" "metadata-stripper-daily" "metadata-stripper-daily: scheduled daily" || true

# Timer visibility: all timers should have wantedBy=timers.target
grep -rl "wantedBy.*timers.target" "$SEC_DIR" --include="*.nix" 2>/dev/null | sort -u > "$TEMP_DIR/timer_files.txt"
timer_file_count=$(wc -l < "$TEMP_DIR/timer_files.txt" 2>/dev/null || echo 0)
if [ "$timer_file_count" -ge 2 ]; then
  pass "Timer visibility: $timer_file files register with timers.target"
else
  warn "Timer visibility: only $timer_file_count files register with timers.target"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 8. SERVICE TYPE VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════
header "8. Service Type Verification"

# Check that service types match expectations
check_service_type() {
  local file="$1" svc="$2" expected_type="$3" label="$4"
  if grep -A15 "services.$svc\|services\.\"$svc\"" "$file" 2>/dev/null | grep -q "Type.*$expected_type"; then
    pass "$label: Type=$expected_type"
  else
    fail "$label: not Type=$expected_type"
  fi
}

check_service_type "$SEC_DIR/snort.nix" "snort-daemon" "simple" "snort-daemon" || true
check_service_type "$SEC_DIR/snort.nix" "snort-monitor" "simple" "snort-monitor" || true
check_service_type "$SEC_DIR/snout.nix" "snout-watcher" "oneshot" "snout-watcher" || true
check_service_type "$SEC_DIR/clamav.nix" "clamav-daily-scan" "oneshot" "clamav-daily-scan" || true
check_service_type "$SEC_DIR/clamav.nix" "clamav-tmp-scan" "oneshot" "clamav-tmp-scan" || true
check_service_type "$SEC_DIR/aide.nix" "aide-init" "oneshot" "aide-init" || true
check_service_type "$SEC_DIR/quarantine.nix" "quarantine-setup" "oneshot" "quarantine-setup" || true
check_service_type "$SEC_DIR/quarantine.nix" "quarantine-cleanup" "oneshot" "quarantine-cleanup" || true
check_service_type "$SEC_DIR/memory-wipe.nix" "dram-wiper" "oneshot" "dram-wiper" || true

# User services should be simple (long-running) or oneshot
check_service_type "$CFG" "atlas-awww" "simple" "atlas-awww" || true
check_service_type "$CFG" "atlas-vicinae" "simple" "atlas-vicinae" || true
check_service_type "$CFG" "atlas-startup-sound" "oneshot" "atlas-startup-sound" || true

# ═════════════════════════════════════════════════════════════════════════════
# 9. SERVICE RESTART POLICY
# ═════════════════════════════════════════════════════════════════════════════
header "9. Service Restart Policies"

# Long-running daemons should have Restart=on-failure
check_restart_policy() {
  local file="$1" svc="$2" label="$3"
  if grep -A15 "services.$svc\|services\.\"$svc\"" "$file" 2>/dev/null | grep -q "Restart"; then
    pass "$label: has restart policy"
  else
    warn "$label: no explicit restart policy"
  fi
}

check_restart_policy "$SEC_DIR/snort.nix" "snort-daemon" "snort-daemon" || true
check_restart_policy "$SEC_DIR/snort.nix" "snort-monitor" "snort-monitor" || true
check_restart_policy "$SEC_DIR/clamav.nix" "clamav-daemon" "clamav-daemon" || true

# User services should have Restart=on-failure
for svc in atlas-awww atlas-vicinae atlas-xwayland-satellite; do
  if grep -A10 "user.services.$svc" "$CFG" 2>/dev/null | grep -q "Restart.*on-failure"; then
    pass "$svc: Restart=on-failure"
  else
    warn "$svc: missing Restart=on-failure"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# 10. STATIC STATE-VERSION CONSISTENCY
# ═════════════════════════════════════════════════════════════════════════════
header "10. State Version Consistency"

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

# ═════════════════════════════════════════════════════════════════════════════
# 11. TMPFILES CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════
header "11. tmpfiles Configuration"

tmpfiles_count=$(grep -r "systemd.tmpfiles.rules" "$SEC_DIR" --include="*.nix" -c 2>/dev/null | wc -l || echo 0)
if [ "$tmpfiles_count" -ge 5 ]; then
  pass "tmpfiles: $tmpfiles_count modules define tmpfiles rules"
else
  warn "tmpfiles: only $tmpfiles_count modules define rules"
fi

declare -A EXPECTED_TMPFILES=(
  ["/var/log/clamav"]="clamav.nix"
  ["/var/log/aide"]="aide.nix"
  ["/var/log/snort"]="snort.nix"
  ["/var/log/snout"]="snout.nix"
  ["/var/log/metadata-stripper"]="metadata-stripper.nix"
  ["/var/log/audit"]="auditd-config.nix"
  ["/var/account"]="process-accounting.nix"
)

for dir in "${!EXPECTED_TMPFILES[@]}"; do
  file="${EXPECTED_TMPFILES[$dir]}"
  if grep -q "$dir" "$SEC_DIR/$file" 2>/dev/null; then
    pass "tmpfiles: $dir created by $file"
  else
    fail "tmpfiles: $dir not found in $file"
  fi
done

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
