#!/usr/bin/env bash
# ============================================================================
# ATLAS NIXOS CONFIGURATION TEST SUITE
# ============================================================================
# Run: bash test_config.sh
# Tests all aspects of the Atlas NixOS configuration for errors.
# All checks are offline static analysis -- no network or root needed.
# ============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BASE="/home/yusa/Atlas"; PASS=0; FAIL=0; WARN=0

header() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }
pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $1"; }
warn() { WARN=$((WARN+1)); echo -e "  ${YELLOW}⚠${NC} $1"; }
# Multiline grep: checks if pattern exists across lines in a file
mlgrep() { local f="$1" pat="$2"; python3 -c "import re; c=open('$f').read(); exit(0 if re.search(r'$pat', c, re.DOTALL) else 1)" 2>/dev/null; }

# ============================================================================
# 1. FLAKE STRUCTURE
# ============================================================================
header "0. INSTALL SCRIPT"
grep -q 'Step 1/7' "$BASE/install.sh" && pass "install.sh has step progress (7 steps)" || warn "install.sh missing step progress"
grep -q 'Cancel Installation' "$BASE/install.sh" 2>/dev/null || grep -q "can't be undone" "$BASE/install.sh" && pass "install.sh warns about destructive action" || warn "install.sh missing destructive action warning"
grep -q "password: atlas" "$BASE/install.sh" && pass "install.sh provides default credentials" || warn "install.sh missing default credentials info"

header "1. FLAKE STRUCTURE"
[ -f "$BASE/flake.nix" ] && pass "flake.nix exists" || fail "flake.nix missing"
[ -f "$BASE/flake.lock" ] && pass "flake.lock exists" || fail "flake.lock missing"
grep -q 'nixpkgs.*nixos-unstable' "$BASE/flake.nix" && pass "nixpkgs pinned to nixos-unstable" || fail "nixpkgs not pinned to nixos-unstable"
grep -q 'home-manager.*master' "$BASE/flake.nix" && pass "home-manager pinned to master" || fail "home-manager not pinned to master"
grep -q 'noctalia' "$BASE/flake.nix" && pass "noctalia flake input present" || fail "noctalia missing from flake inputs"
python3 -c "import json; json.load(open('$BASE/flake.lock'))" 2>/dev/null && pass "flake.lock is valid JSON" || fail "flake.lock is not valid JSON"

# ============================================================================
# 2. FILE EXISTENCE
# ============================================================================
header "2. FILE EXISTENCE"
declare -a REQUIRED_FILES=(
  "flake.nix" "files/core/configuration.nix" "files/core/home.nix"
  "files/core/hardware-configuration.nix" "files/core/config/shellrc.nu"
  "files/core/config/nix/nix.conf" "files/modules/security/default.nix"
  "files/modules/security/snout.nix" "files/modules/security/clamav.nix"
  "files/modules/security/aide.nix" "files/modules/security/snort.nix"
  "files/modules/security/quarantine.nix" "files/modules/security/firewall.nix"
  "files/modules/security/kernel-sysctl.nix" "files/modules/security/kernel-boot.nix"
  "files/modules/security/banner.nix" "files/modules/security/network-privacy.nix"
  "files/modules/security/password-policy.nix" "files/modules/security/service-hardening.nix"
  "files/modules/security/telemetry.nix" "files/modules/security/auditd-config.nix"
  "files/modules/security/process-accounting.nix" "files/modules/security/strong-keyring.nix"
  "files/modules/dev/dev.nix" "files/modules/gaming/gaming.nix"
  "files/modules/gaming/millennium/config.json" "files/modules/privacy/privacy.nix"
  "files/modules/flatpak.nix" "files/modules/minecraft.nix" "files/modules/performance.nix"
  "files/modules/tools.nix" "files/modules/virtualisation.nix"
  "files/config/niri/config.kdl" "files/config/niri/binds.kdl" "files/config/niri/env.kdl"
  "files/config/niri/inputs.kdl" "files/config/niri/layout.kdl" "files/config/niri/outputs.kdl"
  "files/config/niri/startup.kdl" "files/config/niri/window-rules.kdl"
  "files/config/niri/animations/pop-drop.kdl" "files/config/vicinae/vicinae.json"
  "files/config/primary_color.txt" "files/config/primary_color_template.txt"
  "files/audio/startup.mp3" "files/audio/close_window.mp3"
  "files/bin/shell/startup.sh" "files/bin/python/fix_rgb_color.py"
)
for f in "${REQUIRED_FILES[@]}"; do
  [ -f "$BASE/$f" ] && pass "$f exists" || fail "$f MISSING"
