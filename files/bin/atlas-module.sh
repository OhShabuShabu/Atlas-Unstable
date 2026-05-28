#!/usr/bin/env bash
# ============================================================================
# ATLAS MODULE — Unified CLI for Module Operations
# ============================================================================
# Unified command-line interface for all module management operations.
# Works entirely from a TTY.
#
# Usage:
#   atlas-module list                        # List all modules with status
#   atlas-module enable <id>                 # Enable a module
#   atlas-module disable <id>                # Disable a module
#   atlas-module install <id> [id ...]       # Download and install modules
#   atlas-module remove <id> [id ...]        # Remove modules
#   atlas-module update [id]                 # Update module(s)
#   atlas-module info <id>                   # Show module details
#   atlas-module status [id]                 # Show module status
#   atlas-module validate                    # Validate module state
#   atlas-module apply                       # Apply changes and rebuild
#   atlas-module search <query>              # Search modules by name/tag
#   atlas-module category <name>             # List modules in category
#   atlas-module verify [id]                 # Verify module(s) are loaded
#   atlas-module tui                         # Launch TTY-friendly TUI (fzf/dialog/whiptail)
# ============================================================================
set -euo pipefail

BASE="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$BASE/files/lib/logging.sh"
source "$BASE/files/lib/module-registry.sh"
ATLAS_MODULES_BASE="$BASE"

cmd_list() {
  local state; state=$(read_state)
  local fmt="${1:-table}"
  echo -e "${BOLD}Module Status:${NC}"
  echo ""
  printf "  ${BOLD}%-3s %-16s %-12s %-10s %s${NC}\n" "ID" "Name" "Status" "Category" "Description"
  echo "  $(printf '%.0s─' {1..75})"
  for id in "${MODULE_IDS[@]}"; do
    local name; name=$(get_module_name "$id")
    local desc="${MODULE_DESC[$id]#* }"
    desc="${desc# }"
    local cat="${MODULE_CATEGORY[$id]}"
    local installed=false; is_module_installed "$id" && installed=true
    local enabled=false
    local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled_str" == "true" ]] && enabled=true
    local status_text
    if $installed && $enabled; then
      status_text="${GREEN}enabled${NC}"
    elif $installed && ! $enabled; then
      status_text="${YELLOW}disabled${NC}"
    else
      status_text="${DIM}not installed${NC}"
    fi
    printf "  ${CYAN}%-3s${NC} %-16s %-20s %-10s %s\n" "$id" "$name" "$status_text" "$cat" "$desc"
  done
}

cmd_enable() {
  local id="$1"
  local state; state=$(read_state)
  local file="${MODULE_FILE[$id]}"
  local filename; filename=$(basename "$file")
  local subdir="${MODULE_SUBDIR[$id]}"
  local dest_dir; dest_dir="$(get_module_dir "$subdir")"

  if [[ ! -f "$dest_dir/$filename" ]]; then
    fail "Module $id ($(get_module_name $id)) is not installed. Install it first."
    return 1
  fi
  # Check and install dependencies
  local deps="${MODULE_DEPS[$id]}"
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      local dep_file="${MODULE_FILE[$dep]}"
      local dep_filename; dep_filename=$(basename "$dep_file")
      local dep_subdir="${MODULE_SUBDIR[$dep]}"
      local dep_dest; dep_dest="$(get_module_dir "$dep_subdir")"
      if [[ ! -f "$dep_dest/$dep_filename" ]]; then
        warn "Dependency $(get_module_name $dep) is missing. Install it first."
        return 1
      fi
      state=$(echo "$state" | jq ".\"$dep\".enabled = true")
    done
  fi
  state=$(echo "$state" | jq ".\"$id\".enabled = true")
  write_state "$state"
  ok "Module $(get_module_name $id) enabled."
}

cmd_disable() {
  local id="$1"
  local state; state=$(read_state)

  # Check reverse dependencies
  local rev_deps
  rev_deps=$(get_reverse_deps "$id")
  if [[ -n "$rev_deps" ]]; then
    local blocking=""
    for rev in $rev_deps; do
      local rev_enabled; rev_enabled=$(echo "$state" | jq -r ".\"$rev\".enabled // false")
      if [[ "$rev_enabled" == "true" ]]; then
        blocking+="  - $(get_module_name $rev) (id: $rev)\n"
      fi
    done
    if [[ -n "$blocking" ]]; then
      warn "Cannot disable $(get_module_name $id): other enabled modules depend on it:"
      echo -e "$blocking"
      return 1
    fi
  fi
  state=$(echo "$state" | jq ".\"$id\".enabled = false")
  write_state "$state"
  ok "Module $(get_module_name $id) disabled."
}

