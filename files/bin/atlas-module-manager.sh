#!/usr/bin/env bash
# ============================================================================
# ATLAS MODULE MANAGER — TUI Interface
# ============================================================================
# fzf-based TUI for browsing, enabling/disabling, downloading, and removing
# optional modules. Works entirely from a TTY.
#
# Usage: atlas-module-manager
# ============================================================================
set -euo pipefail
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

# ─── Paths ──────────────────────────────────────────────────────────────────
BASE="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$BASE/files/lib/logging.sh"
source "$BASE/files/lib/module-registry.sh"
ATLAS_MODULES_BASE="$BASE"

OPT_NIXOS_DIR="$(get_module_dir nixos)"
OPT_HOME_DIR="$(get_module_dir home)"

# ─── UI Helpers ────────────────────────────────────────────────────────────
header() {
  clear
  echo -e "${CYAN}┌─ Atlas Module Manager ──────────────────────────────────────┐${NC}"
  echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# ─── Module Status ──────────────────────────────────────────────────────────
get_module_status() {
  local id="$1"
  local state
  state=$(read_state)
  local enabled
  enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
  local installed=false
  local file="${MODULE_FILE[$id]}"
  local filename; filename=$(basename "$file")
  local subdir="${MODULE_SUBDIR[$id]}"
  local dest_dir
  dest_dir="$(get_module_dir "$subdir")"

  if [[ -f "$dest_dir/$filename" ]]; then
    installed=true
  fi

  if [[ "$installed" == "true" && "$enabled" == "true" ]]; then
    echo -e "${GREEN}● Enabled${NC}  ${DIM}($filename)${NC}"
  elif [[ "$installed" == "true" && "$enabled" == "false" ]]; then
    echo -e "${YELLOW}○ Disabled${NC} ${DIM}($filename)${NC}"
  elif [[ "$installed" == "false" ]]; then
    echo -e "${DIM}○ Not installed${NC}"
  fi
}

# ─── Detect available TUI backends ─────────────────────────────────────────
HAS_FZF=false; HAS_GUM=false; HAS_DIALOG=false; HAS_WHIPTAIL=false
command -v fzf &>/dev/null && HAS_FZF=true
command -v gum &>/dev/null && HAS_GUM=true
command -v dialog &>/dev/null && HAS_DIALOG=true
command -v whiptail &>/dev/null && HAS_WHIPTAIL=true

# ─── TUI Backend Selection ─────────────────────────────────────────────────
# Priority: fzf > gum > dialog > whiptail > basic_tty
# User can force a backend: ATLAS_MODULE_UI=fzf|gum|dialog|whiptail|tty
select_backend() {
  local forced="${ATLAS_MODULE_UI:-}"
  if [[ -n "$forced" ]]; then
    echo "$forced"
    return
  fi
  if $HAS_FZF; then echo "fzf"; return; fi
  if $HAS_GUM; then echo "gum"; return; fi
  if $HAS_DIALOG; then echo "dialog"; return; fi
  if $HAS_WHIPTAIL; then echo "whiptail"; return; fi
  echo "tty"
}

UI_BACKEND=$(select_backend)

# ─── TTY-only helper: check if running without display ────────────────────
is_tty_only() {
  [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]
}

tty_echo() {
  echo -e "$@"
}

# ─── Main Menu ──────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    header
    echo -e "  ${BOLD}Welcome to the Atlas Module Manager${NC}"
    echo -e "  ${DIM}Manage optional NixOS modules for your system${NC}"
    spacer
    echo -e "  ${CYAN}1${NC}) Browse & Manage Modules"
    echo -e "  ${CYAN}2${NC}) Check Module Status"
    echo -e "  ${CYAN}3${NC}) Download / Install Modules"
    echo -e "  ${CYAN}4${NC}) Update All Modules"
    echo -e "  ${CYAN}5${NC}) Remove a Module"
    echo -e "  ${CYAN}6${NC}) Apply Changes & Rebuild"
    echo -e "  ${CYAN}7${NC}) Show Module Info"
    echo -e "  ${CYAN}8${NC}) Browse by Category"
    echo -e "  ${CYAN}9${NC}) Search Modules"
    echo -e "  ${CYAN}10${NC}) Validate Module State"
    echo -e "  ${CYAN}d${NC}) Toggle Detailed View"
    echo -e "  ${CYAN}q${NC}) Quit"
    spacer
    read -rp "$(echo -e "${CYAN}Choose an option: ${NC}")" choice

    case "$choice" in
      1) browse_modules ;;
      2) check_status ;;
      3) install_modules ;;
      4) update_modules ;;
      5) remove_modules ;;
      6) apply_changes ;;
      7) module_info ;;
      8) browse_by_category ;;
      9) search_modules ;;
      10) validate_and_report ;;
      d|D) DETAIL_VIEW=$((1 - ${DETAIL_VIEW:-0}))
           [[ $DETAIL_VIEW -eq 1 ]] && ok "Detailed view ON" || info "Detailed view OFF"
           sleep 1 ;;
      q|Q|quit|exit) clear; exit 0 ;;
      *) warn "Invalid option" && sleep 1 ;;
    esac
  done
}