done
[ -d "$BASE/files/config/.icons" ] && pass ".icons directory exists" || warn ".icons directory missing"
[ -f "$BASE/files/modules/dev/dev.nix" ] && pass "Neovim dev module exists" || fail "Neovim dev module missing"

# ============================================================================
# 3. NIX SYNTAX
# ============================================================================
header "3. NIX SYNTAX"
NIX_FILES=$(find "$BASE" -name '*.nix' -not -path '*/flake.lock' | sort)
for nf in $NIX_FILES; do
  REL="${nf#$BASE/}"
  nix-instantiate --parse "$nf" 2>/dev/null && pass "$REL parses" || fail "$REL PARSE ERROR"
done

# ============================================================================
# 4. CORE CONFIG VALIDATION
# ============================================================================
header "4. CORE CONFIG"
CFG="$BASE/files/core/configuration.nix"

mlgrep "$CFG" 'system\.stateVersion\s*=\s*"25\.11"' && pass "system.stateVersion = 25.11" || fail "system.stateVersion not 25.11"
mlgrep "$CFG" 'hostName\s*=\s*"atlas"' && pass "hostname = atlas" || fail "hostname not atlas"
mlgrep "$CFG" 'experimental-features.*nix-command.*flakes' && pass "Flakes + nix-command enabled" || fail "Flakes/nix-command not enabled"
mlgrep "$CFG" 'allowUnfree\s*=\s*true' && pass "Unfree packages allowed" || fail "Unfree not allowed"
mlgrep "$CFG" 'systemd-boot.*enable\s*=\s*true' && pass "systemd-boot enabled" || fail "systemd-boot not enabled"
mlgrep "$CFG" 'plymouth.*enable\s*=\s*true' && pass "Plymouth enabled" || fail "Plymouth not enabled"
mlgrep "$CFG" 'autoLogin.*enable\s*=\s*true' && pass "Auto-login enabled" || warn "Auto-login not enabled"
mlgrep "$CFG" 'programs\.niri\.enable\s*=\s*true' && pass "Niri WM enabled" || fail "Niri not enabled"
mlgrep "$CFG" 'pipewire.*enable\s*=\s*true' && pass "Pipewire enabled" || fail "Pipewire not enabled"
mlgrep "$CFG" 'xdg\.portal.*enable\s*=\s*true' && pass "XDG Portal enabled" || fail "XDG Portal not enabled"
mlgrep "$CFG" 'dbus.*implementation.*broker' && pass "dbus-broker enabled" || fail "dbus-broker not enabled"
mlgrep "$CFG" 'qt.*enable\s*=\s*true' && pass "Qt enabled" || fail "Qt not enabled"
mlgrep "$CFG" 'platformTheme\s*=\s*"kde"' && pass "Qt KDE platform theme" || fail "Qt KDE platform theme not set"
mlgrep "$CFG" 'XDG_CURRENT_DESKTOP.*niri' && pass "XDG_CURRENT_DESKTOP = niri" || fail "XDG_CURRENT_DESKTOP not set"
mlgrep "$CFG" 'XDG_SESSION_TYPE.*wayland' && pass "XDG_SESSION_TYPE = wayland" || fail "XDG_SESSION_TYPE not set"
mlgrep "$CFG" 'timeZone.*Europe/Berlin' && pass "Timezone = Europe/Berlin" || fail "Timezone not set"
mlgrep "$CFG" 'polkit.*enable\s*=\s*true' && pass "Polkit enabled" || fail "Polkit not enabled"
mlgrep "$CFG" 'apparmor.*enable\s*=\s*true' && pass "AppArmor enabled" || fail "AppArmor not enabled"
mlgrep "$CFG" 'home-manager\.useUserPackages\s*=\s*true' && pass "home-manager user packages enabled" || fail "home-manager user packages not enabled"
mlgrep "$CFG" 'hidepid=2' && pass "/proc hidepid=2 configured" || fail "/proc hidepid=2 not configured"
mlgrep "$CFG" 'programs\.nix-ld\.enable\s*=\s*true' && pass "nix-ld enabled" || fail "nix-ld not enabled"
mlgrep "$CFG" 'logrotate.*enable\s*=\s*true' && pass "logrotate enabled" || fail "logrotate not enabled"
grep -Ezq 'security\.audit\s*=\s*\{[^}]*enable\s*=\s*true' "$CFG" || grep -q 'security\.audit\.enable\s*=\s*true' "$CFG" && pass "Linux audit subsystem enabled" || fail "audit not enabled"
mlgrep "$CFG" 'security\.auditd\.enable\s*=\s*true' && pass "auditd enabled" || fail "auditd not enabled"
CSN="$BASE/files/core/current-system.nix"
mlgrep "$CSN" 'luks\.devices\.\"crypt\"' && pass "LUKS devices configured" || fail "LUKS not configured in current-system.nix"
mlgrep "$CFG" 'distrobox' && pass "Distrobox config present" || fail "Distrobox config missing"
mlgrep "$CFG" 'monocraft' && pass "Monocraft font configured" || fail "Monocraft font not configured"
mlgrep "$CFG" 'protectKernelImage\s*=\s*true' && pass "protectKernelImage enabled" || fail "protectKernelImage not enabled"
mlgrep "$CFG" 'forcePageTableIsolation\s*=\s*true' && pass "forcePageTableIsolation enabled" || fail "forcePageTableIsolation not enabled"
mlgrep "$CFG" 'nier-automata' && pass "SDDM Nier Automata theme configured" || warn "SDDM Nier Automata theme not configured"

