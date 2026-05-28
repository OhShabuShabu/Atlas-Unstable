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

# ============================================================================
# SECTION 1: Base Module Metadata
# ============================================================================
# These are the well-known modules with full metadata.
# Arrays are intentionally NOT readonly so they can be dynamically extended
# by discover_remote_catalog() and fetch_remote_registry().
# ============================================================================

# Module IDs
MODULE_IDS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19)

# Module descriptions (one-line summary for UI display)
MODULE_DESC=(
  [1]="performance       CPU governor, TCP BBR, Nix GC tuning, ZRAM"
  [2]="privacy           Mullvad VPN, Mullvad Browser, metadata cleaner"
  [3]="gaming            Steam, MangoHUD, 32-bit graphics"
  [4]="virtualisation    Docker, Podman, libvirt, Looking Glass"
  [5]="minecraft         PrismLauncher, Blockbench, MCASelector"
  [6]="flatpak           Flatpak with Flathub repository"
  [7]="dev               Neovim, VSCodium, bun, opencode"
  [8]="tools             yt-dlp, mpv, btop, ripgrep, bat"
  [9]="extras            Ollama ROCm, animated wallpapers"
  [10]="bluetooth         Bluetooth with Blueman manager"
  [11]="pdf               PDF readers, editors, OCR tools"
  [12]="art               Krita, Inkscape, GIMP, OBS Studio"
  [13]="gpu-amd           AMD GPU initrd kernel module"
  [14]="gpu-intel         Intel GPU initrd kernel module"
  [15]="gpu-nvidia        NVIDIA GPU initrd kernel module"
  [16]="security          System security hardening"
  [17]="shell             ZSH with OhMyZsh, Starship prompt"
  [18]="fonts             Fonts including Nerd Fonts"
  [19]="media             Media codecs, VA-API, VLC, FFmpeg"
)

# Relative file path within the atlas-modules repository
MODULE_FILE=(
  [1]="modules/nixos/performance.nix"
  [2]="modules/nixos/privacy.nix"
  [3]="modules/nixos/gaming.nix"
  [4]="modules/nixos/virtualisation.nix"
  [5]="modules/nixos/minecraft.nix"
  [6]="modules/nixos/flatpak.nix"
  [7]="modules/home/dev.nix"
  [8]="modules/home/tools.nix"
  [9]="modules/nixos/extras.nix"
  [10]="modules/nixos/bluetooth.nix"
  [11]="modules/nixos/pdf.nix"
  [12]="modules/nixos/art.nix"
  [13]="modules/nixos/gpu-amd.nix"
  [14]="modules/nixos/gpu-intel.nix"
  [15]="modules/nixos/gpu-nvidia.nix"
  [16]="modules/nixos/security.nix"
  [17]="modules/nixos/shell.nix"
  [18]="modules/nixos/fonts.nix"
  [19]="modules/nixos/media.nix"
)

# Subdirectory: "nixos" for system modules, "home" for home-manager modules
MODULE_SUBDIR=(
  [1]="nixos"
  [2]="nixos"
  [3]="nixos"
  [4]="nixos"
  [5]="nixos"
  [6]="nixos"
  [7]="home"
  [8]="home"
  [9]="nixos"
  [10]="nixos"
  [11]="nixos"
  [12]="nixos"
  [13]="nixos"
  [14]="nixos"
  [15]="nixos"
  [16]="nixos"
  [17]="nixos"
  [18]="nixos"
  [19]="nixos"
)

# Module categories for grouping in the UI
MODULE_CATEGORY=(
  [1]="system"
  [2]="privacy"
  [3]="gaming"
  [4]="virtualisation"
  [5]="gaming"
  [6]="system"
  [7]="development"
  [8]="tools"
  [9]="extras"
  [10]="system"
  [11]="system"
  [12]="creative"
  [13]="hardware"
  [14]="hardware"
  [15]="hardware"
  [16]="security"
  [17]="system"
  [18]="system"
  [19]="system"
)

