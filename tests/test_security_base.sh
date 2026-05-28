#!/usr/bin/env bash
# ============================================================================
# SECURITY BASE MODULE TESTS
# ============================================================================
# Tests kernel hardening (sysctl + boot params), firewall rules, network
# privacy, password policy, telemetry disabling, and security banner.
# All tests are static analysis — no root required.
# ============================================================================

TEST_NAME="Security Base Modules"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

SEC_DIR="$BASE/files/modules/security"
TEMP_DIR=$(_mktemp /tmp/sec-base-test.XXXXXX)

# =============================================================================
# 1. KERNEL SYSCTL HARDENING
# =============================================================================
header "1. KERNEL SYSCTL HARDENING"

SYSCTL="$SEC_DIR/kernel-sysctl.nix"

if [ -f "$SYSCTL" ]; then
  pass "kernel-sysctl.nix found"

  # ── Critical exploit mitigations ─────────────────────────────────────
  header "  1a. Exploit Mitigation"

  check_sysctl_value "$SYSCTL" "kernel.kptr_restrict" "2" "kptr_restrict=2" || true
  check_sysctl_value "$SYSCTL" "kernel.dmesg_restrict" "1" "dmesg_restrict=1" || true
  check_sysctl_value "$SYSCTL" "kernel.randomize_va_space" "2" "ASLR: randomize_va_space=2" || true
  check_sysctl_value "$SYSCTL" "kernel.unprivileged_bpf_disabled" "1" "eBPF: unprivileged_bpf_disabled=1" || true
  check_sysctl_value "$SYSCTL" "kernel.kexec_load_disabled" "1" "kexec: disabled" || true
  check_sysctl_value "$SYSCTL" "kernel.sysrq" "0" "SysRq: disabled" || true
  check_sysctl_value "$SYSCTL" "kernel.perf_event_paranoid" "2" "perf_event_paranoid=2" || true
  check_sysctl_value "$SYSCTL" "vm.mmap_rnd_bits" "32" "ASLR bits: 32" || true
  check_sysctl_value "$SYSCTL" "dev.tty.ldisc_autoload" "0" "TTY discipline: disabled" || true
  check_sysctl_value "$SYSCTL" "fs.suid_dumpable" "0" "SUID dumpable: disabled" || true

  # ── Network hardening ────────────────────────────────────────────────
  header "  1b. Network Security"

  check_sysctl_value "$SYSCTL" "net.ipv4.tcp_syncookies" "1" "SYN cookies: enabled" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.conf.all.accept_redirects" "0" "ICMP redirects: disabled" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.conf.all.send_redirects" "0" "Send redirects: disabled" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.icmp_echo_ignore_all" "1" "ICMP echo: ignored" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.conf.all.rp_filter" "1" "RP filter: enabled" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.conf.all.accept_source_route" "0" "Source routing: disabled" || true
  check_sysctl_value "$SYSCTL" "net.ipv6.conf.all.accept_ra" "0" "IPv6 RA: disabled" || true
  check_sysctl_value "$SYSCTL" "net.core.bpf_jit_harden" "2" "BPF JIT: hardened" || true

  # ── Filesystem protection ────────────────────────────────────────────
  header "  1c. Filesystem Protection"

  check_sysctl_value "$SYSCTL" "fs.protected_symlinks" "1" "Protected symlinks: enabled" || true
  check_sysctl_value "$SYSCTL" "fs.protected_hardlinks" "1" "Protected hardlinks: enabled" || true
  check_sysctl_value "$SYSCTL" "fs.protected_fifos" "2" "Protected FIFOs: enabled" || true
  check_sysctl_value "$SYSCTL" "fs.protected_regular" "2" "Protected regular: enabled" || true

  # ── Lynis recommendations ────────────────────────────────────────────
  header "  1d. Lynis Compliance"

  check_sysctl_value "$SYSCTL" "net.ipv4.icmp_ignore_bogus_error_responses" "1" "Bogus errors: ignored" || true
  check_sysctl_value "$SYSCTL" "kernel.core_uses_pid" "1" "Core dumps: include PID" || true
  check_sysctl_value "$SYSCTL" "kernel.yama.ptrace_scope" "1" "ptrace_scope: restricted" || true
  check_sysctl_value "$SYSCTL" "net.ipv4.conf.all.log_martians" "1" "Martian packets: logged" || true

  # ── Count total unique sysctls ───────────────────────────────────────
  sysctl_count=$(grep -cP '"\w+\.\w+' "$SYSCTL" 2>/dev/null || echo 0)
  if [ "$sysctl_count" -ge 40 ]; then
    pass "Total: $sysctl_count+ sysctl parameters configured"
  else
    warn "Only $sysctl_count sysctl parameters found (expected 40+)"
  fi