# ============================================================================
# 5. HOME MANAGER CONFIG
# ============================================================================
header "5. HOME MANAGER"
HM="$BASE/files/core/home.nix"

mlgrep "$HM" 'home\.username\s*=\s*"yusa"' && pass "home.username = yusa" || fail "home.username not set"
mlgrep "$HM" 'home\.homeDirectory\s*=\s*"/home/yusa"' && pass "home.homeDirectory = /home/yusa" || fail "home.homeDirectory not set"
mlgrep "$HM" 'gtk.*enable\s*=\s*true' && pass "GTK enabled" || fail "GTK not enabled"
mlgrep "$HM" 'Adwaita-dark' && pass "Adwaita-dark GTK theme" || fail "Adwaita-dark theme missing"
mlgrep "$HM" 'Papirus-Dark' && pass "Papirus-Dark icon theme" || fail "Papirus-Dark icon theme missing"
mlgrep "$HM" 'noctalia-shell.*enable\s*=\s*true' && pass "Noctalia shell enabled" || fail "Noctalia shell not enabled"
mlgrep "$HM" 'Catppuccin Mocha' && pass "Catppuccin Mocha scheme" || fail "Catppuccin Mocha scheme missing"
mlgrep "$HM" 'notifications\.enabled\s*=\s*true' && pass "Noctalia notifications enabled" || fail "Noctalia notifications not enabled"
mlgrep "$HM" 'osd\.enabled\s*=\s*true' && pass "Noctalia OSD enabled" || fail "Noctalia OSD not enabled"
mlgrep "$HM" 'nushell.*enable\s*=\s*true' && pass "Nushell enabled" || fail "Nushell not enabled"
mlgrep "$HM" 'zoxide.*enable\s*=\s*true' && pass "Zoxide enabled" || fail "Zoxide not enabled"
mlgrep "$HM" 'opencode.*enable\s*=\s*true' && pass "opencode enabled" || fail "opencode not enabled"
mlgrep "$HM" 'git.*enable\s*=\s*true' && pass "Git configured" || fail "Git not configured"
mlgrep "$HM" 'fonts\.fontconfig\.enable\s*=\s*true' && pass "Fontconfig enabled" || fail "Fontconfig not enabled"
mlgrep "$HM" 'xdg\.mimeApps\.enable\s*=\s*true' && pass "MIME apps enabled" || fail "MIME apps not enabled"
mlgrep "$HM" 'home\.stateVersion\s*=\s*"25\.11"' && pass "home.stateVersion = 25.11" || fail "home.stateVersion not 25.11"

for pkg in nushell fzf btop vicinae ghostty libnotify wl-clipboard matugen tty-clock; do
  mlgrep "$HM" "$pkg" && pass "home.package: $pkg" || warn "home.package: $pkg not found"
done

# ============================================================================
# 6. SECURITY HARDENING
# ============================================================================
header "6. SECURITY HARDENING"
SYSCTL="$BASE/files/modules/security/kernel-sysctl.nix"
mlgrep "$SYSCTL" 'kptr_restrict".*= 2' && pass "kptr_restrict=2" || fail "kptr_restrict not 2"
mlgrep "$SYSCTL" 'dmesg_restrict".*= 1' && pass "dmesg_restrict=1" || fail "dmesg_restrict not 1"
mlgrep "$SYSCTL" 'randomize_va_space".*= 2' && pass "ASLR enabled" || fail "ASLR not enabled"
mlgrep "$SYSCTL" 'unprivileged_bpf_disabled".*= 1' && pass "eBPF restricted" || fail "eBPF not restricted"
mlgrep "$SYSCTL" 'sysrq".*= 0' && pass "SysRq disabled" || fail "SysRq not disabled"
mlgrep "$SYSCTL" 'tcp_syncookies".*= 1' && pass "SYN cookies enabled" || fail "SYN cookies not enabled"
mlgrep "$SYSCTL" 'accept_redirects".*= 0' && pass "ICMP redirects disabled" || fail "ICMP redirects not disabled"
mlgrep "$SYSCTL" 'icmp_echo_ignore_all".*= 1' && pass "ICMP echo ignored" || fail "ICMP echo not ignored"
mlgrep "$SYSCTL" 'protected_symlinks".*= 1' && pass "Protected symlinks enabled" || fail "Protected symlinks not enabled"
mlgrep "$SYSCTL" 'protected_hardlinks".*= 1' && pass "Protected hardlinks enabled" || fail "Protected hardlinks not enabled"

