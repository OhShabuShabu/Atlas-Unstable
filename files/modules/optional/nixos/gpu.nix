{ config, lib, ... }:

# ============================================================================
# GPU INITRD KERNEL MODULES (Optional Layer)
# ============================================================================
# Loads the detected GPU driver in initrd so Plymouth shows KMS content
# at native resolution during LUKS passphrase prompt.
#
# Detection is read from hardware.gpu.vendor (set by hardware/detect/gpu.nix).
# Only the matching GPU's firmware gets bundled — keeps initrd small for /boot.
#
# If the GPU vendor is "generic" (unknown/unsupported), no initrd GPU modules
# are loaded — Plymouth falls back to EFI framebuffer, which is functional
# albeit not at native resolution.
#
# Override:
#   hardware.gpu.vendor = lib.mkForce "intel";  # in configuration.nix
# ============================================================================

let
  gpuVendor = config.hardware.gpu.vendor;
  
  # Map GPU vendor to initrd kernel module name
  initrdModule = {
    amd = "amdgpu";
    intel = "i915";
    nvidia = "nvidia";
    generic = "";  # No vendor-specific module — use EFI framebuffer
  }.${gpuVendor} or "";
in {
  # Only add GPU initrd modules if we know the vendor
  boot.initrd.kernelModules = lib.mkIf (initrdModule != "") [ initrdModule ];
  boot.initrd.availableKernelModules = lib.mkIf (initrdModule != "") [ initrdModule ];
}