# Module tags for filtering (space-separated)
MODULE_TAGS=(
  [1]="performance nix gc kernel"
  [2]="vpn privacy metadata mullvad"
  [3]="steam gaming overlay mangohud"
  [4]="docker podman vm containers kvm"
  [5]="minecraft prism launcher"
  [6]="flatpak flathub"
  [7]="dev neovim vscode editor git"
  [8]="media downloader tools utilities"
  [9]="ai ml ollama wallpaper"
  [10]="bluetooth bluez blueman"
  [11]="pdf document viewer ocr"
  [12]="art drawing painting creative"
  [13]="gpu amd initrd plymouth"
  [14]="gpu intel initrd plymouth"
  [15]="gpu nvidia initrd plymouth"
  [16]="security hardening firewall audit"
  [17]="shell zsh terminal prompt"
  [18]="fonts typography nerdfonts"
  [19]="media codecs video audio playback"
)

# Module dependencies (space-separated module IDs)
MODULE_DEPS=(
  [1]=""
  [2]=""
  [3]="8"
  [4]=""
  [5]="3"
  [6]=""
  [7]=""
  [8]=""
  [9]=""
  [10]=""
  [11]=""
  [12]=""
  [13]=""
  [14]=""
  [15]=""
  [16]=""
  [17]=""
  [18]=""
  [19]=""
)

# Module descriptions (long form for preview/help)
MODULE_INFO=(
  [1]="Performance tuning: sets CPU governor to performance, enables TCP BBR congestion control, tunes Nix garbage collection, and enables ZRAM compressed swap for improved responsiveness."
  [2]="Privacy suite: installs Mullvad VPN with kill switch, Mullvad Browser, and automated metadata stripping via mat2 for downloaded files."
  [3]="Gaming environment: Steam with MangoHUD performance overlay, Gamescope session, 32-bit graphics support, and custom Millennium Steam skin assets."
  [4]="Virtualisation: Docker, Podman, and libvirt (virt-manager) with distrobox integration, Looking Glass KVM framebuffer relay, SPICE USB redirection, and nftables VM-forward rules."
  [5]="Minecraft: PrismLauncher for modded Minecraft with modpack support, Blockbench for 3D model editing, and MCASelector for region-file editing."
  [6]="Flatpak: enables Flatpak and adds the Flathub repository automatically on first boot."
  [7]="Development tools: Neovim (LazyVim-ready), VSCodium, bun runtime, opencode AI coding assistant, git/gh/lazygit workflow tools, TypeScript/ESLint/Prettier toolchain."
  [8]="Core CLI utilities: yt-dlp for video downloading, mpv media player, btop/htop monitoring, ripgrep/fd/fzf search tools, bat/eza/jq formatters, compression tools, and fastfetch system info."
  [9]="Extras: Ollama with ROCm GPU acceleration for local LLM inference, linux-wallpaperengine and mpvpaper for animated desktop wallpapers."
  [10]="Bluetooth: enables Bluetooth hardware with experimental features, power-on-boot, and the Blueman GTK management GUI."
  [11]="PDF & documents: Zathura/Evince viewers, pdfarranger/poppler/qpdf manipulation, Pandoc conversion, Tesseract OCR engine."
  [12]="Digital art and creative tools: Krita for painting, Inkscape for vector graphics, GIMP for raster image editing, and OBS Studio for recording/streaming."
  [13]="AMD GPU: loads amdgpu in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only AMD firmware is bundled."
  [14]="Intel GPU: loads i915 in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only Intel firmware is bundled."
  [15]="NVIDIA GPU: loads nouveau in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only NVIDIA firmware is bundled."
  [16]="Security hardening: kernel sysctl hardening (dmesg/kptr/bpf/network), sudo password enforcement, optional fail2ban, and security auditing tools."
  [17]="Shell customization: ZSH with OhMyZsh plugins (git, sudo, extract), syntax highlighting, autosuggestions, Starship prompt, zoxide directory jumper, and thefuck command correction."
  [18]="Font configuration: Inter, Noto Fonts (CJK/Emoji), JetBrains Mono, Fira Code, and optional Nerd Fonts patched variants with proper fontconfig defaults."
  [19]="Media codecs and playback: FFmpeg with hardware acceleration, VLC/mpv/imv players, Intel/Radeon VA-API drivers, and thumbnail generation."
)