else
  skip "kernel-sysctl.nix not found"
fi

# =============================================================================
# 2. KERNEL BOOT PARAMETERS
# =============================================================================
header "2. KERNEL BOOT PARAMETERS"

KBOOT="$SEC_DIR/kernel-boot.nix"

if [ -f "$KBOOT" ]; then
  pass "kernel-boot.nix found"

  # ── Security boot params ─────────────────────────────────────────────
  header "  2a. Security Boot Parameters"

  check_boot_param "$KBOOT" "slab_nomerge" || true
  check_boot_param "$KBOOT" "init_on_alloc=1" || true
  check_boot_param "$KBOOT" "init_on_free=1" || true
  check_boot_param "$KBOOT" "page_poison=1" || true
  check_boot_param "$KBOOT" "page_alloc.shuffle=1" || true
  check_boot_param "$KBOOT" "pti=on" || true
  check_boot_param "$KBOOT" "randomize_kstack_offset=on" || true
  check_boot_param "$KBOOT" "debugfs=off" || true
  check_boot_param "$KBOOT" "audit_backlog_limit=16384" || true
  check_boot_param "$KBOOT" "loglevel=3" || true

  # ── Module blocking ──────────────────────────────────────────────────
  header "  2b. Kernel Module Blocking"

  check_blocked_module "$KBOOT" "firewire-core" || true
  check_blocked_module "$KBOOT" "firewire_core" || true
  check_blocked_module "$KBOOT" "firewire-ohci" || true
  check_blocked_module "$KBOOT" "thunderbolt" && pass "thunderbolt blocked (conditional)" || warn "thunderbolt blocking: conditional (check config)"

  # ── Blacklisted modules ──────────────────────────────────────────────
  header "  2c. Blacklisted Modules"

  for mod in dccp sctp rds tipc cramfs freevxfs jffs2 hfs hfsplus; do
    check_blocked_module "$KBOOT" "$mod" || true
  done

  # ── Module count validation ──────────────────────────────────────────
  blacklisted_count=$(grep -cP '"[a-z_-]+"' "$KBOOT" 2>/dev/null || echo 0)
  if [ "$blacklisted_count" -ge 20 ]; then
    pass "Total: $blacklisted_count+ modules blacklisted/blocked"
  else
    warn "Only $blacklisted_count modules blocked (expected 20+)"
  fi
else
  skip "kernel-boot.nix not found"
fi

# =============================================================================
# 3. FIREWALL CONFIGURATION
# =============================================================================
header "3. FIREWALL CONFIGURATION"

FIRE="$SEC_DIR/firewall.nix"

if [ -f "$FIRE" ]; then
  pass "firewall.nix found"

  check_nix_value "$FIRE" 'enable = true' "Firewall: enabled" || true
  check_nix_value "$FIRE" 'allowedTCPPorts' "Firewall: allowed TCP ports defined" || true
  check_nix_value "$FIRE" '22' "Firewall: SSH port 22 open" || true
  check_nix_value "$FIRE" '80' "Firewall: HTTP port 80 open" || true
  check_nix_value "$FIRE" '443' "Firewall: HTTPS port 443 open" || true
  check_nix_value "$FIRE" 'allowedUDPPortRanges' "Firewall: UDP port ranges defined" || true
  check_nix_value "$FIRE" '4000' "Firewall: UDP 4000 included" || true
  check_nix_value "$FIRE" '8000' "Firewall: UDP 8000 included" || true
  check_nix_value "$FIRE" 'virbr0' "Firewall: trusted interface virbr0" || true
  check_nix_value "$FIRE" 'checkReversePath.*strict' "Firewall: strict reverse path filtering" || false
  check_nix_value "$FIRE" 'logRefusedConnections = true' "Firewall: log refused connections" || true

  # Default deny mode
  if grep -q "DENY\|deny" "$FIRE" 2>/dev/null; then
    pass "Firewall: default deny mode documented"
  else
    warn "Firewall: default deny not explicit in comments"
  fi
else
  skip "firewall.nix not found"
fi

# =============================================================================
# 4. NETWORK PRIVACY
# =============================================================================
header "4. NETWORK PRIVACY"

NETPRIV="$SEC_DIR/network-privacy.nix"

