{ pkgs, lib, ... }:

# ============================================================================
# GENERIC CPU CONFIGURATION
# ============================================================================
# Safe defaults that work on any CPU vendor.
# No vendor-specific microcode, no vendor-specific pstate drivers.
# Used as fallback when CPU vendor cannot be detected.
# ============================================================================

{
  imports = [ ];

  # No vendor-specific microcode (requires unfree firmware)
  # hardware.cpu.intel.updateMicrocode = false;
  # hardware.cpu.amd.updateMicrocode = false;

  boot.kernelParams = [
    # IOMMU: try to enable if available, don't fail if not
    # "iommu=pt" is safer than "intel_iommu=on"/"amd_iommu=on" — works on both
    "iommu=pt"
  ];
}
