#!/usr/bin/env bash
# ============================================================================
# ATLAS MODULE APPLY — Apply changes and rebuild
# ============================================================================
# Applies module state changes and runs nixos-rebuild switch.
# Can also check for module updates.
#
# Usage:
#   atlas-module-apply              # Apply changes and rebuild
#   atlas-module-apply --check-updates  # Check for module updates only
#   atlas-module-apply --status     # Show module state summary
# ============================================================================
set -euo pipefail

BASE="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$BASE/files/lib/logging.sh"
source "$BASE/files/lib/module-registry.sh"
ATLAS_MODULES_BASE="$BASE"

# ─── Validate State ────────────────────────────────────────────────────────
validate_state() {
  if [[ ! -f "$ATLAS_MODULE_STATE_FILE" ]]; then
    fail "Module state file not found at $ATLAS_MODULE_STATE_FILE"
    info "Run 'atlas-module-manager' to configure modules first."
    exit 1
  fi

  local state
  state=$(jq -c '.modules' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null || echo "{}")
  local issues=0

  for id in "${MODULE_IDS[@]}"; do
    local enabled
    enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    if [[ "$enabled" != "true" ]]; then
      continue
    fi

    local name="${MODULE_DESC[$id]%% *}"

    # Check dependencies
    local deps="${MODULE_DEPS[$id]}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_enabled
        dep_enabled=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
        if [[ "$dep_enabled" != "true" ]]; then
          warn "Module $name depends on ${MODULE_DESC[$dep]%% *} which is not enabled"
          issues=1
        fi
      done
    fi

    # Check file exists
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"
    if [[ ! -f "$dest_dir/$filename" ]]; then
      warn "Module $name is enabled but file $filename is missing"
      issues=1
    fi
  done

  if [[ $issues -gt 0 ]]; then
    echo ""
    warn "Found $issues validation issue(s). Fix them before rebuilding."
    echo -e "  ${DIM}Run 'atlas-module validate' for details.${NC}"
    return 1
  fi

  return 0
}

# ─── Dry Run ──────────────────────────────────────────────────────────────
dry_run() {
  echo -e "${CYAN}════════════════════════════════════════${NC}"
  echo -e "${CYAN}  Atlas Module Apply — Dry Run${NC}"
  echo -e "${CYAN}════════════════════════════════════════${NC}"
  echo ""

  local state
  state=$(jq -c '.modules' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null || echo "{}")

  echo -e "  ${BOLD}Would rebuild with:${NC}"
  local count=0
  for id in "${MODULE_IDS[@]}"; do
    local enabled
    enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    if [[ "$enabled" == "true" ]]; then
      local name="${MODULE_DESC[$id]%% *}"
      local version="${MODULE_VERSION[$id]}"
      echo -e "    ${GREEN}+${NC} ${CYAN}$id${NC} $name ${DIM}(v$version)${NC}"
      count=$((count + 1))
    fi
  done
  echo -e "    ${DIM}Total: $count enabled module(s)${NC}"
  echo ""

  local enabled_count
  enabled_count=$(echo "$state" | jq '[to_entries[] | select(.value.enabled == true)] | length')
  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    Enabled modules:    ${CYAN}$enabled_count${NC}"
  echo -e "    Flake target:       ${DIM}#atlas${NC}"
  echo ""
  echo -e "  ${YELLOW}This is a dry run. No changes were made.${NC}"
}

# ─── Check Updates ──────────────────────────────────────────────────────────
check_updates() {
  info "Checking for module updates..."
  local available=0

  for id in "${MODULE_IDS[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    if [[ ! -f "$dest_dir/$filename" ]]; then
      continue
    fi

    # Check if we can reach the remote
    if curl -sI "$ATLAS_MODULES_RAW_URL/$file" >/dev/null 2>&1; then
      available=$((available + 1))
    fi
  done

  info "$available module(s) available for update."
}

# ─── Status Report ─────────────────────────────────────────────────────────
status_report() {
  if [[ ! -f "$ATLAS_MODULE_STATE_FILE" ]]; then
    info "No module state file found."
    echo -e "  ${DIM}Run 'atlas-module-manager' to configure modules.${NC}"
    exit 0
  fi

  local state
  state=$(jq -c '.modules' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null || echo "{}")
  local enabled=0
  local disabled=0
  local installed=0

  for id in "${MODULE_IDS[@]}"; do
    local file="${MODULE_FILE[$id]}"
    local filename; filename=$(basename "$file")
    local subdir="${MODULE_SUBDIR[$id]}"
    local dest_dir
    dest_dir="$(get_module_dir "$subdir")"

    if [[ -f "$dest_dir/$filename" ]]; then
      installed=$((installed + 1))
      local enabled_str
      enabled_str=$(echo "$state" | jq -r ".\"$id\".enabled // false")
      if [[ "$enabled_str" == "true" ]]; then
        enabled=$((enabled + 1))
      else
        disabled=$((disabled + 1))
      fi
    fi
  done

  echo -e "  ${BOLD}Module Status:${NC}"
  echo -e "    Installed:  ${CYAN}$installed${NC}"
  echo -e "    Enabled:    ${GREEN}$enabled${NC}"
  echo -e "    Disabled:   ${YELLOW}$disabled${NC}"
  echo -e "    State file: ${DIM}$ATLAS_MODULE_STATE_FILE${NC}"
  echo -e "    Last rebuild: ${DIM}$(jq -r '.metadata.last_rebuild // "never"' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null)${NC}"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

case "${1:-apply}" in
  --check-updates)
    check_updates
    ;;
  --status)
    status_report
    ;;
  --validate)
    validate_state
    if [[ $? -eq 0 ]]; then
      ok "Module state is valid."
    fi
    ;;
  --dry-run)
    dry_run
    ;;
  apply|"")
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Atlas Module Apply${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""

    validate_state || exit 1

    info "Stopping tamper-detection services..."
    sudo systemctl stop \
      snort-daemon snort-monitor \
      snout-watcher.service snout-watcher.path \
      aide-check.service aide-check.timer \
      firmware-version-check \
      tpm-attestation-check \
      secureboot-verify 2>/dev/null || true
    ok "Services stopped"

    echo ""
    info "Running nixos-rebuild switch..."
    echo -e "  ${DIM}Flake: $BASE#atlas${NC}"
    echo ""

    if sudo nixos-rebuild switch --flake "$BASE#atlas" 2>&1; then
      echo ""
      ok "Rebuild successful!"

      local state
      state=$(jq -c '.modules' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null || echo "{}")
      jq --arg now "$(date -Iseconds)" \
         --argjson modules "$state" \
         '.modules = $modules | .metadata.last_rebuild = $now | .metadata.updated = $now' \
         "$ATLAS_MODULE_STATE_FILE" > "${ATLAS_MODULE_STATE_FILE}.tmp" && mv "${ATLAS_MODULE_STATE_FILE}.tmp" "$ATLAS_MODULE_STATE_FILE"

      atlas-health quick 2>/dev/null || echo -e "  ${YELLOW}⚠  Health check found issues — run 'atlas-health' for details.${NC}"
    else
      echo ""
      fail "Rebuild failed!"
      exit 1
    fi
    ;;
  *)
    echo "Usage: atlas-module-apply [--check-updates|--status|--validate|--dry-run]"
    exit 1
    ;;
esac