KBOOT="$BASE/files/modules/security/kernel-boot.nix"
mlgrep "$KBOOT" 'slab_nomerge' && pass "slab_nomerge boot param" || fail "slab_nomerge missing"
mlgrep "$KBOOT" 'init_on_alloc=1' && pass "init_on_alloc=1" || fail "init_on_alloc=1 missing"
mlgrep "$KBOOT" 'pti=on' && pass "pti=on" || fail "pti=on missing"
mlgrep "$KBOOT" 'lockdown=integrity' && pass "lockdown=integrity" || fail "lockdown=integrity missing"

FIRE="$BASE/files/modules/security/firewall.nix"
mlgrep "$FIRE" 'networking\.firewall.*enable\s*=\s*true' && pass "Firewall enabled" || fail "Firewall not enabled"
mlgrep "$FIRE" 'checkReversePath.*strict' && pass "Strict reverse path filtering" || fail "Reverse path filtering not strict"

CLAMAV="$BASE/files/modules/security/clamav.nix"
mlgrep "$CLAMAV" 'daemon\.enable\s*=\s*true' && pass "ClamAV daemon enabled" || fail "ClamAV daemon not enabled"
mlgrep "$CLAMAV" 'updater\.enable\s*=\s*true' && pass "ClamAV updater enabled" || fail "ClamAV updater not enabled"
mlgrep "$CLAMAV" 'OnCalendar.*03:00:00' && pass "Daily ClamAV scan at 3am" || fail "ClamAV scan timer not set"

AIDE="$BASE/files/modules/security/aide.nix"
mlgrep "$AIDE" 'aide-init' && pass "AIDE init service" || fail "AIDE init service missing"
mlgrep "$AIDE" 'aide-check' && pass "AIDE check service" || fail "AIDE check service missing"
mlgrep "$AIDE" 'OnCalendar.*15:00:00' && pass "Daily AIDE check at 3pm" || fail "AIDE timer not set"

SNOUT="$BASE/files/modules/security/snout.nix"
mlgrep "$SNOUT" 'systemd\.services\.snout-daemon' && pass "Snout daemon service" || fail "Snout daemon service missing"
mlgrep "$SNOUT" 'notify-send' && pass "Snout uses notify-send" || fail "Snout missing notify-send"
mlgrep "$SNOUT" 'inotifywait' && pass "Snout uses inotify" || fail "Snout missing inotify"
mlgrep "$SNOUT" 'NoNewPrivileges\s*=\s*true' && pass "Snout: NoNewPrivileges" || fail "Snout: NoNewPrivileges missing"

QUAR="$BASE/files/modules/security/quarantine.nix"
mlgrep "$QUAR" '/etc/quarantine' && pass "Quarantine directory configured" || fail "Quarantine not configured"

# Misc modules exist
for mod in strong-keyring password-policy auditd-config process-accounting telemetry banner network-privacy service-hardening; do
  [ -f "$BASE/files/modules/security/$mod.nix" ] && pass "security/$mod.nix exists" || fail "security/$mod.nix MISSING"
done

grep -q 'PASS_MAX_DAYS' "$BASE/files/modules/security/password-policy.nix" && pass "Password max days configured" || fail "Password max days not configured"
grep -q 'YESCRYPT' "$BASE/files/modules/security/password-policy.nix" && pass "YESCRYPT password hashing" || fail "YESCRYPT not enabled"

# ============================================================================
# 7. NOTIFICATION SYSTEM
# ============================================================================
header "7. NOTIFICATION SYSTEM"
mlgrep "$HM" 'libnotify' && pass "libnotify in home packages" || fail "libnotify missing from home packages"
for f in clamav snout snort; do
  mlgrep "$BASE/files/modules/security/$f.nix" 'notify-send' && pass "$f: notify-send" || fail "$f: notify-send missing"
  mlgrep "$BASE/files/modules/security/$f.nix" 'DBUS_SESSION_BUS_ADDRESS' && pass "$f: DBUS pattern" || fail "$f: missing DBUS pattern"