cmd_install() {
  local state; state=$(read_state)
  local dl_fail=0
  for id in "$@"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    printf "  ${CYAN}→${NC} Installing ${BOLD}%s${NC} ... " "$(get_module_name $id)"
    if download_module "$id" "$dest_dir"; then
      ok "$filename"
      state=$(echo "$state" | jq ".\"$id\".enabled = true | .\"$id\".installed = true | .\"$id\".source = \"$ATLAS_MODULES_RAW_URL\" | .\"$id\".version = \"${MODULE_VERSION[$id]}\"")
      # Resolve dependencies
      local deps="${MODULE_DEPS[$id]}"
      if [[ -n "$deps" ]]; then
        for dep in $deps; do
          local dep_file="${MODULE_FILE[$dep]}"
          local dep_fn; dep_fn=$(basename "$dep_file")
          local dep_subdir="${MODULE_SUBDIR[$dep]}"
          local dep_dest; dep_dest="$(get_module_dir "$dep_subdir")"
          if [[ ! -f "$dep_dest/$dep_fn" ]]; then
            printf "  ${CYAN}→${NC} Installing dependency ${BOLD}%s${NC} ... " "$(get_module_name $dep)"
            if download_module "$dep" "$dep_dest"; then
              ok "$dep_fn"
              state=$(echo "$state" | jq ".\"$dep\".enabled = true | .\"$dep\".installed = true | .\"$dep\".version = \"${MODULE_VERSION[$dep]}\"")
            fi
          fi
          state=$(echo "$state" | jq ".\"$dep\".enabled = true")
        done
      fi
    else
      fail "Failed to download $(get_module_name $id)"
      dl_fail=1
    fi
  done
  write_state "$state"
  [[ $dl_fail -eq 0 ]] && ok "All modules installed." || warn "Some modules failed."
}

cmd_remove() {
  local state; state=$(read_state)
  for id in "$@"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    if rm -f "$dest_dir/$filename" 2>/dev/null; then
      state=$(echo "$state" | jq "del(.\"$id\")")
      ok "Removed $(get_module_name $id)"
    else
      fail "Failed to remove $(get_module_name $id)"
    fi
  done
  write_state "$state"
}

