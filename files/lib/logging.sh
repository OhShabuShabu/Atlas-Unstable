#!/usr/bin/env bash
# ============================================================================
# ATLAS SHARED LOGGING LIBRARY
# ============================================================================
# Standardized logging and output formatting for all Atlas scripts.
# Provides consistent colors, status indicators, and output formatting.
#
# Usage: source files/lib/logging.sh
# ============================================================================

# ─── Color Constants ──────────────────────────────────────────────────────
export RED=$'\033[0;31m'
export GREEN=$'\033[0;32m'
export YELLOW=$'\033[1;33m'
export CYAN=$'\033[0;36m'
export BLUE=$'\033[0;34m'
export BOLD=$'\033[1m'
export DIM=$'\033[2m'
export NC=$'\033[0m'

# ─── Status Output ────────────────────────────────────────────────────────
info()   { echo -e "  ${CYAN}→${NC} $1"; }
ok()     { echo -e "  ${GREEN}✓${NC} $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; }
spacer() { echo; }

# ─── Header Output ────────────────────────────────────────────────────────
log_header() {
  echo -e "\n${CYAN}════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}════════════════════════════════════════${NC}"
}

log_subheader() {
  echo -e "\n  ${BOLD}$1${NC}"
}

# ─── Section Divider ──────────────────────────────────────────────────────
log_section() {
  echo -e "\n${CYAN}────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
}

# ─── Confirm Prompt ───────────────────────────────────────────────────────
confirm() {
  local prompt="${1:-Are you sure?}"
  local default="${2:-N}"
  if [[ "$default" == "Y" ]]; then
    read -rp "$(echo -e "${YELLOW}  ${prompt} (Y/n): ${NC}")" response
    [[ -z "$response" || "$response" =~ ^[Yy] ]]
  else
    read -rp "$(echo -e "${YELLOW}  ${prompt} (y/N): ${NC}")" response
    [[ "$response" =~ ^[Yy] ]]
  fi
}

# ─── Status Symbol ────────────────────────────────────────────────────────
status_symbol() {
  local enabled="$1"
  if [[ "$enabled" == "true" ]]; then
    echo -e "${GREEN}●${NC}"
  else
    echo -e "${YELLOW}○${NC}"
  fi
}

# ─── Log to Journald ──────────────────────────────────────────────────────
log_to_journal() {
  local priority="${1:-info}"
  local tag="${2:-atlas}"
  local message="$3"
  echo "$message" | systemd-cat -t "$tag" -p "$priority" 2>/dev/null || true
}

# ─── Timer / Duration ─────────────────────────────────────────────────────
timer_start() {
  TIMER_START=$(date +%s)
}

timer_stop() {
  local now
  now=$(date +%s)
  local elapsed=$((now - TIMER_START))
  local minutes=$((elapsed / 60))
  local seconds=$((elapsed % 60))
  if [[ $minutes -gt 0 ]]; then
    echo "${minutes}m${seconds}s"
  else
    echo "${seconds}s"
  fi
}
