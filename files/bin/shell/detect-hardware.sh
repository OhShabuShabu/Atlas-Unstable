#!/usr/bin/env bash
# ============================================================================
# HARDWARE DETECTION AND COMPATIBILITY REPORT
# ============================================================================
# Runtime hardware detection script.
# Reports detected hardware components and flags any compatibility concerns.
# Can be run at any time to verify the NixOS auto-detection matches reality.
#
# Usage: ./detect-hardware.sh
#        ./detect-hardware.sh --json    (machine-readable output)
# ============================================================================

set -euo pipefail

MODE="${1:-human}"

if [ -n "${YORHA_LIB_DIR:-}" ]; then
  source "$YORHA_LIB_DIR/tui.sh"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  source "$SCRIPT_DIR/files/lib/tui.sh"
fi

# ── Helper functions ────────────────────────────────────────────────────
detect_cpu() {
    if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        echo "intel"
    elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        echo "amd"
    else
        echo "generic"
    fi
}

detect_gpu() {
    local gpu="generic"
    # Check DRM devices (primary method)
    for d in /sys/class/drm/*/; do
        case "$(basename "$d")" in
            *amdgpu*) gpu="amd";;
            *i915*)   gpu="intel";;
            *nvidia*) gpu="nvidia";;
        esac
    done
    # Fallback: check PCI vendor via lspci
    if [ "$gpu" = "generic" ] && command -v lspci &>/dev/null; then
        if lspci -nn | grep -qi "\[1002\]"; then
            gpu="amd"
        elif lspci -nn | grep -qi "\[10de\]"; then
            gpu="nvidia"
        elif lspci -nn | grep -qi "\[8086\]"; then
            gpu="intel"
        fi
    fi
    echo "$gpu"
}

detect_ram() {
    local mem_total_kb
    mem_total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    echo $((mem_total_kb / 1024))
}

detect_tpm() {
    if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
        echo "yes"
    else
        echo "no"
    fi
}

detect_displays() {
    if command -v niri &>/dev/null; then
        niri msg outputs 2>/dev/null | head -20 || echo "Niri not running"
    elif command -v wlr-randr &>/dev/null; then
        wlr-randr 2>/dev/null || echo "No wlr-randr available"
    elif command -v xrandr &>/dev/null; then
        xrandr 2>/dev/null | grep " connected" || echo "No X11 display detected"
    else
        echo "No display detection tools available"
    fi
}

detect_laptop() {
    if [ -d /sys/class/power_supply ] && ls /sys/class/power_supply/ | grep -q "BAT[0-9]"; then
        echo "yes"
    else
        echo "no"
    fi
}

# ── Main detection ──────────────────────────────────────────────────────
CPU=$(detect_cpu)
GPU=$(detect_gpu)
RAM_MB=$(detect_ram)
TPM=$(detect_tpm)
LAPTOP=$(detect_laptop)

# ── Compatibility checks ────────────────────────────────────────────────
COMPAT_ISSUES=()

# GPU compatibility
if [ "$GPU" = "generic" ]; then
    COMPAT_ISSUES+=("GPU: No known GPU detected — running without acceleration")
fi

# RAM compatibility
if [ "$RAM_MB" -lt 4096 ]; then
    COMPAT_ISSUES+=("RAM: Only ${RAM_MB}MB — low-memory mode may still be stressful")
fi
if [ "$RAM_MB" -lt 2048 ]; then
    COMPAT_ISSUES+=("RAM: ${RAM_MB}MB is below minimum recommendation (2GB)")
fi

# TPM compatibility
if [ "$TPM" = "no" ]; then
    COMPAT_ISSUES+=("TPM: No TPM 2.0 detected — LUKS key sealing unavailable (passphrase-only fallback)")
fi

# Architecture check
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    COMPAT_ISSUES+=("Architecture: Running on $ARCH — NixOS configuration targets x86_64-linux primarily")
fi

# ── Output ──────────────────────────────────────────────────────────────
if [ "$MODE" = "json" ]; then
    cat <<EOF
{
  "cpu": "$CPU",
  "gpu": "$GPU",
  "ram_mb": $RAM_MB,
  "tpm": "$TPM",
  "laptop": "$LAPTOP",
  "arch": "$ARCH",
  "issues": [$(printf '"%s"' "${COMPAT_ISSUES[*]}" | sed 's/,/", "/g')]
}
EOF
else
    tui_header "YoRHa Hardware Detection Report"
    tui_kv "CPU"          "$CPU"
    tui_kv "GPU"          "$GPU"
    tui_kv "RAM"          "${RAM_MB}MB"
    tui_kv "TPM"          "$TPM"
    tui_kv "Laptop"       "$LAPTOP"
    tui_kv "Architecture" "$ARCH"
    if [ ${#COMPAT_ISSUES[@]} -gt 0 ]; then
        tui_section "Compatibility Notes"
        for issue in "${COMPAT_ISSUES[@]}"; do
            warn "$issue"
        done
    fi
    tui_hint "For display information: niri msg outputs"
    tui_footer
fi