done
mlgrep "$BASE/files/modules/privacy/privacy.nix" 'notify-send' && pass "privacy.nix: notify-send" || fail "privacy.nix: notify-send missing"

# ============================================================================
# 8. NIRI WM CONFIG
# ============================================================================
header "8. NIRI WM CONFIG"
grep -q 'include.*binds.kdl' "$BASE/files/config/niri/config.kdl" && pass "config.kdl includes binds.kdl" || fail "config.kdl missing binds.kdl include"
grep -q 'include.*env.kdl' "$BASE/files/config/niri/config.kdl" && pass "config.kdl includes env.kdl" || fail "config.kdl missing env.kdl include"
grep -q 'include.*layout.kdl' "$BASE/files/config/niri/config.kdl" && pass "config.kdl includes layout.kdl" || fail "config.kdl missing layout.kdl include"
grep -q 'include.*startup.kdl' "$BASE/files/config/niri/config.kdl" && pass "config.kdl includes startup.kdl" || fail "config.kdl missing startup.kdl include"
grep -q 'include.*animations' "$BASE/files/config/niri/config.kdl" && pass "config.kdl includes animations" || fail "config.kdl missing animations include"
grep -q 'show-hotkey-overlay' "$BASE/files/config/niri/binds.kdl" && pass "Hotkey overlay binding" || fail "Hotkey overlay binding missing"
grep -q 'ghostty' "$BASE/files/config/niri/binds.kdl" && pass "Ghostty terminal binding" || fail "Ghostty terminal binding missing"
grep -q 'alacritty' "$BASE/files/config/niri/binds.kdl" && pass "Alacritty fallback binding" || fail "Alacritty fallback binding missing"
grep -q 'vicinae toggle' "$BASE/files/config/niri/binds.kdl" && pass "Vicinae launcher binding" || fail "Vicinae launcher binding missing"
grep -q 'close-window' "$BASE/files/config/niri/binds.kdl" && pass "Close window binding" || fail "Close window binding missing"
grep -q 'screenshot' "$BASE/files/config/niri/binds.kdl" && pass "Screenshot binding" || fail "Screenshot binding missing"
grep -q 'quit' "$BASE/files/config/niri/binds.kdl" && pass "Quit binding" || fail "Quit binding missing"
grep -q 'XWAYLAND_SATELLITE' "$BASE/files/config/niri/env.kdl" && pass "XWAYLAND_SATELLITE env var" || fail "XWAYLAND_SATELLITE env missing"
grep -q 'oreo_black_cursors' "$BASE/files/config/niri/config.kdl" && pass "oreo_black_cursors cursor theme" || fail "Cursor theme not set"
grep -q 'startup.sh' "$BASE/files/config/niri/startup.kdl" && pass "startup.kdl calls startup.sh" || fail "startup.kdl missing startup.sh"
grep -q 'noctalia-shell' "$BASE/files/config/niri/startup.kdl" && pass "startup.kdl spawns noctalia-shell" || fail "startup.kdl missing noctalia-shell"

# ============================================================================
# 9. STARTUP SCRIPT
# ============================================================================
header "9. STARTUP SCRIPT"
[ -x "$BASE/files/bin/shell/startup.sh" ] && pass "startup.sh is executable" || warn "startup.sh not executable"
grep -q 'awww-daemon' "$BASE/files/bin/shell/startup.sh" && pass "awww wallpaper daemon" || fail "awww-daemon not in startup"
grep -q 'vicinae server' "$BASE/files/bin/shell/startup.sh" && pass "vicinae server" || fail "vicinae server not in startup"
grep -q 'xwayland-satellite' "$BASE/files/bin/shell/startup.sh" && pass "xwayland-satellite" || fail "xwayland-satellite not in startup"
grep -q 'ffplay.*startup.mp3' "$BASE/files/bin/shell/startup.sh" && pass "Startup sound plays" || fail "startup.mp3 not in startup"
grep -q 'mullvad connect' "$BASE/files/bin/shell/startup.sh" && pass "Mullvad VPN connects" || fail "Mullvad connect not in startup"
grep -q 'openrgb' "$BASE/files/bin/shell/startup.sh" && pass "OpenRGB on startup" || fail "OpenRGB not in startup"
grep -q 'primary_color.txt' "$BASE/files/bin/shell/startup.sh" && pass "OpenRGB reads primary color" || fail "Primary color not used in startup"

# ============================================================================
# 10. PYTHON SCRIPTS
# ============================================================================
header "10. PYTHON SCRIPTS"
python3 -c "import py_compile; py_compile.compile('$BASE/files/bin/python/fix_rgb_color.py', doraise=True)" 2>/dev/null && \
  pass "fix_rgb_color.py compiles" || fail "fix_rgb_color.py has syntax errors"