# Module versions (semver)
MODULE_VERSION=(
  [1]="1.0.0"
  [2]="1.1.0"
  [3]="2.0.0"
  [4]="1.1.0"
  [5]="1.0.0"
  [6]="1.0.0"
  [7]="2.0.0"
  [8]="1.1.0"
  [9]="1.0.0"
  [10]="1.0.0"
  [11]="1.0.0"
  [12]="1.0.0"
  [13]="1.0.0"
  [14]="1.0.0"
  [15]="1.0.0"
  [16]="1.0.0"
  [17]="1.0.0"
  [18]="1.0.0"
  [19]="1.0.0"
)

# ============================================================================
# SECTION 2: Dynamic Module Discovery
# ============================================================================
# Auto-discovers modules from the Atlas-Modules GitHub repo that aren't
# in the hardcoded list above. New modules get auto-assigned IDs (1000+)
# with generated metadata.
#
# Disable with: REMOTE_DISCOVERY_SKIP=1
# ============================================================================

readonly GITHUB_MODULES_API="${GITHUB_MODULES_API:-https://api.github.com/repos/OhShabuShabu/Atlas-Modules/contents/modules}"

# Check if a given filename+subdir is already in the registry
_is_known_file() {
  local filename="$1" subdir="$2"
  local expected="modules/$subdir/$filename"
  for __id in "${MODULE_IDS[@]}"; do
    if [[ "${MODULE_FILE[$__id]:-}" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

# Add a dynamically discovered module to the registry arrays
_add_dynamic_module() {
  local id="$1" name="$2" filename="$3" subdir="$4"

  MODULE_IDS+=("$id")
  MODULE_FILE[$id]="modules/$subdir/$filename"
  MODULE_SUBDIR[$id]="$subdir"
  MODULE_CATEGORY[$id]="system"
  MODULE_TAGS[$id]="$name"
  MODULE_DEPS[$id]=""
  MODULE_VERSION[$id]="0.1.0"

  local desc="Auto-discovered module"
  local info="Auto-discovered module '$name' from the Atlas-Modules repository. Install via 'atlas-module install $id'."

  case "$name" in
    syncthing)  desc="syncthing        Syncthing continuous file synchronization";;
    tailscale)  desc="tailscale        Tailscale zero-config VPN mesh network";;
    firefox)    desc="firefox          Firefox web browser with hardening";;
    chrome|chromium|brave|vivaldi|edge) desc="$name   $name web browser";;
    docker)     desc="docker           Docker container runtime";;
    podman)     desc="podman           Podman rootless container manager";;
    sway|hyprland|river|wayfire) desc="$name   $name Wayland compositor";;
    zellij)     desc="zellij           Zellij terminal multiplexer";;
    tmux)       desc="tmux             Tmux terminal multiplexer";;
    kitty|alacritty|foot|wezterm) desc="$name   $name terminal emulator";;
  esac

  MODULE_DESC[$id]="$desc"
  MODULE_INFO[$id]="$info"
}

