{ lib, ... }:

# ============================================================================
# GPU VENDOR DETECTION
# ============================================================================
# Reads /proc/bus/pci/devices to detect AMD vs Intel vs NVIDIA vs generic GPU.
# Falls back to "generic" if detection is unavailable.
#
# NOTE: Guards readFile with builtins.pathExists because pathExists returns false
# cleanly in pure evaluation mode (nixos-install), while tryEval does NOT catch
# readFile's path access errors. The guarded readFile is lazy — the then-branch
# is never evaluated in pure mode.
#
# Manual override:
#   hardware.gpu.vendor = lib.mkForce "intel";
# ============================================================================

let
  # PCI vendor detection via /proc/bus/pci/devices
  # Vendor IDs: 1002=AMD, 8086=Intel, 10de=NVIDIA
  pciDevices = if builtins.pathExists "/proc/bus/pci/devices"
    then builtins.readFile "/proc/bus/pci/devices"
    else "";

  hasAmd = if pciDevices != "" then
    builtins.match ".*1002.*" pciDevices != null
    else false;
  hasIntel = if pciDevices != "" then
    builtins.match ".*8086.*" pciDevices != null
    else false;
  hasNvidia = if pciDevices != "" then
    builtins.match ".*10de.*" pciDevices != null
    else false;

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
      defaultText = lib.literalExpression "Auto-detected from /proc/bus/pci/devices";
      description = ''
        GPU vendor for hardware-specific drivers and firmware.
        Auto-detected at evaluation time from PCI vendor IDs.
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