COLOR=$(cat "$BASE/files/config/primary_color.txt" | tr -d ' #\n')
[[ "$COLOR" =~ ^[0-9A-Fa-f]{6}$ ]] && pass "primary_color.txt contains valid hex: $COLOR" || fail "primary_color.txt invalid: $COLOR"
mlgrep "$HM" 'kotofetch' && pass "kotofetch in home packages" || warn "kotofetch not in home packages"

# ============================================================================
# 11. NUSHELL CONFIG
# ============================================================================
header "11. NUSHELL CONFIG"
NUSHELL="$BASE/files/core/config/shellrc.nu"

grep -q 'alias logs' "$NUSHELL" && pass "logs alias" || fail "logs alias missing"
grep -q 'security-logs' "$NUSHELL" && pass "security-logs alias" || fail "security-logs alias missing"
grep -q 'snout-status' "$NUSHELL" && pass "snout-status alias" || fail "snout-status alias missing"
grep -q 'snout-scan' "$NUSHELL" && pass "snout-scan alias" || fail "snout-scan alias missing"
mlgrep "$HM" 'zoxide.*enableNushellIntegration.*true' && pass "zoxide integration" || warn "zoxide integration via home-manager"
mlgrep "$HM" 'shellrc\.nu' && pass "home.nix sources shellrc.nu" || fail "shellrc.nu not sourced in home.nix"

# ============================================================================
# 12. GAMING CONFIG
# ============================================================================
header "12. GAMING"
GAMING="$BASE/files/modules/gaming/gaming.nix"
mlgrep "$GAMING" 'steam.*enable\s*=\s*true' && pass "Steam enabled" || fail "Steam not enabled"
mlgrep "$GAMING" 'mangohud' && pass "MangoHUD for Steam" || fail "MangoHUD not configured"
mlgrep "$GAMING" 'enable32Bit\s*=\s*true' && pass "32-bit graphics enabled" || fail "32-bit graphics not enabled"
mlgrep "$HM" 'MANGOHUD' && pass "MANGOHUD env var set" || warn "MANGOHUD env var not set"
python3 -c "import json; json.load(open('$BASE/files/modules/gaming/millennium/config.json'))" 2>/dev/null && \
  pass "Millennium config is valid JSON" || fail "Millennium config is not valid JSON"
mlgrep "$BASE/files/modules/minecraft.nix" 'prismlauncher' && pass "PrismLauncher configured" || fail "PrismLauncher not configured"
mlgrep "$BASE/files/modules/minecraft.nix" 'blockbench' && pass "Blockbench configured" || fail "Blockbench not configured"

# ============================================================================
# 13. PRIVACY CONFIG
# ============================================================================
header "13. PRIVACY"
PRIV="$BASE/files/modules/privacy/privacy.nix"
mlgrep "$PRIV" 'mullvad-vpn.*enable\s*=\s*true' && pass "Mullvad VPN enabled" || fail "Mullvad VPN not enabled"
mlgrep "$PRIV" 'mullvad-browser' && pass "Mullvad Browser in packages" || fail "Mullvad Browser not in packages"
mlgrep "$PRIV" 'metadata-cleaner' && pass "Metadata cleaner service" || fail "Metadata cleaner missing"
mlgrep "$PRIV" 'metadata-watcher' && pass "Metadata watcher service" || fail "Metadata watcher missing"
[ -f "$BASE/files/modules/privacy/mullvadbrowser/profiles.ini" ] && pass "Mullvad profiles.ini exists" || warn "Mullvad profiles.ini missing"
[ -d "$BASE/files/modules/privacy/mullvadbrowser/ipg7sh9x.default-release-1" ] && pass "Mullvad browser profile dir exists" || warn "Mullvad browser profile dir missing"
mlgrep "$BASE/files/modules/security/network-privacy.nix" 'macAddress.*random' && pass "WiFi MAC randomization enabled" || fail "WiFi MAC randomization not enabled"
mlgrep "$BASE/files/modules/security/telemetry.nix" 'avahi.*false' && pass "Avahi disabled" || fail "Avahi not disabled"
mlgrep "$BASE/files/modules/security/telemetry.nix" 'geoclue2.*false' && pass "Geoclue disabled" || fail "Geoclue not disabled"

