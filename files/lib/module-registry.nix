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

let
  baseUrl = "https://raw.githubusercontent.com/OhShabuShabu/Atlas-Modules/main";
  moduleDir = type: "modules/${type}/";

  stateFilePath = "/persistent/etc/atlas-modules/state.json";
  stateDir = "/persistent/etc/atlas-modules";

  modules = {
    "1" = {
      name = "performance";
      description = "CPU governor, TCP BBR, Nix GC tuning, ZRAM";
      info = "Performance tuning: sets CPU governor to performance, enables TCP BBR congestion control, tunes Nix garbage collection, and enables ZRAM compressed swap for improved responsiveness.";
      file = "performance.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "performance" "nix" "gc" "kernel" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}performance.nix";
    };

    "2" = {
      name = "privacy";
      description = "Mullvad VPN, Mullvad Browser, metadata cleaner";
      info = "Privacy suite: installs Mullvad VPN with kill switch, Mullvad Browser, and automated metadata stripping via mat2 for downloaded files.";
      file = "privacy.nix";
      subdir = "nixos";
      category = "privacy";
      tags = [ "vpn" "privacy" "metadata" "mullvad" ];
      deps = [ ];
      version = "1.1.0";
      url = "${baseUrl}/${moduleDir "nixos"}privacy.nix";
    };

    "3" = {
      name = "gaming";
      description = "Steam, MangoHUD, 32-bit graphics";
      info = "Gaming environment: Steam with MangoHUD performance overlay, Gamescope session, 32-bit graphics support, and custom Millennium Steam skin assets.";
      file = "gaming.nix";
      subdir = "nixos";
      category = "gaming";
      tags = [ "steam" "gaming" "overlay" "mangohud" ];
      deps = [ "8" ];
      version = "2.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}gaming.nix";
    };

    "4" = {
      name = "virtualisation";
      description = "Docker, Podman, libvirt, Looking Glass";
      info = "Virtualisation: Docker, Podman, and libvirt (virt-manager) with distrobox integration, Looking Glass KVM framebuffer relay, SPICE USB redirection, and nftables VM-forward rules.";
      file = "virtualisation.nix";
      subdir = "nixos";
      category = "virtualisation";
      tags = [ "docker" "podman" "vm" "containers" "kvm" ];
      deps = [ ];
      version = "1.1.0";
      url = "${baseUrl}/${moduleDir "nixos"}virtualisation.nix";
    };

    "5" = {
      name = "minecraft";
      description = "PrismLauncher, Blockbench, MCASelector";
      info = "Minecraft: PrismLauncher for modded Minecraft with modpack support, Blockbench for 3D model editing, and MCASelector for region-file editing.";
      file = "minecraft.nix";
      subdir = "nixos";
      category = "gaming";
      tags = [ "minecraft" "prism" "launcher" ];
      deps = [ "3" ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}minecraft.nix";
    };

    "6" = {
      name = "flatpak";
      description = "Flatpak with Flathub repository";
      info = "Flatpak: enables Flatpak and adds the Flathub repository automatically on first boot.";
      file = "flatpak.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "flatpak" "flathub" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}flatpak.nix";
    };

    "7" = {
      name = "dev";
      description = "Neovim, VSCodium, bun, opencode";
      info = "Development tools: Neovim (LazyVim-ready), VSCodium, bun runtime, opencode AI coding assistant, git/gh/lazygit workflow tools, TypeScript/ESLint/Prettier toolchain.";
      file = "dev.nix";
      subdir = "home";
      category = "development";
      tags = [ "dev" "neovim" "vscode" "editor" "git" ];
      deps = [ ];
      version = "2.0.0";
      url = "${baseUrl}/${moduleDir "home"}dev.nix";
    };

    "8" = {
      name = "tools";
      description = "yt-dlp, mpv, btop, ripgrep, bat";
      info = "Core CLI utilities: yt-dlp for video downloading, mpv media player, btop/htop monitoring, ripgrep/fd/fzf search tools, bat/eza/jq formatters, compression tools, and fastfetch system info.";
      file = "tools.nix";
      subdir = "home";
      category = "tools";
      tags = [ "media" "downloader" "tools" "utilities" ];
      deps = [ ];
      version = "1.1.0";
      url = "${baseUrl}/${moduleDir "home"}tools.nix";
    };

    "9" = {
      name = "extras";
      description = "Ollama ROCm, animated wallpapers";
      info = "Extras: Ollama with ROCm GPU acceleration for local LLM inference, linux-wallpaperengine and mpvpaper for animated desktop wallpapers.";
      file = "extras.nix";
      subdir = "nixos";
      category = "extras";
      tags = [ "ai" "ml" "ollama" "wallpaper" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}extras.nix";
    };

    "10" = {
      name = "bluetooth";
      description = "Bluetooth with Blueman manager";
      info = "Bluetooth: enables Bluetooth hardware with experimental features, power-on-boot, and the Blueman GTK management GUI.";
      file = "bluetooth.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "bluetooth" "bluez" "blueman" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}bluetooth.nix";
    };

    "11" = {
      name = "pdf";
      description = "PDF readers, editors, OCR tools";
      info = "PDF & documents: Zathura/Evince viewers, pdfarranger/poppler/qpdf manipulation, Pandoc conversion, Tesseract OCR engine.";
      file = "pdf.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "pdf" "document" "viewer" "ocr" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}pdf.nix";
    };

    "12" = {
      name = "art";
      description = "Krita, Inkscape, GIMP, OBS Studio";
      info = "Digital art and creative tools: Krita for painting, Inkscape for vector graphics, GIMP for raster image editing, and OBS Studio for recording/streaming.";
      file = "art.nix";
      subdir = "nixos";
      category = "creative";
      tags = [ "art" "drawing" "painting" "creative" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}art.nix";
    };

    "13" = {
      name = "gpu-amd";
      description = "AMD GPU initrd kernel module";
      info = "AMD GPU: loads amdgpu in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only AMD firmware is bundled.";
      file = "gpu-amd.nix";
      subdir = "nixos";
      category = "hardware";
      tags = [ "gpu" "amd" "initrd" "plymouth" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}gpu-amd.nix";
    };

    "14" = {
      name = "gpu-intel";
      description = "Intel GPU initrd kernel module";
      info = "Intel GPU: loads i915 in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only Intel firmware is bundled.";
      file = "gpu-intel.nix";
      subdir = "nixos";
      category = "hardware";
      tags = [ "gpu" "intel" "initrd" "plymouth" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}gpu-intel.nix";
    };

    "15" = {
      name = "gpu-nvidia";
      description = "NVIDIA GPU initrd kernel module";
      info = "NVIDIA GPU: loads nouveau in initrd so Plymouth shows KMS content at native resolution during LUKS passphrase prompt. Only NVIDIA firmware is bundled.";
      file = "gpu-nvidia.nix";
      subdir = "nixos";
      category = "hardware";
      tags = [ "gpu" "nvidia" "initrd" "plymouth" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}gpu-nvidia.nix";
    };

    "16" = {
      name = "security";
      description = "System security hardening";
      info = "Security hardening: kernel sysctl hardening (dmesg/kptr/bpf/network), sudo password enforcement, optional fail2ban, and security auditing tools.";
      file = "security.nix";
      subdir = "nixos";
      category = "security";
      tags = [ "security" "hardening" "firewall" "audit" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}security.nix";
    };

    "17" = {
      name = "shell";
      description = "ZSH with OhMyZsh, Starship prompt";
      info = "Shell customization: ZSH with OhMyZsh plugins (git, sudo, extract), syntax highlighting, autosuggestions, Starship prompt, zoxide directory jumper, and thefuck command correction.";
      file = "shell.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "shell" "zsh" "terminal" "prompt" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}shell.nix";
    };

    "18" = {
      name = "fonts";
      description = "Fonts including Nerd Fonts";
      info = "Font configuration: Inter, Noto Fonts (CJK/Emoji), JetBrains Mono, Fira Code, and optional Nerd Fonts patched variants with proper fontconfig defaults.";
      file = "fonts.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "fonts" "typography" "nerdfonts" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}fonts.nix";
    };

    "19" = {
      name = "media";
      description = "Media codecs, VA-API, VLC, FFmpeg";
      info = "Media codecs and playback: FFmpeg with hardware acceleration, VLC/mpv/imv players, Intel/Radeon VA-API drivers, and thumbnail generation.";
      file = "media.nix";
      subdir = "nixos";
      category = "system";
      tags = [ "media" "codecs" "video" "audio" "playback" ];
      deps = [ ];
      version = "1.0.0";
      url = "${baseUrl}/${moduleDir "nixos"}media.nix";
    };
  };

  # ─── Reverse Mapping: filename -> module id ───────────────────────────────
  filenameToId = builtins.listToAttrs (
    builtins.map (id: {
      name = modules.${id}.file;
      value = id;
    }) (builtins.attrNames modules)
  );

  # ─── Category Index ──────────────────────────────────────────────────────
  modulesByCategory =
    let
      addToCategory = acc: id:
        let cat = modules.${id}.category;
            existing = acc.${cat} or [ ];
        in acc // { ${cat} = existing ++ [ id ]; };
    in builtins.foldl' addToCategory { } (builtins.attrNames modules);

  # ─── Read Module State ──────────────────────────────────────────────────
  readModuleState = { };

  # ─── Helper: is module enabled? ─────────────────────────────────────────
  isEnabled = state: id:
    let modState = state.${id} or { };
    in if builtins.hasAttr "enabled" modState then modState.enabled else true;

  # ─── Helper: should import a file? ──────────────────────────────────────
  shouldImportFile = state: filename:
    let matchedId = filenameToId.${filename} or null;
    in if matchedId == null then true else isEnabled state matchedId;

  # ─── Get enabled/disabled IDs ───────────────────────────────────────────
  getEnabledIds = state:
    builtins.filter (id: isEnabled state id) (builtins.attrNames modules);

  getDisabledIds = state:
    builtins.filter (id: !isEnabled state id) (builtins.attrNames modules);

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

  # ─── Reverse deps ────────────────────────────────────────────────────────
  getReverseDeps = id:
    builtins.filter (otherId:
      builtins.elem id modules.${otherId}.deps
    ) (builtins.attrNames modules);

  # ─── Generate state summary ────────────────────────────────────────────
  generateStateSummary = state:
    builtins.map (id:
      let
        mod = modules.${id};
        enabled = isEnabled state id;
      in {
        inherit id;
        name = mod.name;
        description = mod.description;
        category = mod.category;
        tags = mod.tags;
        version = mod.version;
        file = mod.file;
        subdir = mod.subdir;
        inherit enabled;
        deps = mod.deps;
      }
    ) (builtins.attrNames modules);

  # ─── Module path helpers ───────────────────────────────────────────────
  getModulePath = subdir: filename:
    let baseDir = ./.;
    in baseDir + "/../modules/optional/${subdir}/${filename}";

in {
  inherit
    modules filenameToId modulesByCategory
    stateFilePath stateDir
    readModuleState isEnabled shouldImportFile
    getEnabledIds getDisabledIds
    validateDeps getReverseDeps
    generateStateSummary getModulePath
    ;
  moduleIds = builtins.sort builtins.lessThan (builtins.attrNames modules);
  categories = builtins.attrNames modulesByCategory;
}
