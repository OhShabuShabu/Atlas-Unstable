#!/usr/bin/env bash
# ============================================================================
# YORHA TUI THEME LIBRARY
# ============================================================================
# Extends logging.sh with consistent box-drawing, status display, and layout
# helpers.  Every YoRHa script that produces terminal output should source
# this file (which sources logging.sh) instead of defining its own colors.
#
# Usage: source "$(dirname "$0")/../lib/tui.sh"
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# ─── Terminal Width ─────────────────────────────────────────────────────
tui_width() {
  tput cols 2>/dev/null || echo 80
}

# ─── Box Drawing (Headers / Sections) ───────────────────────────────────

tui_header() {
  local title="$1"
  local w; w=$(tui_width)
  local line_len=$((w - 5 - ${#title}))
  [[ $line_len -lt 2 ]] && line_len=2
  local line; line=$(printf '─%.0s' $(seq 1 $line_len))
  echo -e "\n${CYAN}┌─ ${title} ${line}┐${NC}"
}

tui_footer() {
  local w; w=$(tui_width)
  local line_len=$((w - 3))
  [[ $line_len -lt 2 ]] && line_len=2
  local line; line=$(printf '─%.0s' $(seq 1 $line_len))
  echo -e "${CYAN}└─${line}┘${NC}"
}

# Framed header used by the module manager (shorter, fixed width).
tui_box_header() {
  local title="$1"
  echo -e "${CYAN}┌─ ${title} ${DIM}──────────────────────────────────────${NC}"
  echo -e "${CYAN}└────────────────────────────────────────────────────────${NC}"
  echo ""
}

# Section divider (thin line + title).
tui_section() {
  local title="$1"
  echo -e "\n${CYAN}── ${title}${NC}"
}

# Sub-section (bold, indented).
tui_subtitle() {
  echo -e "\n  ${BOLD}$1${NC}"
}

# ─── Status Symbols ────────────────────────────────────────────────────

# Dot for enabled/disabled states.
tui_dot() {
  local state="$1"
  case "$state" in
    enabled|true|yes|1)  echo -e "${GREEN}●${NC}" ;;
    disabled|false|no|0) echo -e "${YELLOW}○${NC}" ;;
    *)                   echo -e "${DIM}○${NC}" ;;
  esac
}

# Check/cross symbols.
tui_check()  { echo -e "${GREEN}✓${NC}"; }
tui_cross()  { echo -e "${RED}✗${NC}"; }
tui_arrow()  { echo -e "${CYAN}→${NC}"; }
tui_warn_sym() { echo -e "${YELLOW}⚠${NC}"; }

# ─── Module Status Row ─────────────────────────────────────────────────
# Output: <dot> <id>) <icon> <bold-name> — <desc>  [(disabled|not installed)]
tui_module_row() {
  local id="$1" name="$2" desc="$3" icon="$4" state="$5"
  local dot; dot=$(tui_dot "$state")
  local suffix=""
  [[ "$state" == "disabled" ]] && suffix=" ${YELLOW}(disabled)${NC}"
  [[ "$state" == "not-installed" ]] && suffix=" ${DIM}(not installed)${NC}"
  echo -e "  ${dot} ${CYAN}$id${NC}) $icon ${BOLD}$name${NC} — ${DIM}$desc${NC}${suffix}"
}

# ─── List-style helpers ─────────────────────────────────────────────────
# Menu option:  1) Label
tui_option() {
  echo -e "  ${CYAN}$1${NC}) $2"
}

# Info line (key: value) with dimmed value.
tui_kv() {
  local key="$1" val="$2"
  echo -e "  ${BOLD}$key:${NC} ${DIM}$val${NC}"
}

# ─── Keybinding hint (dimmed) ───────────────────────────────────────────
tui_hint() {
  echo -e "  ${DIM}$1${NC}"
}

# ─── "Press Enter" prompt ──────────────────────────────────────────────
tui_press_enter() {
  read -rp "$(echo -e "  ${DIM}Press Enter to continue...${NC}")"
}

# ─── Prompt (colored label + read into named var) ───────────────────────
# Usage: tui_prompt "Enter ID" CYAN choice
tui_prompt() {
  local label="$1"
  local color="${2:-CYAN}"
  local varname="${3:-REPLY}"
  local var; var="${!color:-$CYAN}"
  read -rp "$(echo -e "  ${var}$label: ${NC}")" "$varname"
}

# ─── Summary Line ───────────────────────────────────────────────────────
# Counters with color: "Total: 10 | Enabled: 5 | Disabled: 2"
tui_summary() {
  local parts=()
  while [[ $# -gt 0 ]]; do
    local label="$1" count="$2" color="$3"
    parts+=("$(echo -e "${BOLD}$label:${NC} ${!color}$count${NC}")")
    shift 3
  done
  local IFS=" | "
  echo -e "  ${parts[*]}"
}

# ─── fzf Preview Helpers ───────────────────────────────────────────────
# Returns ANSI-escaped strings for use in fzf --preview blocks.
# These output raw escape sequences (no $'' evaluation needed in fzf).

tui_fzf_header() {
  local title="$1"
  printf '\033[1;36m%s\033[0m\n' "$title"
  printf '\033[2m%s\033[0m\n' '─────────────────────────────────'
}

tui_fzf_kv() {
  local key="$1" val="$2"
  printf '  \033[1m%s\033[0m  %s\n' "$key:" "$val"
}

tui_fzf_body() {
  local text="$1"
  printf '  %s\n' "$text" | fold -w 55 | sed 's/^/  /'
}

tui_fzf_dim() {
  printf '\033[2m%s\033[0m\n' "$1"
}

# ─── Summary Line with Counters for fzf ─────────────────────────────────
tui_fzf_counters() {
  printf '  \033[1mTotal:\033[0m \033[0;36m%s\033[0m  |  \033[1mEnabled:\033[0m \033[0;32m%s\033[0m  |  \033[1mDisabled:\033[0m \033[1;33m%s\033[0m\n' "$1" "$2" "$3"
}

# ─── Reset ──────────────────────────────────────────────────────────────
tui_reset() {
  echo -e "${NC}"
}