# ─── TTY Menu (whiptail/dialog/basic fallback) ─────────────────────────────
tty_main_menu() {
  while true; do
    local title="Atlas Module Manager"
    local menu_choices

    if [[ "$UI_BACKEND" == "whiptail" ]] || [[ "$UI_BACKEND" == "dialog" ]]; then
      local cmd; cmd="$UI_BACKEND"
      local choices=(
        "1" "Browse & Manage Modules"
        "2" "Check Module Status"
        "3" "Download / Install Modules"
        "4" "Update All Modules"
        "5" "Remove a Module"
        "6" "Apply Changes & Rebuild"
        "7" "Show Module Info"
        "8" "Browse by Category"
        "9" "Search Modules"
        "10" "Validate Module State"
        "11" "Verify Loaded Modules"
        "Q" "Quit"
      )
      local choice
      choice=$("$cmd" --title "$title" --menu "Choose an option:" 22 70 12 "${choices[@]}" 3>&1 1>&2 2>&3) || { clear; exit 0; }

      case "$choice" in
        1) tty_browse_modules ;;
        2) tty_check_status ;;
        3) tty_install_modules ;;
        4) tty_update_modules ;;
        5) tty_remove_modules ;;
        6) tty_apply_changes ;;
        7) tty_module_info ;;
        8) tty_browse_by_category ;;
        9) tty_search_modules ;;
        10) tty_validate ;;
        11) tty_verify_modules ;;
        Q|q) clear; exit 0 ;;
      esac
    else
      # Pure TTY fallback (no whiptail/dialog)
      header
      echo -e "  ${BOLD}Welcome to the Atlas Module Manager${NC}"
      echo -e "  ${DIM}Manage optional NixOS modules for your system${NC}"
      spacer
      echo -e "  ${CYAN}1${NC}) Browse & Manage Modules"
      echo -e "  ${CYAN}2${NC}) Check Module Status"
      echo -e "  ${CYAN}3${NC}) Download / Install Modules"
      echo -e "  ${CYAN}4${NC}) Update All Modules"
      echo -e "  ${CYAN}5${NC}) Remove a Module"
      echo -e "  ${CYAN}6${NC}) Apply Changes & Rebuild"
      echo -e "  ${CYAN}7${NC}) Show Module Info"
      echo -e "  ${CYAN}8${NC}) Browse by Category"
      echo -e "  ${CYAN}9${NC}) Search Modules"
      echo -e "  ${CYAN}10${NC}) Validate Module State"
      echo -e "  ${CYAN}11${NC}) Verify Loaded Modules"
      echo -e "  ${CYAN}q${NC}) Quit"
      spacer
      read -rp "$(echo -e "${CYAN}Choose an option: ${NC}")" choice

      case "$choice" in
        1) tty_browse_modules ;;
        2) tty_check_status ;;
        3) tty_install_modules ;;
        4) tty_update_modules ;;
        5) tty_remove_modules ;;
        6) tty_apply_changes ;;
        7) tty_module_info ;;
        8) tty_browse_by_category ;;
        9) tty_search_modules ;;
        10) tty_validate ;;
        11) tty_verify_modules ;;
        q|Q|quit|exit) clear; exit 0 ;;
        *) warn "Invalid option" && sleep 1 ;;
      esac
    fi
  done
}

# ─── TTY Helper Functions ─────────────────────────────────────────────────