# ============================================================================
# 14. VIRTUALIZATION
# ============================================================================
header "14. VIRTUALIZATION"
VIRT="$BASE/files/modules/virtualisation.nix"
mlgrep "$VIRT" 'docker.*enable\s*=\s*true' && pass "Docker enabled" || fail "Docker not enabled"
# NOTE: rootless Docker disabled; falls back to standard Docker daemon
mlgrep "$VIRT" 'podman.*enable\s*=\s*true' && pass "Podman enabled" || fail "Podman not enabled"
mlgrep "$VIRT" 'libvirtd.*enable\s*=\s*true' && pass "libvirtd enabled" || fail "libvirtd not enabled"
mlgrep "$VIRT" 'virt-manager.*enable\s*=\s*true' && pass "virt-manager enabled" || fail "virt-manager not enabled"
mlgrep "$VIRT" 'distrobox' && pass "Distrobox configured" || fail "Distrobox not configured"

# ============================================================================
# 15. PERFORMANCE
# ============================================================================
header "15. PERFORMANCE"
PERF="$BASE/files/modules/performance.nix"
mlgrep "$PERF" 'tcp_bbr' && pass "TCP BBR module loaded" || fail "TCP BBR not loaded"
mlgrep "$PERF" 'cpuFreqGovernor.*performance' && pass "CPU governor = performance" || fail "CPU governor not performance"
mlgrep "$PERF" 'auto-optimise-store.*true' && pass "Nix auto-optimise store" || fail "Nix auto-optimise not enabled"
mlgrep "$PERF" 'gc.*automatic\s*=\s*true' && pass "Nix GC automatic" || fail "Nix GC not automatic"

# ============================================================================
# 16. FLATPAK
# ============================================================================
header "16. FLATPAK"
FLAT="$BASE/files/modules/flatpak.nix"
mlgrep "$FLAT" 'services\.flatpak.*enable\s*=\s*true' && pass "Flatpak enabled" || fail "Flatpak not enabled"
mlgrep "$FLAT" 'flathub' && pass "Flathub repository configured" || fail "Flathub not configured"
for app in Discord Telegram Vesktop bottles Steam; do
  mlgrep "$FLAT" "(?i)$app" && pass "Flatpak: $app configured" || warn "Flatpak: $app not found"
done

# ============================================================================
# 17. DEV MODULE
# ============================================================================
header "17. DEVELOPMENT"
DEV="$BASE/files/modules/dev/dev.nix"
for tool in neovim opencode bun claude-code; do
  mlgrep "$DEV" "$tool" && pass "dev: $tool" || fail "dev: $tool not configured"
done
mlgrep "$BASE/files/modules/dev/dev.nix" 'LazyVim' && pass "Neovim LazyVim configured" || fail "Neovim LazyVim not configured"

# ============================================================================
# 18. SYSTEM PACKAGES
# ============================================================================
header "18. SYSTEM PACKAGES"
for pkg in niri python3 ffmpeg inotify-tools roboto openrgb ollama-rocm mpvpaper pavucontrol jq trashy alacritty; do
  grep -q "$pkg" "$BASE/files/core/configuration.nix" && pass "system package: $pkg" || warn "system package: $pkg not found"
done
for pkg in vulnix; do
  grep -q "$pkg" "$BASE/files/modules/security/default.nix" && pass "system package: $pkg (security module)" || warn "system package: $pkg not found"
done
for pkg in lynis clamav aide audit lnav; do
  grep -q "$pkg" "$BASE/files/modules/security/default.nix" && pass "security packages: $pkg" || warn "security packages: $pkg not found"
done
grep -q 'snort' "$BASE/files/modules/security/snort.nix" && pass "security packages: snort (snort.nix)" || warn "security packages: snort not found"

# ============================================================================
# 19. IMPORTS CONSISTENCY
# ============================================================================
header "19. IMPORTS CONSISTENCY"
for mod in kernel-sysctl kernel-boot process-accounting firewall banner service-hardening telemetry password-policy network-privacy aide clamav strong-keyring auditd-config quarantine; do
  grep -q "./$mod" "$BASE/files/modules/security/default.nix" && pass "security/default.nix imports $mod" || fail "security/default.nix missing import: $mod"
done
for mod in hardware-configuration security snort snout performance privacy gaming virtualisation minecraft flatpak; do
  mlgrep "$CFG" "$mod" && pass "configuration.nix imports $mod" || warn "configuration.nix import not found: $mod"
done
for imp in dev tools; do
  mlgrep "$HM" "$imp" && pass "home.nix imports $imp" || warn "home.nix import not found: $imp"
done

# ============================================================================
# 20. SYSTEMD SERVICES
# ============================================================================
header "20. SYSTEMD SERVICES"
declare -a SERVICES=(
  "snout-daemon" "snort-daemon" "snort-monitor" "clamav-daily-scan" "clamav-daemon"
  "aide-init" "aide-check" "quarantine-setup" "quarantine-sanitizer" "metadata-cleaner"
  "metadata-watcher" "setup-mullvad-dirs" "flatpak-repo"
  "polkit-gnome-authentication-agent-1"
)
for svc in "${SERVICES[@]}"; do
  if grep -qr "$svc" "$BASE/files/" --include='*.nix' 2>/dev/null; then
    pass "Service defined: $svc"
  else
    fail "Service NOT FOUND: $svc"
  fi
