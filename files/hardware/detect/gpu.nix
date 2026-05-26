{ lib, ... }:

# ============================================================================
# GPU VENDOR DETECTION
# ============================================================================
# Reads /sys/class/drm/ to detect AMD vs Intel vs NVIDIA vs generic GPU.
# Falls back to "generic" if detection is unavailable.
#
# The detected vendor controls which GPU module is imported and which
# initrd kernel modules are loaded for KMS (Kernel Mode Setting):
#   - "amd"     → amdgpu driver, RADV Vulkan
#   - "intel"   → i915 driver, intel-media-driver VA-API
#   - "nvidia"  → nvidia driver (proprietary), nvidia-vaapi-driver
#   - "generic" → no GPU-specific drivers (uses modesetting/KMS fallback)
#
# NOTE: Detection reads /sys/class/drm/ which lists available DRM devices.
# Each GPU driver creates a directory like "card0" or "card0-<vendor>".
# We also check /sys/devices/ for PCI vendor IDs as a secondary source.
#
# Manual override:
#   hardware.gpu.vendor = lib.mkForce "intel";
# ============================================================================

let
  # Try DRM class detection (primary method)
  drmDir = builtins.tryEval (builtins.readDir "/sys/class/drm");
  
  hasAmdDrm = if drmDir.success then
    builtins.any (n: builtins.match ".*amdgpu.*" n != null) (builtins.attrNames drmDir.value)
    else false;
  hasIntelDrm = if drmDir.success then
    builtins.any (n: builtins.match ".*i915.*" n != null || builtins.match ".*intel.*" n != null) (builtins.attrNames drmDir.value)
    else false;
  hasNvidiaDrm = if drmDir.success then
    builtins.any (n: builtins.match ".*nvidia.*" n != null) (builtins.attrNames drmDir.value)
    else false;

  # Fallback: try PCI vendor detection via lspci (less reliable)
  pciDevices = builtins.tryEval (builtins.readFile "/proc/bus/pci/devices");
  hasAmdPci = if pciDevices.success then
    builtins.match ".*1002.*" pciDevices.value != null  # AMD PCI vendor ID
    else false;
  hasIntelPci = if pciDevices.success then
    builtins.match ".*8086.*" pciDevices.value != null  # Intel PCI vendor ID
    else false;
  hasNvidiaPci = if pciDevices.success then
    builtins.match ".*10de.*" pciDevices.value != null  # NVIDIA PCI vendor ID
    else false;

  # Combine: DRM detection is primary, PCI is fallback
  hasAmd = hasAmdDrm || (!drmDir.success && hasAmdPci);
  hasIntel = hasIntelDrm || (!drmDir.success && hasIntelPci);
  hasNvidia = hasNvidiaDrm || (!drmDir.success && hasNvidiaPci);

  # Priority: If multiple GPUs detected, prefer AMD > NVIDIA > Intel
  # (AMD has best open-source driver support on modern kernels)
  detected = if hasAmd then "amd"
    else if hasNvidia then "nvidia"
    else if hasIntel then "intel"
    else "generic";
in {
  options.hardware.gpu = {
    vendor = lib.mkOption {
      type = lib.types.enum [ "amd" "intel" "nvidia" "generic" ];
      default = detected;
      defaultText = lib.literalExpression "Auto-detected from /sys/class/drm/";
      description = ''
        GPU vendor for hardware-specific drivers and firmware.
        Auto-detected at evaluation time from /sys/class/drm/.
        Set manually to override:
        - "amd"     → amdgpu initrd, RADV, VA-API (amdgpu)
        - "intel"   → i915 initrd, Intel media driver, VA-API
        - "nvidia"  → nvidia and nvidia_modeset, nvidia-vaapi-driver
        - "generic" → no GPU-specific drivers (software rendering fallback)
      '';
    };

    hasAmd = lib.mkOption {
      type = lib.types.bool;
      default = hasAmd;
      description = "Whether an AMD GPU was detected.";
      readOnly = true;
    };

    hasIntel = lib.mkOption {
      type = lib.types.bool;
      default = hasIntel;
      description = "Whether an Intel GPU was detected.";
      readOnly = true;
    };

    hasNvidia = lib.mkOption {
      type = lib.types.bool;
      default = hasNvidia;
      description = "Whether an NVIDIA GPU was detected.";
      readOnly = true;
    };
  };

  # Hardware graphics always enabled for all GPU types
  config = {
    hardware.graphics.enable = lib.mkDefault true;
  };
}