tty_check_status() {
  header
  echo -e "  ${BOLD}Module Status${NC}"
  spacer
  local state; state=$(read_state)
  for id in "${MODULE_IDS[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    local installed=false; is_module_installed "$id" && installed=true
    local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")

    if $installed; then
      if [[ "$enabled_str" == "true" ]]; then
        echo -e "  ${GREEN}[●]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
      else
        echo -e "  ${YELLOW}[○]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  ${YELLOW}(disabled)${NC}"
      fi
    else
      echo -e "  ${DIM}[ ]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  (not installed)${NC}"
    fi
  done
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_browse_modules() {
  tty_check_status
}

tty_install_modules() {
  header
  echo -e "  ${BOLD}Download & Install Modules${NC}"
  spacer
  echo -e "  ${DIM}Enter module IDs to install (space-separated, e.g. '1 3 7')${NC}"
  spacer
  local state; state=$(read_state)
  for id in "${MODULE_IDS[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    local installed=false; is_module_installed "$id" && installed=true
    local status; $installed && status="INSTALLED" || status="available"
    echo -e "  ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}  [${status}]"
  done
  spacer
  read -rp "$(echo -e "${CYAN}Module IDs to install: ${NC}")" ids
  [[ -z "$ids" ]] && return

  local dl_fail=0
  local state; state=$(read_state)
  for id in $ids; do
    [[ ! "$id" =~ ^[0-9]+$ ]] && continue
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    printf "  ${CYAN}→${NC} Installing ${BOLD}%s${NC} ... " "$(get_module_name $id)"
    if download_module "$id" "$dest_dir"; then
      ok "$filename"
      state=$(echo "$state" | jq ".\"$id\".enabled = true | .\"$id\".installed = true | .\"$id\".source = \"$ATLAS_MODULES_RAW_URL\" | .\"$id\".version = \"${MODULE_VERSION[$id]}\"")
      local deps="${MODULE_DEPS[$id]}"
      if [[ -n "$deps" ]]; then
        for dep in $deps; do
          local dep_file="${MODULE_FILE[$dep]}"
          local dep_fn; dep_fn=$(basename "$dep_file")
          local dep_subdir="${MODULE_SUBDIR[$dep]}"
          local dep_dest; dep_dest="$(get_module_dir "$dep_subdir")"
          if [[ ! -f "$dep_dest/$dep_fn" ]]; then
            if download_module "$dep" "$dep_dest"; then
              ok "Dependency $dep_fn also installed"
              state=$(echo "$state" | jq ".\"$dep\".enabled = true | .\"$dep\".installed = true | .\"$dep\".version = \"${MODULE_VERSION[$dep]}\"")
            fi
          fi
        done
      fi
    else
      fail "Failed to download $(get_module_name $id)"
      dl_fail=1
    fi
  done
  write_state "$state"
  spacer
  [[ $dl_fail -eq 0 ]] && ok "All modules installed." || warn "Some modules failed."
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_remove_modules() {
  header
  echo -e "  ${BOLD}Remove Modules${NC}"
  spacer
  local state; state=$(read_state)
  local installed_ids=()
  for id in "${MODULE_IDS[@]}"; do
    is_module_installed "$id" && installed_ids+=("$id")
  done
  [[ ${#installed_ids[@]} -eq 0 ]] && { info "No modules installed."; spacer; read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"; return; }

  for id in "${installed_ids[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    echo -e "  ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
  done
  spacer
  read -rp "$(echo -e "${CYAN}Module IDs to remove: ${NC}")" ids
  [[ -z "$ids" ]] && return

  local new_state="$state"
  for id in $ids; do
    [[ ! "$id" =~ ^[0-9]+$ ]] && continue
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    if rm -f "$dest_dir/$filename" 2>/dev/null; then
      ok "Removed $(get_module_name $id)"
      new_state=$(echo "$new_state" | jq "del(.\"$id\")")
    else
      fail "Failed to remove $(get_module_name $id)"
    fi
  done
  write_state "$new_state"
  spacer
  info "Module files removed. Run option 6 to apply changes."
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_update_modules() {
  header
  echo -e "  ${BOLD}Update All Modules${NC}"
  spacer
  local updated=0 failed=0
  for id in "${MODULE_IDS[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    if [[ -f "$dest_dir/$filename" ]]; then
      printf "  ${CYAN}→${NC} Updating ${BOLD}%s${NC} ... " "$(get_module_name $id)"
      cp "$dest_dir/$filename" "$dest_dir/.${filename}.bak" 2>/dev/null || true
      if download_module "$id" "$dest_dir"; then
        ok "Updated"
        local s; s=$(read_state)
        s=$(echo "$s" | jq ".\"$id\".version = \"${MODULE_VERSION[$id]}\"")
        write_state "$s"
        updated=$((updated + 1))
        rm -f "$dest_dir/.${filename}.bak"
      else
        [[ -f "$dest_dir/.${filename}.bak" ]] && mv "$dest_dir/.${filename}.bak" "$dest_dir/$filename"
        fail "Update failed"
        failed=$((failed + 1))
      fi
    fi
  done
  spacer
  [[ $updated -gt 0 ]] && ok "Updated $updated module(s)."
  [[ $failed -gt 0 ]] && warn "$failed module(s) failed."
  [[ $updated -eq 0 && $failed -eq 0 ]] && info "No modules to update."
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_apply_changes() {
  header
  echo -e "  ${BOLD}Apply Changes & Rebuild${NC}"
  spacer
  local state; state=$(read_state)
  local enabled_count; enabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == true)] | length')
  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    Enabled modules:    ${CYAN}$enabled_count${NC}"
  echo -e "    Flake target:       ${DIM}#atlas${NC}"
  spacer
  read -rp "$(echo -e "${YELLOW}  Run nixos-rebuild switch now? (y/N): ${NC}")" confirm
  shopt -s nocasematch
  [[ "$confirm" != "y" ]] && { info "Cancelled."; return; }
  shopt -u nocasematch
  spacer
  echo -e "  ${YELLOW}Running nixos-rebuild switch...${NC}"
  echo -e "  ${DIM}(This may take several minutes)${NC}"
  spacer
  # Stop tamper-detection services before rebuild
  sudo systemctl stop snort-daemon snort-monitor snout-watcher.service snout-watcher.path aide-check.service aide-check.timer firmware-version-check tpm-attestation-check secureboot-verify 2>/dev/null || true
  sudo nixos-rebuild switch --flake "$BASE#atlas" 2>&1 | tee /tmp/atlas-module-rebuild.log
  local rebuild_exit=${PIPESTATUS[0]}
  if [[ $rebuild_exit -eq 0 ]]; then
    ok "Rebuild successful!"
    local s; s=$(read_state)
    s=$(echo "$s" | jq --arg now "$(date -Iseconds)" '.metadata.last_rebuild = $now')
    write_state "$s"
  else
    fail "Rebuild failed (exit $rebuild_exit). Check /tmp/atlas-module-rebuild.log"
  fi
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_module_info() {
  header
  echo -e "  ${BOLD}Module Information${NC}"
  spacer
  for id in "${MODULE_IDS[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    echo -e "  ${CYAN}$id${NC}) ${BOLD}$name${NC}"
  done
  spacer
  read -rp "$(echo -e "${CYAN}Enter module ID: ${NC}")" sel
  [[ -z "$sel" || ! "$sel" =~ ^[0-9]+$ ]] && return

  local name; name=$(get_module_name "$sel")
  local desc="${MODULE_DESC[$sel]#* }"; desc="${desc# }"
  local info_text="${MODULE_INFO[$sel]}"
  local cat="${MODULE_CATEGORY[$sel]}"
  local file="${MODULE_FILE[$sel]}"
  local subdir="${MODULE_SUBDIR[$sel]}"
  local version="${MODULE_VERSION[$sel]}"
  local deps="${MODULE_DEPS[$sel]}"
  local tags="${MODULE_TAGS[$sel]}"

  spacer
  echo -e "  ${BOLD}$name${NC} (id: $sel)"
  echo -e "  ${DIM}$desc${NC}"
  echo -e "  Category: $cat  |  Type: $subdir  |  Version: $version"
  echo -e "  File: $file  |  Tags: $tags"
  [[ -n "$deps" ]] && echo -e "  Dependencies: $deps" || echo -e "  Dependencies: none"
  echo -e "  ${DIM}$info_text${NC}"
  spacer
  echo -e "  Source: ${DIM}$ATLAS_MODULES_RAW_URL/$file${NC}"

  local installed=false; is_module_installed "$sel" && installed=true
  local state; state=$(read_state)
  local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$sel\".enabled // false")
  echo ""
  echo -e "  Status: $($installed && echo "${GREEN}Installed${NC}" || echo "${RED}Not installed${NC}") | $([[ "$enabled_str" == "true" ]] && echo "${GREEN}Enabled${NC}" || echo "${YELLOW}Disabled${NC}")"
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_browse_by_category() {
  header
  echo -e "  ${BOLD}Browse Modules by Category${NC}"
  spacer
  local i=1
  for cat in "${MODULE_CATEGORIES[@]}"; do
    echo -e "  ${CYAN}$i${NC}) $cat"
    i=$((i + 1))
  done
  spacer
  read -rp "$(echo -e "${CYAN}Select category (or Enter to cancel): ${NC}")" sel
  [[ -z "$sel" || ! "$sel" =~ ^[0-9]+$ ]] && return
  [[ "$sel" -lt 1 || "$sel" -gt "${#MODULE_CATEGORIES[@]}" ]] && return

  local selected_cat="${MODULE_CATEGORIES[$((sel-1))]}"
  spacer
  echo -e "  ${BOLD}Category: ${CYAN}$selected_cat${NC}"
  spacer
  local state; state=$(read_state)
  for id in "${MODULE_IDS[@]}"; do
    if [[ "${MODULE_CATEGORY[$id]}" == "$selected_cat" ]]; then
      local name="${MODULE_DESC[$id]%% *}"
      local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
      local installed=false; is_module_installed "$id" && installed=true
      local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
      if $installed && [[ "$enabled_str" == "true" ]]; then
        echo -e "  ${GREEN}[●]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
      elif $installed; then
        echo -e "  ${YELLOW}[○]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  ${YELLOW}(disabled)${NC}"
      else
        echo -e "  ${DIM}[ ]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  (not installed)${NC}"
      fi
    fi
  done
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_search_modules() {
  header
  echo -e "  ${BOLD}Search Modules${NC}"
  spacer
  read -rp "$(echo -e "${CYAN}Search query: ${NC}")" query
  [[ -z "$query" ]] && return

  local state; state=$(read_state)
  local found=0
  spacer
  for id in "${MODULE_IDS[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    local tags="${MODULE_TAGS[$id]}"
    local cat="${MODULE_CATEGORY[$id]}"
    if echo "$name $desc $tags $cat" | grep -iq "$query"; then
      found=1
      local installed=false; is_module_installed "$id" && installed=true
      local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
      if $installed && [[ "$enabled_str" == "true" ]]; then
        echo -e "  ${GREEN}[●]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
      elif $installed; then
        echo -e "  ${YELLOW}[○]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  ${YELLOW}(disabled)${NC}"
      else
        echo -e "  ${DIM}[ ]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  (not installed)${NC}"
      fi
    fi
  done
  [[ $found -eq 0 ]] && warn "No modules match '$query'."
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_validate() {
  header
  echo -e "  ${BOLD}Module State Validation${NC}"
  spacer
  local state; state=$(read_state)
  local issues=0

  for id in "${MODULE_IDS[@]}"; do
    local enabled; enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled" != "true" ]] && continue
    local name="${MODULE_DESC[$id]%% *}"
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"

    if [[ ! -f "$dest_dir/$filename" ]]; then
      warn "$name (id: $id) — enabled but file missing"
      issues=$((issues + 1))
    fi

    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_enabled; dep_enabled=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
        [[ "$dep_enabled" != "true" ]] && { warn "$name — depends on $(get_module_name $dep) not enabled"; issues=$((issues + 1)); }
      done
    fi
  done

  if [[ $issues -eq 0 ]]; then
    ok "Module state is valid."
  else
    warn "Found $issues issue(s)."
  fi

  spacer
  local total; total=$(echo "$state" | jq 'length')
  local enabled_count; enabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == true)] | length')
  local disabled_count; disabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == false)] | length')
  echo -e "  Total in state: $total  |  Enabled: ${GREEN}$enabled_count${NC}  |  Disabled: ${YELLOW}$disabled_count${NC}"
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

tty_verify_modules() {
  header
  echo -e "  ${BOLD}Verify Loaded Modules${NC}"
  spacer
  echo -e "  ${DIM}This checks that enabled modules are actually active on the system.${NC}"
  spacer
  read -rp "$(echo -e "${CYAN}Run verification? (Y/n): ${NC}")" confirm
  shopt -s nocasematch
  [[ "$confirm" == "n" ]] && { shopt -u nocasematch; return; }
  shopt -u nocasematch
  spacer
  bash "$BASE/files/bin/atlas-module-verify.sh" || true
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Browse by Category ────────────────────────────────────────────────────
browse_by_category() {
  header
  echo -e "  ${BOLD}Browse Modules by Category${NC}"
  spacer

  local cats=(${MODULE_CATEGORIES[@]})
  local i=1
  for cat in "${cats[@]}"; do
    echo -e "  ${CYAN}$i${NC}) $cat"
    i=$((i + 1))
  done
  spacer
  read -rp "$(echo -e "${CYAN}Select category (or Enter to cancel): ${NC}")" sel

  if [[ -z "$sel" ]]; then return; fi
  if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "${#cats[@]}" ]]; then
    local selected_cat="${cats[$((sel-1))]}"
    header
    echo -e "  ${BOLD}Category: ${CYAN}$selected_cat${NC}"
    spacer
    local state; state=$(read_state)
    local found=0
    for id in "${MODULE_IDS[@]}"; do
      if [[ "${MODULE_CATEGORY[$id]}" == "$selected_cat" ]]; then
        found=1
        local name="${MODULE_DESC[$id]%% *}"
        local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
        local file="${MODULE_FILE[$id]}"
        local fn; fn=$(basename "$file")
        local subdir="${MODULE_SUBDIR[$id]}"
        local dest_dir; dest_dir="$(get_module_dir "$subdir")"
        local installed=false; [[ -f "$dest_dir/$fn" ]] && installed=true
        local enabled=false
        local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
        [[ "$enabled_str" == "true" ]] && enabled=true

        if $installed && $enabled; then
          echo -e "  ${GREEN}[●]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
        elif $installed && ! $enabled; then
          echo -e "  ${YELLOW}[○]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  ${YELLOW}(disabled)${NC}"
        else
          echo -e "  ${DIM}[ ]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  (not installed)${NC}"
        fi
      fi
    done
    [[ $found -eq 0 ]] && warn "No modules in this category."
  fi
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Search Modules ─────────────────────────────────────────────────────────
search_modules() {
  header
  echo -e "  ${BOLD}Search Modules${NC}"
  spacer
  read -rp "$(echo -e "${CYAN}Search query: ${NC}")" query
  if [[ -z "$query" ]]; then return; fi

  local state; state=$(read_state)
  local found=0
  for id in "${MODULE_IDS[@]}"; do
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    local tags="${MODULE_TAGS[$id]}"
    local cat="${MODULE_CATEGORY[$id]}"
    if echo "$name $desc $tags $cat" | grep -iq "$query"; then
      found=1
      local status_text
      status_text=$(get_module_status "$id" | sed 's/\x1b\[[0-9;]*m//g' | xargs)
      echo -e "  ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
      echo -e "       ${DIM}Status: $status_text | Category: $cat | Tags: $tags${NC}"
    fi
  done
  [[ $found -eq 0 ]] && warn "No modules match '$query'."
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Validate and Report ────────────────────────────────────────────────────
validate_and_report() {
  header
  echo -e "  ${BOLD}Module State Validation${NC}"
  spacer
  local state; state=$(read_state)
  local issues=0

  for id in "${MODULE_IDS[@]}"; do
    local enabled
    enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled" != "true" ]] && continue

    local name="${MODULE_DESC[$id]%% *}"
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"

    # Check file exists
    if [[ ! -f "$dest_dir/$filename" ]]; then
      warn "$name (id: $id) — enabled but file missing"
      issues=$((issues + 1))
    fi

    # Check dependencies
    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_enabled
        dep_enabled=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
        if [[ "$dep_enabled" != "true" ]]; then
          warn "$name — depends on $(get_module_name $dep) which is not enabled"
          issues=$((issues + 1))
        fi
      done
    fi
  done

  if [[ $issues -eq 0 ]]; then
    ok "Module state is valid — all dependencies satisfied."
  else
    warn "Found $issues issue(s). Run 'atlas-module fix' to resolve."
  fi

  # Show summary
  spacer
  local total=$(echo "$state" | jq 'length')
  local enabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == true)] | length')
  local disabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == false)] | length')
  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    Total in state:     ${CYAN}$total${NC}"
  echo -e "    Enabled:            ${GREEN}$enabled_count${NC}"
  echo -e "    Disabled:           ${YELLOW}$disabled_count${NC}"
  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Detailed Module Status ────────────────────────────────────────────────
check_status() {
  header
  echo -e "  ${BOLD}Module Status${NC}"
  spacer

  local state
  state=$(read_state)
  local any_installed=false
  local has_detail=${DETAIL_VIEW:-0}

  for id in "${MODULE_IDS[@]}"; do
    local name desc
    name="${MODULE_DESC[$id]%% *}"
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"
    local installed=false
    [[ -f "$dest_dir/$filename" ]] && installed=true

    local enabled=false
    local enabled_str
    enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled_str" == "true" ]] && enabled=true

    if $installed; then
      any_installed=true
      if $enabled; then
        echo -e "  ${GREEN}[●]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}"
      else
        echo -e "  ${YELLOW}[○]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc${NC}  ${YELLOW}(disabled)${NC}"
      fi
      if [[ $has_detail -eq 1 ]]; then
        local version="${MODULE_VERSION[$id]}"
        local deps="${MODULE_DEPS[$id]}"
        local cat="${MODULE_CATEGORY[$id]}"
        local tags="${MODULE_TAGS[$id]}"
        echo -e "       ${DIM}v$version | $cat | tags: $tags${NC}"
        if [[ -n "$deps" ]]; then
          local dep_names=""
          for d in $deps; do dep_names+="$(get_module_name $d) "; done
          echo -e "       ${DIM}deps: $dep_names${NC}"
        fi
      fi
    else
      echo -e "  ${DIM}[ ]${NC} ${CYAN}$id${NC}) ${BOLD}$name${NC} — ${DIM}$desc  (not installed)${NC}"
    fi
  done

  spacer
  if ! $any_installed; then
    warn "No modules installed. Use option 3 to download modules."
  fi
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Browse Modules (fzf-based) ────────────────────────────────────────────
browse_modules() {
  header
  echo -e "  ${BOLD}Browse Optional Modules${NC}"
  spacer

  local state
  state=$(read_state)

  for id in "${MODULE_IDS[@]}"; do
    local name desc cat info_text status_text deps
    name=$(get_module_name "$id")
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    cat="${MODULE_CATEGORY[$id]}"
    info_text="${MODULE_INFO[$id]}"
    deps="${MODULE_DEPS[$id]:-}"
    status_text=$(get_module_status "$id" | sed 's/\x1b\[[0-9;]*m//g' | xargs)

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$id" "$name" "$desc" "$cat" "$info_text" "$deps"
  done | fzf \
    --header "Module Browser | Esc: back" \
    --prompt "Search modules > " \
    --delimiter="\t" \
    --with-nth=1,2,3,4 \
    --preview "
      echo -e '\033[1;36mModule Information\033[0m'
      echo -e '\033[2m─────────────────────────────\033[0m'
      echo ''
      echo -e '  \033[1mID:\033[0m          {1}'
      echo -e '  \033[1mName:\033[0m        {2}'
      echo -e '  \033[1mDescription:\033[0m  {3}'
      echo -e '  \033[1mCategory:\033[0m     {4}'
      echo -e '  \033[1mDependencies:\033[0m {6}'
      echo ''
      echo -e '  {5}' | fold -w 50 | sed 's/^/  /'
      echo ''
      echo -e '\033[2mPress ? for keybindings\033[0m'
    " \
    --bind "enter:accept" \
    --bind "esc:cancel" \
    --bind "?:toggle-preview" \
    --cycle \
    2>/dev/null || true

  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}




# ─── Install Modules ────────────────────────────────────────────────────────
install_modules() {
  header
  echo -e "  ${BOLD}Download & Install Modules${NC}"
  spacer
  echo -e "  ${DIM}Select modules to download and install (multi-select with TAB)${NC}"
  spacer

  local state
  state=$(read_state)

  local fzf_input=""
  for id in "${MODULE_IDS[@]}"; do
    local name desc cat info_text
    name=$(get_module_name "$id")
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    cat="${MODULE_CATEGORY[$id]}"
    info_text="${MODULE_INFO[$id]}"

    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    local status=""
    if [[ -f "$dest_dir/$filename" ]]; then
      local enabled_str
      enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
      if [[ "$enabled_str" == "true" ]]; then
        status="INSTALLED+ENABLED"
      else
        status="INSTALLED+DISABLED"
      fi
    else
      status="NOT INSTALLED"
    fi

    local deps="${MODULE_DEPS[$id]:-}"

    fzf_input+="$id | $name | $status | $cat | $deps | $info_text"$'\n'
  done

  local selected
  selected=$(echo "$fzf_input" | \
    fzf --multi \
        --header "TAB: toggle | Enter: confirm | Esc: cancel" \
        --prompt "Select modules to install > " \
        --delimiter="|" \
        --with-nth=1,2,3,4 \
        --preview "
          echo -e '\033[1;36mModule Information\033[0m'
          echo -e '\033[2m─────────────────────────────\033[0m'
          echo ''
          echo -e '  \033[1mID:\033[0m           {1}'
          echo -e '  \033[1mName:\033[0m         {2}'
          echo -e '  \033[1mCategory:\033[0m      {4}'
          echo -e '  \033[1mDependencies:\033[0m  {5}'
          echo ''
          echo -e '  {6}' | fold -w 55 | sed 's/^/  /'
        " \
        --bind "enter:accept" \
        --bind "esc:cancel" \
        --cycle \
        2>/dev/null || true)

  if [[ -z "$selected" ]]; then
    warn "No modules selected."
    sleep 1
    return
  fi

  spacer
  info "Downloading selected modules..."
  spacer

  local module_re="^[0-9]+"
  local dl_fail=0

  while IFS= read -r line; do
    local id
    id=$(echo "$line" | cut -d'|' -f1 | xargs)
    id=$(echo "$id" | grep -oE '^[0-9]+' || echo "")

    [[ -z "$id" ]] && continue

    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    printf "  ${CYAN}→${NC} Downloading ${BOLD}%s${NC} ... " "${MODULE_DESC[$id]%% *}"
    if download_module "$id" "$dest_dir"; then
      ok "Downloaded $filename"
    else
      fail "Failed to download $filename"
      dl_fail=1
    fi
  done <<< "$selected"

  # Check dependencies and resolve deps
  spacer
  info "Checking dependencies..."
  local new_state
  new_state=$(read_state)
  while IFS= read -r line; do
    local id
    id=$(echo "$line" | cut -d'|' -f1 | xargs)
    id=$(echo "$id" | grep -oE '^[0-9]+' || echo "")
    [[ -z "$id" ]] && continue

    # Enable the module in state
    new_state=$(echo "$new_state" | jq ".\"$id\".enabled = true | .\"$id\".installed = true | .\"$id\".source = \"$ATLAS_MODULES_RAW_URL\" | .\"$id\".version = \"${MODULE_VERSION[$id]}\"")

    # Resolve dependencies
    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_file="${MODULE_FILE[$dep]}"
        local dep_filename; dep_filename=$(basename "$dep_file")
        local dep_subdir="${MODULE_SUBDIR[$dep]}"
        local dep_dest
        dep_dest="$(get_module_dir "$dep_subdir")"

        if [[ ! -f "$dep_dest/$dep_filename" ]]; then
          printf "  ${CYAN}→${NC} Installing dependency ${BOLD}${MODULE_DESC[$dep]%% *}${NC} ... "
          if download_module "$dep" "$dep_dest"; then
            ok "Downloaded $dep_filename"
            new_state=$(echo "$new_state" | jq ".\"$dep\".enabled = true | .\"$dep\".installed = true | .\"$dep\".source = \"$ATLAS_MODULES_RAW_URL\" | .\"$dep\".version = \"${MODULE_VERSION[$dep]}\"")
          fi
        else
          ok "Dependency ${MODULE_DESC[$dep]%% *} already installed"
          new_state=$(echo "$new_state" | jq ".\"$dep\".enabled = true")
        fi
      done
    fi
  done <<< "$selected"

  write_state "$new_state"

  spacer
  if [[ $dl_fail -eq 0 ]]; then
    ok "All modules downloaded successfully."
    echo -e "  ${DIM}Run option 6 to apply changes and rebuild.${NC}"
  else
    warn "Some modules failed to download. Check your network connection."
  fi
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Update Modules ─────────────────────────────────────────────────────────
update_modules() {
  header
  echo -e "  ${BOLD}Update All Modules${NC}"
  spacer

  local updated=0
  local failed=0

  for id in "${MODULE_IDS[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    if [[ -f "$dest_dir/$filename" ]]; then
      printf "  ${CYAN}→${NC} Updating ${BOLD}%s${NC} ... " "${MODULE_DESC[$id]%% *}"
      # Backup current
      cp "$dest_dir/$filename" "$dest_dir/.${filename}.bak" 2>/dev/null || true
      if download_module "$id" "$dest_dir"; then
        ok "Updated"
        # Update state version
        local state
        state=$(read_state)
        state=$(echo "$state" | jq ".\"$id\".version = \"${MODULE_VERSION[$id]}\"")
        write_state "$state"
        updated=$((updated + 1))
        rm -f "$dest_dir/.${filename}.bak"
      else
        # Restore backup on failure
        if [[ -f "$dest_dir/.${filename}.bak" ]]; then
          mv "$dest_dir/.${filename}.bak" "$dest_dir/$filename"
        fi
        fail "Update failed (kept previous version)"
        failed=$((failed + 1))
      fi
    fi
  done

  spacer
  if [[ $updated -gt 0 ]]; then
    ok "Updated $updated module(s)."
  fi
  if [[ $failed -gt 0 ]]; then
    warn "$failed module(s) failed to update."
  fi
  if [[ $updated -eq 0 && $failed -eq 0 ]]; then
    info "No modules installed — nothing to update."
  fi
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Remove Modules ─────────────────────────────────────────────────────────
remove_modules() {
  header
  echo -e "  ${BOLD}Remove Modules${NC}"
  spacer
  echo -e "  ${YELLOW}Select modules to remove (multi-select with TAB)${NC}"
  spacer

  local state
  state=$(read_state)

  # Build list of installed modules
  local fzf_input=""
  for id in "${MODULE_IDS[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    if [[ -f "$dest_dir/$filename" ]]; then
      local name="${MODULE_DESC[$id]%% *}"
      local desc="${MODULE_DESC[$id]#* }"
      local enabled_str
      enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
      local status="ENABLED"
      [[ "$enabled_str" != "true" ]] && status="DISABLED"
      fzf_input+="$id | $name | $status | $desc"$'\n'
    fi
  done

  if [[ -z "$fzf_input" ]]; then
    info "No modules installed."
    spacer
    read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
    return
  fi

  local selected
  selected=$(echo "$fzf_input" | \
    fzf --multi \
        --header "TAB: toggle | Enter: confirm removal | Esc: cancel" \
        --prompt "Select modules to remove > " \
        --delimiter="|" \
        --with-nth=1,2,3,4 \
        --bind "enter:accept" \
        --bind "esc:cancel" \
        --cycle \
        2>/dev/null || true)

  if [[ -z "$selected" ]]; then
    warn "No modules selected."
    sleep 1
    return
  fi

  spacer
  warn "${BOLD}Warning: Removing modules will delete their files.${NC}"
  read -rp "$(echo -e "${YELLOW}  Are you sure? (y/N): ${NC}")" confirm
  shopt -s nocasematch
  if [[ "$confirm" != "y" ]]; then
    shopt -u nocasematch
    info "Cancelled."
    sleep 1
    return
  fi
  shopt -u nocasematch

  local new_state="$state"

  while IFS= read -r line; do
    local id
    id=$(echo "$line" | cut -d'|' -f1 | xargs)
    id=$(echo "$id" | grep -oE '^[0-9]+' || echo "")
    [[ -z "$id" ]] && continue

    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    if rm -f "$dest_dir/$filename"; then
      ok "Removed ${MODULE_DESC[$id]%% *}"
      new_state=$(echo "$new_state" | jq "del(.\"$id\")")
    else
      fail "Failed to remove ${MODULE_DESC[$id]%% *}"
    fi
  done <<< "$selected"

  write_state "$new_state"

  spacer
  info "Module files removed. Run option 6 to apply changes."
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Apply Changes ─────────────────────────────────────────────────────────
apply_changes() {
  header
  echo -e "  ${BOLD}Apply Changes & Rebuild${NC}"
  spacer

  local state
  state=$(read_state)
  local enabled_count
  enabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == true)] | length')

  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    Enabled modules:    ${CYAN}$enabled_count${NC}"
  echo -e "    Configuration:      ${DIM}$BASE${NC}"
  echo -e "    Flake target:       ${DIM}#atlas${NC}"
  spacer

  read -rp "$(echo -e "${YELLOW}  Run nixos-rebuild switch now? (y/N): ${NC}")" confirm
  shopt -s nocasematch
  if [[ "$confirm" != "y" ]]; then
    shopt -u nocasematch
    info "Cancelled. You can rebuild manually:"
    echo -e "       ${DIM}sudo nixos-rebuild switch --flake $BASE#atlas${NC}"
    sleep 1
    return
  fi
  shopt -u nocasematch

  spacer
  echo -e "  ${YELLOW}Running nixos-rebuild switch...${NC}"
  echo -e "  ${DIM}(This may take several minutes)${NC}"
  spacer

  # Stop tamper-detection services before rebuild (following atlas-rebuild pattern)
  sudo systemctl stop \
    snort-daemon snort-monitor \
    snout-watcher.service snout-watcher.path \
    aide-check.service aide-check.timer \
    firmware-version-check \
    tpm-attestation-check \
    secureboot-verify 2>/dev/null || true

  sudo nixos-rebuild switch --flake "$BASE#atlas" 2>&1 | tee /tmp/atlas-module-rebuild.log
  local rebuild_exit=${PIPESTATUS[0]}
  if [[ $rebuild_exit -eq 0 ]]; then
    ok "Rebuild successful!"
    local updated_state
    updated_state=$(read_state)
    updated_state=$(echo "$updated_state" | jq --arg now "$(date -Iseconds)" '.metadata.last_rebuild = $now')
    write_state "$updated_state"
  else
    fail "Rebuild failed (exit $rebuild_exit). Check /tmp/atlas-module-rebuild.log"
  fi

  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Module Info ────────────────────────────────────────────────────────────
module_info() {
  header
  echo -e "  ${BOLD}Module Information${NC}"
  spacer
  echo -e "  ${DIM}Select a module to view its details${NC}"
  spacer

  local fzf_input=""
  for id in "${MODULE_IDS[@]}"; do
    local name desc cat file subdir version deps info_text
    name=$(get_module_name "$id")
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    cat="${MODULE_CATEGORY[$id]}"
    file="${MODULE_FILE[$id]}"
    subdir="${MODULE_SUBDIR[$id]}"
    version="${MODULE_VERSION[$id]}"
    deps="${MODULE_DEPS[$id]:--}"
    info_text="${MODULE_INFO[$id]}"
    fzf_input+="$id | $name | $desc | $cat | $subdir | $version | $deps | $info_text | $file"$'\n'
  done

  local selected
  selected=$(echo "$fzf_input" | \
    fzf \
        --header "Select a module | Enter: view details | Esc: back" \
        --prompt "Search > " \
        --delimiter="|" \
        --with-nth=1,2,3 \
        --preview "
          echo -e '\033[1;36m═══════════════════════════════════════\033[0m'
          echo -e ' \033[1mModule Details\033[0m'
          echo -e '\033[1;36m═══════════════════════════════════════\033[0m'
          echo ''
          echo -e '  ID:         \033[1m{1}\033[0m'
          echo -e '  Name:       {2}'
          echo -e '  Category:   {4}'
          echo -e '  Type:       {5}'
          echo -e '  Version:    {6}'
          echo -e '  Deps:       {7}'
          echo -e '  File:       {9}'
          echo ''
          echo -e '  \033[1mDescription:\033[0m'
          echo -e '  {8}' | fold -w 55 | sed 's/^/  /'
          echo ''
          echo -e '  Source:     ${ATLAS_MODULES_RAW_URL}/{9}'
        " \
        --bind "enter:accept" \
        --bind "esc:cancel" \
        --cycle \
        2>/dev/null || true)

  if [[ -n "$selected" ]]; then
    spacer
    read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═════════════════════════════════════════════════════════════════════════════

# Check if running as root (not recommended for interactive use)
if [[ $EUID -eq 0 ]]; then
  echo -e "${YELLOW}Warning: Running as root. Prefer running as a regular user.${NC}"
  sleep 1
fi

# Ensure state directory exists
ensure_state

# Launch the appropriate menu based on available backends
case "$UI_BACKEND" in
  fzf|gum)
    main_menu
    ;;
  dialog|whiptail|tty)
    tty_main_menu
    ;;
  *)
    info "No TUI backend found. Using basic TTY interface."
    tty_main_menu
    ;;
esac