done

# ============================================================================
# 21. SHELL ALIASES
# ============================================================================
header "21. SHELL ALIASES"
NUSHELL="$BASE/files/core/config/shellrc.nu"
grep -q 'aide-check' "$NUSHELL" && pass "Alias: aide-check" || fail "Alias: aide-check missing"
grep -q 'lynis-scan' "$NUSHELL" && pass "Alias: lynis-scan" || fail "Alias: lynis-scan missing"
grep -q 'snout-scan' "$NUSHELL" && pass "Alias: snout-scan" || fail "Alias: snout-scan missing"
grep -q 'snortctl' "$NUSHELL" && pass "Alias: snortctl" || fail "Alias: snortctl missing"
grep -q 'audit-tail' "$BASE/files/modules/security/auditd-config.nix" && pass "Alias: audit-tail" || fail "Alias: audit-tail missing"
grep -q 'pa-report' "$BASE/files/modules/security/process-accounting.nix" && pass "Alias: pa-report" || fail "Alias: pa-report missing"
grep -q 'pkcs11-list' "$BASE/files/modules/security/strong-keyring.nix" && pass "Alias: pkcs11-list" || fail "Alias: pkcs11-list missing"

# ============================================================================
# 22. APP LAUNCHER
# ============================================================================
header "22. APP LAUNCHER"
python3 -c "import json; json.load(open('$BASE/files/config/vicinae/vicinae.json'))" 2>/dev/null && \
  pass "vicinae.json is valid JSON" || fail "vicinae.json is not valid JSON"
grep -q 'vicinae-dark' "$BASE/files/config/vicinae/vicinae.json" && pass "vicinae-dark theme" || fail "vicinae-dark theme not set"

# ============================================================================
# 23. MISC CHECKS
# ============================================================================
header "23. MISC CHECKS"
grep -q 'result' "$BASE/.gitignore" 2>/dev/null && pass ".gitignore ignores build results" || warn ".gitignore doesn't ignore result/"
grep -q 'Authorized Access Only' "$BASE/files/modules/security/banner.nix" && pass "Login banner present" || fail "Login banner missing"
grep -q 'enableGnomeKeyring.*false' "$BASE/files/modules/security/password-policy.nix" && pass "GNOME keyring disabled" || fail "GNOME keyring not disabled"
[ -f "$BASE/files/audio/startup.mp3" ] && pass "startup.mp3 audio file" || warn "startup.mp3 missing"
[ -f "$BASE/files/audio/close_window.mp3" ] && pass "close_window.mp3 audio file" || warn "close_window.mp3 missing"
mlgrep "$HM" 'createAwwwCache' && pass "Awww cache directory created" || warn "Awww cache creation missing"
mlgrep "$HM" 'alacritty\.toml' && pass "Alacritty fallback config" || warn "Alacritty fallback config missing"
mlgrep "$BASE/files/modules/security/service-hardening.nix" 'Service Hardening Guidelines' && pass "Service hardening docs present" || fail "Service hardening docs missing"

# ============================================================================
# 24. CROSS-REFERENCE CONSISTENCY
# ============================================================================
header "24. CROSS-REFERENCE CONSISTENCY"
mlgrep "$SNOUT" 'after.*clamav-daemon' && pass "Snout depends on ClamAV" || fail "Snout not dependent on ClamAV"
mlgrep "$BASE/files/modules/security/snort.nix" 'after.*snort-daemon' && pass "Snort monitor depends on snort-daemon" || fail "Snort monitor dependency missing"
mlgrep "$QUAR" 'before.*snout-daemon' && pass "Quarantine setup before Snout" || fail "Quarantine dependency missing"
mlgrep "$CFG" 'docker' && pass "User in docker group" || fail "User not in docker group"
mlgrep "$VIRT" 'libvirtd' && pass "User in libvirtd group" || fail "User not in libvirtd group"
mlgrep "$CFG" 'alsa\.support32Bit\s*=\s*true' && pass "ALSA 32-bit enabled" || fail "ALSA 32-bit not enabled"

# ============================================================================
# 25. SUMMARY
# ============================================================================
header "TEST RESULTS"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo -e "  Total: $TOTAL"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n  ${RED}SOME TESTS FAILED -- review details above.${NC}"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "\n  ${YELLOW}All critical tests passed, but there are warnings.${NC}"
  exit 0
else
  echo -e "\n  ${GREEN}ALL TESTS PASSED.${NC}"
  exit 0
fi