# Discover modules from the GitHub repo that aren't in the hardcoded list
# Usage: discover_remote_catalog
discover_remote_catalog() {
  local next_id=1000
  local api_url="${GITHUB_MODULES_API}"
  local nixos_files home_files

  # Find the next available ID starting from 1000
  local max_id=0
  for __id in "${MODULE_IDS[@]}"; do
    [[ "$__id" -gt "$max_id" ]] && max_id="$__id"
  done
  next_id=$((max_id > 999 ? max_id + 1 : 1000))

  # Fetch file lists from GitHub API
  nixos_files=$(timeout 10 curl -sf "$api_url/nixos" 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep '\.nix$' | grep -v '^default\.nix$' || true)
  home_files=$(timeout 10 curl -sf "$api_url/home" 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep '\.nix$' | grep -v '^default\.nix$' || true)

  # Process nixos modules
  if [[ -n "$nixos_files" ]]; then
    while IFS= read -r filename; do
      [[ -z "$filename" ]] && continue
      local name="${filename%.nix}"
      if ! _is_known_file "$filename" "nixos"; then
        _add_dynamic_module "$next_id" "$name" "$filename" "nixos"
        ((next_id++))
      fi
    done <<< "$nixos_files"
  fi

  # Process home modules
  if [[ -n "$home_files" ]]; then
    while IFS= read -r filename; do
      [[ -z "$filename" ]] && continue
      local name="${filename%.nix}"
      if ! _is_known_file "$filename" "home"; then
        _add_dynamic_module "$next_id" "$name" "$filename" "home"
        ((next_id++))
      fi
    done <<< "$home_files"
  fi
}

# ============================================================================
# Module State File Path
# ============================================================================
ATLAS_MODULE_STATE_DIR="${ATLAS_MODULE_STATE_DIR:-/persistent/etc/atlas-modules}"
ATLAS_MODULE_STATE_FILE="${ATLAS_MODULE_STATE_FILE:-$ATLAS_MODULE_STATE_DIR/state.json}"

# ============================================================================
# Categories (grouped module IDs) — rebuilt dynamically from MODULE_CATEGORY
# ============================================================================
_build_categories_list() {
  local seen=""
  MODULE_CATEGORIES=()
  for __id in "${MODULE_IDS[@]}"; do
    local cat="${MODULE_CATEGORY[$__id]}"
    if [[ "$seen" != *"|$cat|"* ]]; then
      seen="$seen|$cat|"
      MODULE_CATEGORIES+=("$cat")
    fi
  done
}
_build_categories_list

# ============================================================================
# State Management
# ============================================================================