cmd_update() {
  local ids=("$@")
  [[ ${#ids[@]} -eq 0 ]] && ids=("${MODULE_IDS[@]}")
  local updated=0 failed=0
  for id in "${ids[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    if [[ -f "$dest_dir/$filename" ]]; then
      printf "  ${CYAN}→${NC} Updating ${BOLD}%s${NC} ... " "$(get_module_name $id)"
      cp "$dest_dir/$filename" "$dest_dir/.${filename}.bak" 2>/dev/null || true
      if download_module "$id" "$dest_dir"; then
        ok "Updated to v${MODULE_VERSION[$id]}"
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
  [[ $updated -gt 0 ]] && ok "Updated $updated module(s)."
  [[ $failed -gt 0 ]] && warn "$failed module(s) failed."
  [[ $updated -eq 0 && $failed -eq 0 ]] && info "No modules to update."
}

cmd_info() {
  local id="$1"
  local state; state=$(read_state)
  local name; name=$(get_module_name "$id")
  local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
  local cat="${MODULE_CATEGORY[$id]}"
  local file="${MODULE_FILE[$id]}"
  local subdir="${MODULE_SUBDIR[$id]}"
  local version="${MODULE_VERSION[$id]}"
  local deps="${MODULE_DEPS[$id]}"
  local info_text="${MODULE_INFO[$id]}"
  local tags="${MODULE_TAGS[$id]}"

  local installed=false; is_module_installed "$id" && installed=true
  local enabled=false
  local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
  [[ "$enabled_str" == "true" ]] && enabled=true

  echo -e "${BOLD}Module: ${CYAN}$name${NC} (id: $id)"
  echo ""
  echo -e "  ${BOLD}Description:${NC}  $desc"
  echo -e "  ${BOLD}Category:${NC}     $cat"
  echo -e "  ${BOLD}Type:${NC}         $subdir"
  echo -e "  ${BOLD}File:${NC}         $file"
  echo -e "  ${BOLD}Version:${NC}      $version"
  echo -e "  ${BOLD}Tags:${NC}         $tags"
  echo ""
  echo -e "  ${BOLD}Status:${NC}"
  $installed && echo -e "    Installed:  ${GREEN}yes${NC}" || echo -e "    Installed:  ${RED}no${NC}"
  $enabled && echo -e "    Enabled:    ${GREEN}yes${NC}" || echo -e "    Enabled:    ${YELLOW}no${NC}"
  echo ""
  echo -e "  ${BOLD}Dependencies:${NC}"
  if [[ -n "$deps" ]]; then
    for dep in $deps; do
      local dep_enabled_str; dep_enabled_str=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
      if [[ "$dep_enabled_str" == "true" ]]; then
        echo -e "    ${GREEN}●${NC} $(get_module_name $dep) (id: $dep)"
      else
        echo -e "    ${YELLOW}○${NC} $(get_module_name $dep) (id: $dep) ${YELLOW}(not enabled)${NC}"
      fi
    done
  else
    echo -e "    ${DIM}(none)${NC}"
  fi

  local rev_deps; rev_deps=$(get_reverse_deps "$id")
  if [[ -n "$rev_deps" ]]; then
    echo ""
    echo -e "  ${BOLD}Used by:${NC}"
    for rev in $rev_deps; do
      echo -e "    ${CYAN}→${NC} $(get_module_name $rev) (id: $rev)"
    done
  fi
  echo ""
  echo -e "  ${BOLD}Details:${NC}"
  echo -e "  $info_text" | fold -w 72 | sed 's/^/  /'
  echo ""
  echo -e "  ${DIM}Source: $ATLAS_MODULES_RAW_URL/$file${NC}"
}

cmd_status() {
  local id="${1:-}"
  if [[ -n "$id" ]]; then
    cmd_info "$id"
    return
  fi
  local state; state=$(read_state)
  local total=0 enabled=0 disabled=0 installed=0
  for id in "${MODULE_IDS[@]}"; do
    total=$((total + 1))
    is_module_installed "$id" && installed=$((installed + 1))
    local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled_str" == "true" ]] && enabled=$((enabled + 1)) || disabled=$((disabled + 1))
  done
  echo -e "${BOLD}Module System Status${NC}"
  echo ""
  echo -e "  ${BOLD}Registry entries:${NC}  $total"
  echo -e "  ${BOLD}Installed:${NC}        ${GREEN}$installed${NC}"
  echo -e "  ${BOLD}Enabled:${NC}          ${GREEN}$enabled${NC}"
  echo -e "  ${BOLD}Disabled:${NC}         ${YELLOW}$disabled${NC}"
  echo ""
  echo -e "  ${BOLD}State file:${NC}       ${DIM}$ATLAS_MODULE_STATE_FILE${NC}"
  local last_rebuild; last_rebuild=$(jq -r '.metadata.last_rebuild // "never"' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null)
  echo -e "  ${BOLD}Last rebuild:${NC}     ${DIM}$last_rebuild${NC}"
  # Dependency validation
  echo ""
  if validate_deps "$state"; then
    ok "All dependencies satisfied."
  else
    warn "Dependency issues found."
  fi
}

cmd_validate() {
  local state; state=$(read_state)
  local issues=0
  for id in "${MODULE_IDS[@]}"; do
    local enabled; enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled" != "true" ]] && continue
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir; dest_dir="$(get_module_dir "$subdir")"
    if [[ ! -f "$dest_dir/$filename" ]]; then
      warn "Module $(get_module_name $id) is enabled but file $filename is missing"
      issues=1
    fi
    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_enabled; dep_enabled=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
        if [[ "$dep_enabled" != "true" ]]; then
          warn "Module $(get_module_name $id) depends on $(get_module_name $dep) which is not enabled"
          issues=1
        fi
      done
    fi
  done
  if [[ $issues -eq 0 ]]; then
    ok "Module state is valid."
  else
    warn "Validation found issues. Run 'atlas-module-manager' to fix them."
    return 1
  fi
}

cmd_search() {
  local query="$1"
  local state; state=$(read_state)
  echo -e "${BOLD}Search results for:${NC} ${CYAN}$query${NC}"
  echo ""
  local found=0
  for id in "${MODULE_IDS[@]}"; do
    local name; name=$(get_module_name "$id")
    local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
    local tags="${MODULE_TAGS[$id]}"
    local cat="${MODULE_CATEGORY[$id]}"
    if echo "$name $desc $tags $cat" | grep -iq "$query"; then
      local status_text
      if is_module_installed "$id"; then
        local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
        [[ "$enabled_str" == "true" ]] && status_text="${GREEN}enabled${NC}" || status_text="${YELLOW}disabled${NC}"
      else
        status_text="${DIM}not installed${NC}"
      fi
      printf "  ${CYAN}%-3s${NC} %-16s %-20s %s\n" "$id" "$name" "$status_text" "$desc"
      found=1
    fi
  done
  [[ $found -eq 0 ]] && warn "No modules match '$query'."
}

cmd_category() {
  local cat_name="$1"
  local state; state=$(read_state)
  echo -e "${BOLD}Category:${NC} ${CYAN}$cat_name${NC}"
  echo ""
  local found=0
  for id in "${MODULE_IDS[@]}"; do
    if [[ "${MODULE_CATEGORY[$id]}" == "$cat_name" ]]; then
      local name; name=$(get_module_name "$id")
      local desc="${MODULE_DESC[$id]#* }"; desc="${desc# }"
      local status_text
      if is_module_installed "$id"; then
        local enabled_str; enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
        [[ "$enabled_str" == "true" ]] && status_text="${GREEN}enabled${NC}" || status_text="${YELLOW}disabled${NC}"
      else
        status_text="${DIM}not installed${NC}"
      fi
      printf "  ${CYAN}%-3s${NC} %-16s %-20s %s\n" "$id" "$name" "$status_text" "$desc"
      found=1
    fi
  done
  [[ $found -eq 0 ]] && warn "No modules in category '$cat_name'."
  echo ""
  echo -e "  ${DIM}Available categories: ${CYAN}${MODULE_CATEGORIES[*]}${NC}${NC}"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
ensure_state

case "${1:-help}" in
  list|ls)
    cmd_list "${2:-}"
    ;;
  enable)
    [[ -z "${2:-}" ]] && { fail "Usage: atlas-module enable <id>"; exit 1; }
    cmd_enable "$2"
    ;;
  disable)
    [[ -z "${2:-}" ]] && { fail "Usage: atlas-module disable <id>"; exit 1; }
    cmd_disable "$2"
    ;;
  install)
    shift; [[ $# -eq 0 ]] && { fail "Usage: atlas-module install <id> [id ...]"; exit 1; }
    cmd_install "$@"
    ;;
  remove|rm)
    shift; [[ $# -eq 0 ]] && { fail "Usage: atlas-module remove <id> [id ...]"; exit 1; }
    cmd_remove "$@"
    ;;
  update)
    shift; cmd_update "$@"
    ;;
  info)
    [[ -z "${2:-}" ]] && { fail "Usage: atlas-module info <id>"; exit 1; }
    cmd_info "$2"
    ;;
  status)
    cmd_status "${2:-}"
    ;;
  validate)
    cmd_validate
    ;;
  apply)
    exec atlas-module-apply
    ;;
  search)
    [[ -z "${2:-}" ]] && { fail "Usage: atlas-module search <query>"; exit 1; }
    cmd_search "$2"
    ;;
  category|cat)
    [[ -z "${2:-}" ]] && { fail "Usage: atlas-module category <name>"; exit 1; }
    cmd_category "$2"
    ;;
  verify)
    exec atlas-module-verify "${2:-}"
    ;;
  tui)
    exec atlas-module-manager
    ;;
  help|--help|-h)
    echo "Usage: atlas-module <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list                    List all modules with status"
    echo "  enable <id>            Enable a module"
    echo "  disable <id>           Disable a module"
    echo "  install <id> [...]     Download and install modules"
    echo "  remove <id> [...]      Remove modules"
    echo "  update [id]            Update module(s)"
    echo "  info <id>              Show module details"
    echo "  status [id]            Show module status"
    echo "  validate               Validate module state"
    echo "  apply                  Apply changes and rebuild"
    echo "  search <query>         Search modules"
    echo "  category <name>        List modules in category"
    echo "  verify [id]            Verify module(s) are loaded on system"
    echo "  tui                    Launch TTY-friendly TUI interface"
    ;;
  *)
    fail "Unknown command: $1"
    echo "Usage: atlas-module <command> [args]"
    exit 1
    ;;
esac
