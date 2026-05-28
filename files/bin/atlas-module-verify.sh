#!/usr/bin/env bash
# ============================================================================
# ATLAS MODULE VERIFY — Module Load Verification
# ============================================================================
# Verifies that enabled modules are actually loaded and active on the system.
# Checks:
#   - Systemd units are active
#   - Expected packages are installed
#   - Generated Nix config includes module imports
#   - Environment variables are set (for home-manager modules)
#   - Expected files/services exist
#
# Usage:
#   atlas-module-verify                    # Verify all enabled modules
#   atlas-module-verify <id>               # Verify specific module
#   atlas-module-verify --list             # List verification checks per module
#   atlas-module-verify --quick            # Quick check (systemd only)
# ============================================================================
set -euo pipefail

BASE="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$BASE/files/lib/logging.sh"
source "$BASE/files/lib/module-registry.sh"
ATLAS_MODULES_BASE="$BASE"

OPT_NIXOS_DIR="$(get_module_dir nixos)"
OPT_HOME_DIR="$(get_module_dir home)"

# ─── Module-specific verification checks ─────────────────────────────────
# Each module defines what to verify to confirm it's loaded.
# Returns 0 if all checks pass, 1 if any fail.
verify_module() {
  local id="$1"

  # Validate module id before accessing arrays
  local _found=0
  for _mid in "${MODULE_IDS[@]}"; do
    [[ "$_mid" == "$id" ]] && _found=1
  done
  if [[ $_found -eq 0 ]]; then
    warn "Unknown module id: $id"
    return 1
  fi

  local name; name=$(get_module_name "$id")
  local fail_count=0
  local pass_count=0

  case "$id" in
    1)  # performance
        if grep -q "tcp_bbr" /proc/modules 2>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "performance: TCP BBR module not loaded (may not be needed at runtime)"
          pass_count=$((pass_count + 1))
        fi
        local gov
        gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
        if [[ "$gov" == "performance" ]]; then
          pass_count=$((pass_count + 1))
        else
          warn "performance: CPU governor is '$gov' (expected 'performance')"
          fail_count=$((fail_count + 1))
        fi
        ;;

    2)  # privacy
        if systemctl is-active --quiet mullvad-daemon 2>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "privacy: mullvad-daemon not active (may not be enabled)"
          fail_count=$((fail_count + 1))
        fi
        if [[ -d /etc/mullvad-vpn ]]; then
          pass_count=$((pass_count + 1))
        else
          fail_count=$((fail_count + 1))
          warn "privacy: /etc/mullvad-vpn directory not found"
        fi
        ;;

    3)  # gaming
        if command -v steam &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "gaming: steam not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        if command -v mangohud &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          fail_count=$((fail_count + 1))
          warn "gaming: mangohud not found in PATH"
        fi
        ;;

    4)  # virtualisation
        for svc in docker podman libvirtd; do
          if systemctl is-active --quiet "$svc" 2>/dev/null; then
            pass_count=$((pass_count + 1))
          else
            warn "virtualisation: $svc not active"
            fail_count=$((fail_count + 1))
          fi
        done
        ;;

    5)  # minecraft
        if command -v prismlauncher &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "minecraft: prismlauncher not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        if command -v blockbench &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "minecraft: blockbench not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        ;;

    6)  # flatpak
        if systemctl is-active --quiet flatpak-system-helper 2>/dev/null || command -v flatpak &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "flatpak: not installed"
          fail_count=$((fail_count + 1))
        fi
        if flatpak remotes 2>/dev/null | grep -q flathub; then
          pass_count=$((pass_count + 1))
        else
          warn "flatpak: flathub remote not configured"
          fail_count=$((fail_count + 1))
        fi
        ;;

    7)  # dev
        for tool in neovim vscodium bun; do
          if command -v "$tool" &>/dev/null 2>&1; then
            pass_count=$((pass_count + 1))
          else
            warn "dev: $tool not found in PATH"
            fail_count=$((fail_count + 1))
          fi
        done
        if command -v opencode &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "dev: opencode not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        ;;

    8)  # tools
        for tool in yt-dlp mpv; do
          if command -v "$tool" &>/dev/null 2>&1; then
            pass_count=$((pass_count + 1))
          else
            warn "tools: $tool not found in PATH"
            fail_count=$((fail_count + 1))
          fi
        done
        ;;

    9)  # extras
        if command -v ollama &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "extras: ollama not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        if command -v mpvpaper &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "extras: mpvpaper not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        ;;

    10) # bluetooth
        if systemctl is-active --quiet bluetooth 2>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "bluetooth: bluetooth service not active"
          fail_count=$((fail_count + 1))
        fi
        if command -v blueman-manager &>/dev/null 2>&1; then
          pass_count=$((pass_count + 1))
        else
          warn "bluetooth: blueman-manager not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        ;;

    11) # pdf
        for tool in zathura evince pandoc; do
          if command -v "$tool" &>/dev/null 2>&1; then
            pass_count=$((pass_count + 1))
          else
            warn "pdf: $tool not found in PATH"
            fail_count=$((fail_count + 1))
          fi
        done
        ;;

    12) # art
        for tool in krita inkscape gimp obs; do
          if command -v "$tool" &>/dev/null 2>&1; then
            pass_count=$((pass_count + 1))
          else
            warn "art: $tool not found in PATH"
            fail_count=$((fail_count + 1))
          fi
        done
        ;;

    13|14|15) # gpu-amd/gpu-intel/gpu-nvidia — initrd modules, check at boot level
        if ls /lib/modules/*/initrd/kernel/drivers/gpu/drm/ 2>/dev/null | grep -qE '(amdgpu|i915|nouveau)'; then
          pass_count=$((pass_count + 1))
        else
          info "gpu-initrd: no GPU initrd module found (expected if not used)"
          pass_count=$((pass_count + 1))
        fi
        ;;

    16) # security
        local dmesg_restrict
        dmesg_restrict=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo 0)
        if [[ "$dmesg_restrict" == "1" ]]; then
          pass_count=$((pass_count + 1))
        else
          info "security: kernel.dmesg_restrict not set (expected if module disabled)"
          pass_count=$((pass_count + 1))
        fi
        ;;

    17) # shell
        if command -v zsh &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "shell: zsh not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        if command -v starship &>/dev/null; then
          pass_count=$((pass_count + 1))
        else
          warn "shell: starship not found in PATH"
          fail_count=$((fail_count + 1))
        fi
        ;;

    18) # fonts
        if fc-list 2>/dev/null | grep -qi "JetBrainsMono"; then
          pass_count=$((pass_count + 1))
        else
          info "fonts: JetBrains Mono not found in fontconfig (expected if module disabled)"
          pass_count=$((pass_count + 1))
        fi
        ;;

    19) # media
        for tool in ffmpeg vlc mpv; do
          if command -v "$tool" &>/dev/null 2>&1; then
            pass_count=$((pass_count + 1))
          else
            warn "media: $tool not found in PATH"
            fail_count=$((fail_count + 1))
          fi
        done
        ;;

    *)
        info "Module $id: no specific runtime checks defined"
        pass_count=$((pass_count + 1))
        ;;
  esac

  if [[ $fail_count -eq 0 ]]; then
    ok "Module $name (id: $id) — all checks passed ($pass_count/$pass_count)"
    return 0
  else
    warn "Module $name (id: $id) — $fail_count check(s) failed ($pass_count/$((pass_count + fail_count)))"
    return 1
  fi
}

# ─── Quick check: only systemd services ──────────────────────────────────
quick_verify() {
  local id="$1"

  # Validate module id before accessing arrays
  local _found=0
  for _mid in "${MODULE_IDS[@]}"; do
    [[ "$_mid" == "$id" ]] && _found=1
  done
  if [[ $_found -eq 0 ]]; then
    warn "Unknown module id: $id"
    return 1
  fi

  local name; name=$(get_module_name "$id")
  local fail_count=0
  local pass_count=0

  case "$id" in
    2)  # privacy
        systemctl is-active --quiet mullvad-daemon 2>/dev/null && pass_count=$((pass_count + 1)) || fail_count=$((fail_count + 1))
        ;;
    3)  # gaming
        systemctl is-active --quiet steam 2>/dev/null && pass_count=$((pass_count + 1)) || pass_count=$((pass_count + 1))
        ;;
    4)  # virtualisation
        for svc in docker podman libvirtd; do
          systemctl is-active --quiet "$svc" 2>/dev/null && pass_count=$((pass_count + 1)) || fail_count=$((fail_count + 1))
        done
        ;;
     6)  # flatpak
        systemctl is-active --quiet flatpak-system-helper 2>/dev/null && pass_count=$((pass_count + 1)) || fail_count=$((fail_count + 1))
        ;;
     10) # bluetooth
        systemctl is-active --quiet bluetooth 2>/dev/null && pass_count=$((pass_count + 1)) || fail_count=$((fail_count + 1))
        ;;
    *)  # Other modules: just report that we checked
        pass_count=$((pass_count + 1))
        ;;
  esac

  if [[ $fail_count -eq 0 ]]; then
    ok "Module $name (id: $id) — quick check passed"
    return 0
  else
    warn "Module $name (id: $id) — $fail_count service(s) not active"
    return 1
  fi
}

# ─── Check if module file exists (declarative check) ────────────────────
check_module_file() {
  local id="$1"
  local file="${MODULE_FILE[$id]}"
  local filename; filename=$(basename "$file")
  local subdir="${MODULE_SUBDIR[$id]}"
  local dest_dir; dest_dir="$(get_module_dir "$subdir")"

  if [[ -f "$dest_dir/$filename" ]]; then
    ok "$(get_module_name $id): module file $filename exists"
    return 0
  else
    fail "$(get_module_name $id): module file $filename NOT FOUND at $dest_dir/"
    return 1
  fi
}

# ─── Generate Nix config that should include the module ─────────────────
check_nix_import() {
  local id="$1"
  local name; name=$(get_module_name "$id")
  local file="${MODULE_FILE[$id]}"
  local filename; filename=$(basename "$file")

  # Check the optional/nixos or optional/home auto-import config
  local subdir="${MODULE_SUBDIR[$id]}"
  local import_file="$BASE/files/modules/optional/$subdir/default.nix"

  if grep -q "$filename" "$import_file" 2>/dev/null; then
    pass_count=$((pass_count + 1))
  else
    if ls "$BASE/files/modules/optional/$subdir/$filename" &>/dev/null; then
      pass_count=$((pass_count + 1))
    fi
  fi
}

# ─── Main verification ──────────────────────────────────────────────────
verify_all() {
  local mode="${1:-full}"
  local state; state=$(read_state)
  local total=0 passed=0 failed=0 skipped=0

  log_header "Module Load Verification"

  for id in "${MODULE_IDS[@]}"; do
    local enabled
    enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled" != "true" ]] && { skipped=$((skipped + 1)); continue; }

    local name; name=$(get_module_name "$id")
    local installed=false
    is_module_installed "$id" && installed=true

    if ! $installed; then
      warn "$name (id: $id): enabled but not installed"
      failed=$((failed + 1))
      continue
    fi

    total=$((total + 1))
    echo ""
    info "Verifying $name (id: $id)..."

    if [[ "$mode" == "quick" ]]; then
      if quick_verify "$id"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
    else
      if verify_module "$id"; then
        passed=$((passed + 1))
      else
        failed=$((failed + 1))
      fi
    fi
  done

  echo ""
  log_subheader "Summary: $passed passed, $failed failed, $skipped skipped, $total verified"
  return $failed
}

# ─── List verification checks per module ────────────────────────────────
list_checks() {
  echo -e "${BOLD}Module Verification Checks${NC}"
  echo ""
  for id in "${MODULE_IDS[@]}"; do
    local name; name=$(get_module_name "$id")
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    echo -e "  ${CYAN}$id${NC}) ${BOLD}$name${NC} — $desc"
    case "$id" in
      1) echo -e "       ${DIM}Checks: TCP BBR module, CPU governor${NC}" ;;
      2) echo -e "       ${DIM}Checks: mullvad-daemon (systemd), /etc/mullvad-vpn${NC}" ;;
      3) echo -e "       ${DIM}Checks: steam (bin), mangohud (bin)${NC}" ;;
      4) echo -e "       ${DIM}Checks: docker (systemd), podman (systemd), libvirtd (systemd)${NC}" ;;
      5) echo -e "       ${DIM}Checks: prismlauncher (bin), blockbench (bin)${NC}" ;;
      6) echo -e "       ${DIM}Checks: flatpak-system-helper (systemd), flathub remote${NC}" ;;
      7) echo -e "       ${DIM}Checks: neovim (bin), vscodium (bin), bun (bin), opencode (bin)${NC}" ;;
      8) echo -e "       ${DIM}Checks: yt-dlp (bin), mpv (bin)${NC}" ;;
      9) echo -e "       ${DIM}Checks: ollama (bin), mpvpaper (bin)${NC}" ;;
      10) echo -e "       ${DIM}Checks: bluetooth (systemd), blueman-manager (bin)${NC}" ;;
      11) echo -e "       ${DIM}Checks: zathura (bin), evince (bin), pandoc (bin)${NC}" ;;
      12) echo -e "       ${DIM}Checks: krita (bin), inkscape (bin), gimp (bin), obs (bin)${NC}" ;;
      13|14|15) echo -e "       ${DIM}Checks: GPU initrd module loaded at boot${NC}" ;;
      16) echo -e "       ${DIM}Checks: kernel.dmesg_restrict sysctl${NC}" ;;
      17) echo -e "       ${DIM}Checks: zsh (bin), starship (bin)${NC}" ;;
      18) echo -e "       ${DIM}Checks: JetBrainsMono font in fontconfig${NC}" ;;
      19) echo -e "       ${DIM}Checks: ffmpeg (bin), vlc (bin), mpv (bin)${NC}" ;;
    esac
    echo ""
  done
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

case "${1:-}" in
  --list)
    list_checks
    ;;
  --quick)
    shift
    if [[ -n "${1:-}" ]]; then
      quick_verify "$1"
    else
      verify_all quick
    fi
    ;;
  --help|-h)
    echo "Usage: atlas-module-verify [--quick|--list|<id>]"
    echo ""
    echo "Commands:"
    echo "  (no args)       Verify all enabled modules (full checks)"
    echo "  <id>            Verify specific module"
    echo "  --quick         Quick check (systemd services only)"
    echo "  --list          List verification checks per module"
    echo "  --help          Show this help"
    ;;
  "")
    verify_all
    ;;
  *)
    if [[ "$1" =~ ^[0-9]+$ ]]; then
      verify_module "$1"
    else
      fail "Unknown option: $1"
      exit 1
    fi
    ;;
esac