# Ensure state file and directory exist with default structure
ensure_state() {
  if [[ ! -f "$ATLAS_MODULE_STATE_FILE" ]]; then
    mkdir -p "$ATLAS_MODULE_STATE_DIR"
    cat > "$ATLAS_MODULE_STATE_FILE" <<EOF
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

# Read module state from state file, return JSON for modules
read_state() {
  ensure_state
  jq -c '.modules' "$ATLAS_MODULE_STATE_FILE" 2>/dev/null || echo "{}"
}

# Write module state to state file atomically
write_state() {
  local modules_json="$1"
  jq --arg now "$(date -Iseconds)" \
     --argjson modules "$modules_json" \
     '.modules = $modules | .metadata.updated = $now' \
     "$ATLAS_MODULE_STATE_FILE" > "${ATLAS_MODULE_STATE_FILE}.tmp" && mv "${ATLAS_MODULE_STATE_FILE}.tmp" "$ATLAS_MODULE_STATE_FILE"
}

# ============================================================================
# Helper Functions
# ============================================================================

# Get the local directory for a module type
# Usage: get_module_dir <subdir>
get_module_dir() {
  local subdir="$1"
  local base="${ATLAS_MODULES_BASE:-$(cd "$(dirname "$0")/../.." && pwd)}"
  echo "$base/files/modules/optional/$subdir"
}

# Get module short name from description
# Usage: get_module_name <id>
get_module_name() {
  local id="$1"
  local desc="${MODULE_DESC[$id]:-}"
  echo "${desc%% *}"
}

# Get modules in a specific category
# Usage: get_modules_by_category <category>
get_modules_by_category() {
  local target="$1"
  for id in "${MODULE_IDS[@]}"; do
    if [[ "${MODULE_CATEGORY[$id]}" == "$target" ]]; then
      echo "$id"
    fi
  done
}

# Check if a module is installed
# Usage: is_module_installed <id>
is_module_installed() {
  local id="$1"
  local file="${MODULE_FILE[$id]:-}"
  [[ -z "$file" ]] && return 1
  local filename; filename=$(basename "$file")
  local subdir="${MODULE_SUBDIR[$id]:-}"
  [[ -z "$subdir" ]] && return 1
  local dest_dir; dest_dir="$(get_module_dir "$subdir")"
  [[ -f "$dest_dir/$filename" ]]
}

# Check if a module is enabled in state
# Usage: is_module_enabled <id> [state_json]
is_module_enabled() {
  local id="$1"
  local state="${2:-$(read_state)}"
  local enabled; enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
  [[ "$enabled" == "true" ]]
}

# Get reverse dependencies (modules that depend on the given module)
# Usage: get_reverse_deps <id>
get_reverse_deps() {
  local target="$1"
  for id in "${MODULE_IDS[@]}"; do
    local deps="${MODULE_DEPS[$id]:-}"
    if [[ "$deps" == *"$target"* ]]; then
      echo "$id"
    fi
  done
}

# Validate module dependencies for all enabled modules
# Usage: validate_deps [state_json]
validate_deps() {
  local state="${1:-$(read_state)}"
  local issues=0
  for id in "${MODULE_IDS[@]}"; do
    local enabled; enabled=$(echo "$state" | jq -r ".\"$id\".enabled // false")
    [[ "$enabled" != "true" ]] && continue
    local deps="${MODULE_DEPS[$id]:-}"
    if [[ -n "$deps" ]]; then
      for dep in $deps; do
        local dep_enabled; dep_enabled=$(echo "$state" | jq -r ".\"$dep\".enabled // false")
        if [[ "$dep_enabled" != "true" ]]; then
          echo "WARN: Module $(get_module_name "$id") depends on $(get_module_name "$dep") which is not enabled" >&2
          issues=1
        fi
      done
    fi
  done
  [[ $issues -eq 0 ]]
}

# Download a single module from the atlas-modules repository
# Usage: download_module <id> <dest_dir>
download_module() {
  local id="$1"
  local dest_dir="$2"
  local file="${MODULE_FILE[$id]:-}"
  [[ -z "$file" ]] && return 1
  local filename; filename=$(basename "$file")
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
  local file="${MODULE_FILE[$id]:-}"
  basename "$file"
}

# Check if a module ID is valid (exists in registry)
# Usage: is_valid_module_id <id>
is_valid_module_id() {
  local id="$1"
  for __id in "${MODULE_IDS[@]}"; do
    [[ "$__id" == "$id" ]] && return 0
  done
  return 1
}

# ============================================================================
# Remote Registry Sync
# ============================================================================
# Fetches the latest module metadata from the Atlas-Modules repo,
# overriding local arrays so the manager always reflects the remote state.
# Falls back silently to local definitions on failure.
# ============================================================================
REMOTE_REGISTRY_URL="${REMOTE_REGISTRY_URL:-https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/module-registry.sh}"

fetch_remote_registry() {
  local tmp_file
  tmp_file=$(mktemp)
  if timeout 10 curl -sSf "$REMOTE_REGISTRY_URL" -o "$tmp_file" 2>/dev/null; then
    # Strip readonly so arrays can be re-declared over local ones
    sed -i 's/^readonly //' "$tmp_file"
    source "$tmp_file"
    rm -f "$tmp_file"
    return 0
  fi
  rm -f "$tmp_file"
  return 1
}

# Auto-fetch remote registry and auto-discover modules on source
# Disable with: REMOTE_REGISTRY_SKIP=1
if [[ -z "${REMOTE_REGISTRY_SKIP:-}" && -z "${REMOTE_DISCOVERY_SKIP:-}" ]]; then
  # First try the remote registry sync (may override arrays)
  fetch_remote_registry 2>/dev/null || true
  # Then discover new modules from the GitHub API
  discover_remote_catalog 2>/dev/null || true
  # Rebuild the categories list in case new categories were added
  _build_categories_list 2>/dev/null || true
fi
