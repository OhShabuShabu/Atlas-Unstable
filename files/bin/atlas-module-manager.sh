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

# ─── Paths ──────────────────────────────────────────────────────────────────
BASE="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$BASE/files/lib/module-registry.sh"
ATLAS_MODULES_BASE="$BASE"

OPT_NIXOS_DIR="$(get_module_dir nixos)"
OPT_HOME_DIR="$(get_module_dir home)"

# ─── Colors ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

# ─── State File ─────────────────────────────────────────────────────────────
STATE_DIR="/persistent/etc/atlas-modules"
STATE_FILE="$STATE_DIR/state.json"

ensure_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" <<EOF
{
  "modules": {},
  "metadata": {
    "created": "$(date -Iseconds)",
    "updated": "$(date -Iseconds)",
    "version": "1"
  }
}
EOF
  fi
}

read_state() {
  ensure_state
  jq -c '.modules' "$STATE_FILE" 2>/dev/null || echo "{}"
}

write_state() {
  local modules_json="$1"
  jq --arg now "$(date -Iseconds)" \
     --argjson modules "$modules_json" \
     '.modules = $modules | .metadata.updated = $now' \
     "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# ─── UI Helpers ────────────────────────────────────────────────────────────
header() {
  clear
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║               ATLAS MODULE MANAGER                          ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

info()   { echo -e "  ${CYAN}→${NC} $1"; }
ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
spacer() { echo; }

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
      q|Q|quit|exit) clear; exit 0 ;;
      *) warn "Invalid option" && sleep 1 ;;
    esac
  done
}

# ─── Browse Modules (fzf-based) ────────────────────────────────────────────
browse_modules() {
  header
  echo -e "  ${BOLD}Browse Optional Modules${NC}"
  spacer

  local state
  state=$(read_state)

  # Build fzf input: id | name | status | category
  local input=()
  for id in "${MODULE_IDS[@]}"; do
    local name desc cat info_text status_text deps
    name="${MODULE_DESC[$id]%% *}"
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    cat="${MODULE_CATEGORY[$id]}"
    info_text="${MODULE_INFO[$id]}"
    deps="${MODULE_DEPS[$id]}"
    status_text=$(get_module_status "$id" | sed 's/\x1b\[[0-9;]*m//g' | xargs)

    input+=("$id | $name | $status_text | $cat")
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$id" "$name" "$desc" "$cat" "$info_text" "$deps"
  done | fzf \
    --header "Module Browser | TAB: toggle | Enter: toggle & back | Esc: back" \
    --prompt "Search modules > " \
    --delimiter="\t" \
    --with-nth=1,2,3,4 \
    --preload \
    --preview "
      id=\$(echo {} | cut -d' ' -f1)
      echo -e '\033[1;36mModule Information\033[0m'
      echo -e '\033[2m─────────────────────────────\033[0m'
      echo ''
      echo -e '  \033[1mID:\033[0m          \$id'
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
    --bind "ctrl-t:toggle-all" \
    --bind "tab:toggle+down" \
    --cycle \
    2>/dev/null || true

  spacer
  read -rp "$(echo -e "${DIM}Press Enter to continue...${NC}")"
}

# ─── Check Status ───────────────────────────────────────────────────────────
check_status() {
  header
  echo -e "  ${BOLD}Module Status${NC}"
  spacer

  local state
  state=$(read_state)
  local any_installed=false

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

# ─── Install Modules ────────────────────────────────────────────────────────
install_modules() {
  header
  echo -e "  ${BOLD}Download & Install Modules${NC}"
  spacer
  echo -e "  ${DIM}Select modules to download and install (multi-select with TAB)${NC}"
  spacer

  local state
  state=$(read_state)

  # Build fzf multi-select input with current status
  local fzf_input=""
  for id in "${MODULE_IDS[@]}"; do
    local name desc cat
    name="${MODULE_DESC[$id]%% *}"
    desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    cat="${MODULE_CATEGORY[$id]}"

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

    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      deps=" (depends on: $deps)"
    else
      deps=""
    fi

    fzf_input+="$id | $name | $status | $cat$deps"$'\n'
  done

  local selected
  selected=$(echo "$fzf_input" | \
    fzf --multi \
        --header "TAB: toggle | Enter: confirm | Esc: cancel" \
        --prompt "Select modules to install > " \
        --delimiter="|" \
        --with-nth=1,2,3,4 \
        --preview "
          id=\$(echo {} | cut -d'|' -f1 | xargs)
          echo -e '\033[1;36m\${MODULE_INFO[\$id]}\033[0m'
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

  if sudo nixos-rebuild switch --flake "$BASE#atlas" 2>&1 | tee /tmp/atlas-module-rebuild.log; then
    ok "Rebuild successful!"
    # Update state with rebuild timestamp
    local updated_state
    updated_state=$(read_state)
    updated_state=$(echo "$updated_state" | jq --arg now "$(date -Iseconds)" '.metadata.last_rebuild = $now')
    write_state "$updated_state"
  else
    fail "Rebuild failed. Check /tmp/atlas-module-rebuild.log for details."
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
    local name="${MODULE_DESC[$id]%% *}"
    local desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    fzf_input+="$id | $name | $desc"$'\n'
  done

  local selected
  selected=$(echo "$fzf_input" | \
    fzf \
        --header "Select a module | Enter: view details | Esc: back" \
        --prompt "Search > " \
        --delimiter="|" \
        --with-nth=1,2,3 \
        --preview "
          id=\$(echo {} | cut -d'|' -f1 | xargs)
          source '$BASE/files/lib/module-registry.sh'

          echo -e '\033[1;36m═══════════════════════════════════════\033[0m'
          echo -e ' \033[1mModule Details\033[0m'
          echo -e '\033[1;36m═══════════════════════════════════════\033[0m'
          echo ''
          echo -e '  ID:         \033[1m'\$id'\033[0m'
          echo -e '  Name:       \${MODULE_DESC[\$id]%% *}'
          echo -e '  Category:   \${MODULE_CATEGORY[\$id]}'
          echo -e '  File:       \${MODULE_FILE[\$id]}'
          echo -e '  Type:       \${MODULE_SUBDIR[\$id]}'
          echo -e '  Version:    \${MODULE_VERSION[\$id]}'
          echo -e '  Deps:       \${MODULE_DEPS[\$id]:-none}'
          echo ''
          echo -e '  \033[1mDescription:\033[0m'
          echo -e '  \${MODULE_INFO[\$id]}' | fold -w 55 | sed 's/^/  /'
          echo ''
          echo -e '  Source:     ${ATLAS_MODULES_RAW_URL}/\${MODULE_FILE[\$id]}'
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

# Check for fzf dependency
if ! command -v fzf &>/dev/null; then
  echo -e "${RED}Error: fzf is required but not installed.${NC}"
  echo -e "${YELLOW}Install it with: sudo nix-env -iA nixos.fzf${NC}"
  exit 1
fi

# Check if running as root (not recommended for interactive use)
if [[ $EUID -eq 0 ]]; then
  echo -e "${YELLOW}Warning: Running as root. Prefer running as a regular user.${NC}"
  sleep 1
fi

# Ensure state directory exists
ensure_state

# Launch the main menu
main_menu
