{ pkgs, lib, config, ... }:

# ============================================================================
# NVIDIA GPU CONFIGURATION
# ============================================================================
# Proprietary NVIDIA driver with nvidia_drm modesetting for Wayland.
# Uses nvidia_modeset, nvidia_uvm, and nvidia_drm kernel modules.
#
# NOTE: Requires allowUnfree = true (set in configuration.nix).
# NOTE: Optimus/Prime laptops need special handling (not covered here).
# ============================================================================

let
  # Use the latest stable NVIDIA driver branch
  nvidiaPackage = config.boot.kernelPackages.nvidiaPackages.stable;
in {
  imports = [ ];

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    # NVIDIA proprietary driver handles its own acceleration
    extraPackages = [ ];
    extraPackages32 = [ ];
  };

  hardware.nvidia = {
    package = nvidiaPackage;

    # Enable modesetting for Wayland (required for Niri)
    modesetting.enable = true;

    # Enable NVENC/NVDEC hardware encoding
    nvencSupport = true;

    # Enable CUDA support
    cudaSupport = true;

    # Power management (requires GPU firmware)
    powerManagement.enable = true;

    # Use NVMe for faster runtime PM
    powerManagement.finegrained = false;

    # Dynamic Boost (laptop GPU power optimization)
    dynamicBoost.enable = true;

    # Open kernel module (newer GPUs: Turing+)
    open = false;
  };

  # Load NVIDIA modules in initrd for early KMS
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  boot.initrd.availableKernelModules = [ "nvidia" ];

  # Force NVreg_PreserveVideoMemoryAllocations for Wayland session persistence
  boot.extraModprobeConfig = ''
    options nvidia_drm modeset=1 fbdev=1
    options nvidia NVreg_PreserveVideoMemoryAllocations=1
    options nvidia NVreg_TemporaryFilePath=/var/tmp
  '';

  environment.systemPackages = with pkgs; [
    nvidia-vaapi-driver       # VA-API via NVDEC
    nvidia-settings           # GUI control panel
  ];
}
