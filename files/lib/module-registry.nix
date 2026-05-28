# ============================================================================
# ATLAS MODULE REGISTRY (Nix)
# ============================================================================
# Shared module metadata for both installer and post-install module manager.
# Keep in sync with module-registry.sh
#
# Usage:
#   let registry = import ../../lib/module-registry.nix;
#   in registry.modules  # attrset
# ============================================================================

# ─── Module Definitions ──────────────────────────────────────────────────
# Maps module ID (string) to module metadata
modules = {
  "1" = {
    name = "performance";
    description = "CPU governor, TCP BBR, Nix GC tuning";
    info = "Performance tuning: sets CPU governor to performance, enables TCP BBR congestion control, and tunes Nix garbage collection for optimal build performance.";
    file = "performance.nix";
    subdir = "nixos";
    category = "system";
    tags = [ "performance" "nix" "gc" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/performance.nix";
  };

  "2" = {
    name = "privacy";
    description = "Mullvad VPN, metadata cleaner";
    info = "Privacy suite: installs Mullvad VPN with kill switch, Mullvad Browser, and automated metadata stripping for downloaded files.";
    file = "privacy.nix";
    subdir = "nixos";
    category = "privacy";
    tags = [ "vpn" "privacy" "metadata" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/privacy/privacy.nix";
  };

  "3" = {
    name = "gaming";
    description = "Steam, MangoHUD overlay";
    info = "Gaming environment: Steam with MangoHUD performance overlay, 32-bit graphics support, and custom Millennium Steam skin.";
    file = "gaming.nix";
    subdir = "nixos";
    category = "gaming";
    tags = [ "steam" "gaming" "overlay" ];
    deps = [ "8" ];
    version = "2.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/gaming/gaming.nix";
  };

  "4" = {
    name = "virtualisation";
    description = "Docker, Podman, libvirt";
    info = "Virtualisation: Docker, Podman, and libvirt (virt-manager) with distrobox integration for container-based development.";
    file = "virtualisation.nix";
    subdir = "nixos";
    category = "virtualisation";
    tags = [ "docker" "podman" "vm" "containers" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/virtualisation.nix";
  };

  "5" = {
    name = "minecraft";
    description = "PrismLauncher, Blockbench";
    info = "Minecraft: PrismLauncher for modded Minecraft, Blockbench for 3D model editing. Depends on the gaming module.";
    file = "minecraft.nix";
    subdir = "nixos";
    category = "gaming";
    tags = [ "minecraft" "prism" ];
    deps = [ "3" ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/minecraft.nix";
  };

  "6" = {
    name = "flatpak";
    description = "Flathub repository";
    info = "Flatpak: adds Flathub repository and configures essential Flatpak applications including Discord, Telegram, and Bottles.";
    file = "flatpak.nix";
    subdir = "nixos";
    category = "system";
    tags = [ "flatpak" "flathub" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/flatpak.nix";
  };

  "7" = {
    name = "dev";
    description = "Neovim, VSCodium, bun, opencode";
    info = "Development tools: Neovim with LazyVim, VSCodium, bun runtime, opencode AI coding assistant, and Claude Code CLI.";
    file = "dev.nix";
    subdir = "home";
    category = "development";
    tags = [ "dev" "neovim" "vscode" "editor" ];
    deps = [ ];
    version = "2.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/dev/dev.nix";
  };

  "8" = {
    name = "tools";
    description = "yt-dlp, mpv";
    info = "Media tools: yt-dlp for video downloading, mpv media player with hardware acceleration.";
    file = "tools.nix";
    subdir = "home";
    category = "tools";
    tags = [ "media" "downloader" "tools" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/tools.nix";
  };

  "9" = {
    name = "extras";
    description = "AI/ML (Ollama ROCm), animated wallpapers";
    info = "Extras: Ollama with ROCm GPU acceleration for local LLM inference, animated MPV wallpapers via mpvpaper.";
    file = "extras.nix";
    subdir = "nixos";
    category = "extras";
    tags = [ "ai" "ml" "ollama" "wallpaper" ];
    deps = [ ];
    version = "1.0.0";
    url = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main/extras.nix";
  };
};

# ─── Reverse Mapping: filename -> module id ───────────────────────────────
# Build a lookup table from filename to module id
filenameToId = builtins.listToAttrs (
  builtins.map (id: {
    name = modules.${id}.file;
    value = id;
  }) (builtins.attrNames modules)
);

# ─── State File ──────────────────────────────────────────────────────────
stateFilePath = "/persistent/etc/atlas-modules/state.json";

# ─── Read Module State ──────────────────────────────────────────────────
# Returns an attrset of module_id -> { enabled: bool, ... }
readModuleState = let
  result = builtins.tryEval (builtins.readFile stateFilePath);
in
  if result.success then
    let parsed = builtins.fromJSON result.value;
    in parsed.modules or { }
  else
    { };

# ─── Helper: is module enabled? ─────────────────────────────────────────
# Usage: isEnabled <state_attrset> <module_id>
isEnabled = state: id:
  let
    modState = state.${id} or { };
  in
    if builtins.hasAttr "enabled" modState then modState.enabled
    else true;  # default to enabled

# ─── Helper: should import a file? ──────────────────────────────────────
# Given a filename, check if it corresponds to a registry module and
# whether that module is enabled. Non-registry files are always imported.
shouldImportFile = state: filename:
  let
    matchedId = filenameToId.${filename} or null;
  in
    if matchedId == null then
      true  # Non-registry file (e.g., gpu.nix) → import
    else
      isEnabled state matchedId;

# ─── Get all enabled module IDs ─────────────────────────────────────────
getEnabledIds = state:
  builtins.filter (id: isEnabled state id) (builtins.attrNames modules);

# ─── Validate module dependencies ──────────────────────────────────────
validateDeps = state:
  let
    enabledIds = getEnabledIds state;
    missing = builtins.filter (id:
      let mod = modules.${id}; in
      builtins.any (dep: !(builtins.elem dep enabledIds)) mod.deps
    ) enabledIds;
  in {
    valid = builtins.length missing == 0;
    missingDeps = builtins.map (id: {
      inherit id;
      module = modules.${id}.name;
      missing = builtins.filter (dep: !(builtins.elem dep enabledIds)) modules.${id}.deps;
    }) missing;
  };

{
  inherit modules filenameToId stateFilePath;
  inherit readModuleState isEnabled shouldImportFile getEnabledIds validateDeps;
  moduleIds = builtins.sort builtins.lessThan (builtins.attrNames modules);
}