if [ -f "$NETPRIV" ]; then
  pass "network-privacy.nix found"

  check_nix_value "$NETPRIV" 'macAddress.*random' "WiFi MAC: randomized" || true
else
  skip "network-privacy.nix not found"
fi

# =============================================================================
# 5. PASSWORD POLICY
# =============================================================================
header "5. PASSWORD POLICY"

PASSWD="$SEC_DIR/password-policy.nix"

if [ -f "$PASSWD" ]; then
  pass "password-policy.nix found"

  check_nix_value "$PASSWD" 'FAIL_DELAY.*3' "FAIL_DELAY = 3" || true
  check_nix_value "$PASSWD" 'LOGIN_RETRIES.*3' "LOGIN_RETRIES = 3" || true
  check_nix_value "$PASSWD" 'LOGIN_TIMEOUT.*30' "LOGIN_TIMEOUT = 30" || true
  check_nix_value "$PASSWD" 'PASS_MAX_DAYS.*90' "PASS_MAX_DAYS = 90" || true
  check_nix_value "$PASSWD" 'PASS_MIN_DAYS.*7' "PASS_MIN_DAYS = 7" || true
  check_nix_value "$PASSWD" 'PASS_WARN_AGE.*7' "PASS_WARN_AGE = 7" || true
  check_nix_value "$PASSWD" 'PASS_MIN_LEN.*12' "PASS_MIN_LEN = 12" || true
  check_nix_value "$PASSWD" 'ENCRYPT_METHOD.*YESCRYPT' "YESCRYPT: password hashing" || true
  check_nix_value "$PASSWD" 'YESCRYPT_COST_FACTOR.*10' "YESCRYPT cost: 10" || true
  check_nix_value "$PASSWD" 'SHA_CRYPT_MIN_ROUNDS.*10000' "SHA crypt rounds: 10000" || true
  check_nix_value "$PASSWD" 'enableGnomeKeyring.*false' "GNOME keyring: disabled" || true
else
  skip "password-policy.nix not found"
fi

# =============================================================================
# 6. TELEMETRY DISABLING
# =============================================================================
header "6. TELEMETRY DISABLING"

TELE="$SEC_DIR/telemetry.nix"

if [ -f "$TELE" ]; then
  pass "telemetry.nix found"

  check_nix_value "$TELE" 'avahi.enable = false' "Avahi: disabled" || true
  check_nix_value "$TELE" 'geoclue2.enable = false' "Geoclue2: disabled" || true
  check_nix_value "$TELE" 'accounts-daemon.enable' "accounts-daemon: disabled" || true
  check_nix_value "$TELE" 'storage = "volatile"' "Journal: volatile storage" || true
  check_nix_value "$TELE" 'upload.enable = false' "Journal: upload disabled" || true
  check_nix_value "$TELE" 'RuntimeMaxUse=500M' "Journal: max 500M runtime" || true
  check_nix_value "$TELE" 'networking.modemmanager.enable = false' "ModemManager: disabled" || true
  check_nix_value "$TELE" 'system.autoUpgrade.enable = false' "Auto-upgrade: disabled" || true
else
  skip "telemetry.nix not found"
fi

# =============================================================================
# 7. SECURITY BANNER
# =============================================================================
header "7. SECURITY BANNER"

BANNER="$SEC_DIR/banner.nix"

if [ -f "$BANNER" ]; then
  pass "banner.nix found"

  check_nix_value "$BANNER" 'Authorized Access Only' "Banner: authorized access warning" || true
  check_nix_value "$BANNER" 'WARNING' "Banner: WARNING prefix" || true
  check_nix_value "$BANNER" 'All activities.*monitored' "Banner: monitoring notice" || true

  banner_len=$(wc -c < "$BANNER" 2>/dev/null || echo 0)
  if [ "$banner_len" -gt 200 ]; then
    pass "Banner: substantial content ($banner_len bytes)"
  else
    fail "Banner: too short ($banner_len bytes)"
  fi
else
  skip "banner.nix not found"
fi

# =============================================================================
# 8. CROSS-REFERENCE: Module imports
# =============================================================================
header "8. MODULE IMPORT CONSISTENCY"

SEC_DEFAULT="$SEC_DIR/default.nix"

if [ -f "$SEC_DEFAULT" ]; then
  for mod in kernel-sysctl kernel-boot firewall banner service-hardening telemetry password-policy network-privacy; do
    grep -q "$mod" "$SEC_DEFAULT" && pass "default.nix imports: $mod" || fail "default.nix MISSING import: $mod"
  done
else
  skip "security/default.nix not found"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
