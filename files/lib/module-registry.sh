#!/usr/bin/env bash
# ============================================================================
# ATLAS MODULE REGISTRY (Bash)
# ============================================================================
# Shared module metadata for both installer and post-install module manager.
# Keep in sync with module-registry.nix
#
# Usage: source files/lib/module-registry.sh
# ============================================================================

# Raw URL for module downloads
readonly ATLAS_MODULES_RAW_URL="https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main"

# Module IDs
readonly MODULE_IDS=(1 2 3 4 5 6 7 8 9)

# Module descriptions (one-line summary for UI display)
readonly MODULE_DESC=(
  [1]="performance       CPU governor, TCP BBR, Nix GC tuning"
  [2]="privacy           Mullvad VPN, metadata cleaner"
  [3]="gaming            Steam, MangoHUD overlay"
  [4]="virtualisation    Docker, Podman, libvirt"
  [5]="minecraft         PrismLauncher, Blockbench"
  [6]="flatpak           Flathub repository"
  [7]="dev               Neovim, VSCodium, bun, opencode"
  [8]="tools             yt-dlp, mpv"
  [9]="extras            AI/ML (Ollama ROCm), animated wallpapers"
)

# Relative file path within the atlas-modules repository
readonly MODULE_FILE=(
  [1]="performance.nix"
  [2]="privacy/privacy.nix"
  [3]="gaming/gaming.nix"
  [4]="virtualisation.nix"
  [5]="minecraft.nix"
  [6]="flatpak.nix"
  [7]="dev/dev.nix"
  [8]="tools.nix"
  [9]="extras.nix"
)

# Subdirectory: "nixos" for system modules, "home" for home-manager modules
readonly MODULE_SUBDIR=(
  [1]="nixos"
  [2]="nixos"
  [3]="nixos"
  [4]="nixos"
  [5]="nixos"
  [6]="nixos"
  [7]="home"
  [8]="home"
  [9]="nixos"
)

# Module categories for grouping in the UI
readonly MODULE_CATEGORY=(
  [1]="system"
  [2]="privacy"
  [3]="gaming"
  [4]="virtualisation"
  [5]="gaming"
  [6]="system"
  [7]="development"
  [8]="tools"
  [9]="extras"
)

# Module tags for filtering (space-separated)
readonly MODULE_TAGS=(
  [1]="performance nix gc"
  [2]="vpn privacy metadata"
  [3]="steam gaming overlay"
  [4]="docker podman vm containers"
  [5]="minecraft prism"
  [6]="flatpak flathub"
  [7]="dev neovim vscode editor"
  [8]="media downloader tools"
  [9]="ai ml ollama wallpaper"
)

# Module dependencies (space-separated module IDs)
readonly MODULE_DEPS=(
  [1]=""
  [2]=""
  [3]="8"
  [4]=""
  [5]="3"
  [6]=""
  [7]=""
  [8]=""
  [9]=""
)

# Module descriptions (long form for preview/help)
readonly MODULE_INFO=(
  [1]="Performance tuning: sets CPU governor to performance, enables TCP BBR congestion control, and tunes Nix garbage collection for optimal build performance."
  [2]="Privacy suite: installs Mullvad VPN with kill switch, Mullvad Browser, and automated metadata stripping for downloaded files."
  [3]="Gaming environment: Steam with MangoHUD performance overlay, 32-bit graphics support, and custom Millennium Steam skin."
  [4]="Virtualisation: Docker, Podman, and libvirt (virt-manager) with distrobox integration for container-based development."
  [5]="Minecraft: PrismLauncher for modded Minecraft, Blockbench for 3D model editing. Depends on the gaming module."
  [6]="Flatpak: adds Flathub repository and configures essential Flatpak applications including Discord, Telegram, and Bottles."
  [7]="Development tools: Neovim with LazyVim, VSCodium, bun runtime, opencode AI coding assistant, and Claude Code CLI."
  [8]="Media tools: yt-dlp for video downloading, mpv media player with hardware acceleration."
  [9]="Extras: Ollama with ROCm GPU acceleration for local LLM inference, animated MPV wallpapers via mpvpaper."
)

# Module versions (semver)
readonly MODULE_VERSION=(
  [1]="1.0.0"
  [2]="1.0.0"
  [3]="2.0.0"
  [4]="1.0.0"
  [5]="1.0.0"
  [6]="1.0.0"
  [7]="2.0.0"
  [8]="1.0.0"
  [9]="1.0.0"
)

# ============================================================================
# Module State File Path
# ============================================================================
readonly ATLAS_MODULE_STATE_DIR="/persistent/etc/atlas-modules"
readonly ATLAS_MODULE_STATE_FILE="$ATLAS_MODULE_STATE_DIR/state.json"

# ============================================================================
# Helper Functions
# ============================================================================

# Get the local directory for a module type
# Usage: get_module_dir <subdir>
get_module_dir() {
  local subdir="$1"
  local base="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/.." && pwd)}"
  echo "$base/files/modules/optional/$subdir"
}

# Get module short name from description
# Usage: get_module_name <id>
get_module_name() {
  local id="$1"
  local desc="${MODULE_DESC[$id]}"
  echo "${desc%% *}"
}

# Download a single module from the atlas-modules repository
# Usage: download_module <id> <dest_dir>
download_module() {
  local id="$1"
  local dest_dir="$2"
  local file="${MODULE_FILE[$id]}"
  local filename
  filename=$(basename "$file")
  local url="$ATLAS_MODULES_RAW_URL/$file"

  mkdir -p "$dest_dir"

  if command -v curl &>/dev/null; then
    CURL_CMD=(curl)
  else
    CURL_CMD=(nix run nixpkgs#curl --)
  fi

  if timeout 30 "${CURL_CMD[@]}" -sSo "$dest_dir/$filename" "$url" 2>/dev/null; then
    return 0
  fi
  # Retry once
  if timeout 30 "${CURL_CMD[@]}" -sSo "$dest_dir/$filename" "$url" 2>/dev/null; then
    return 0
  fi
  rm -f "$dest_dir/$filename"
  return 1
}

# Get the filename on disk for a module
# Usage: get_module_filename <id>
get_module_filename() {
  local id="$1"
  local file="${MODULE_FILE[$id]}"
  basename "$file"
}
