{ pkgs, lib, ... }:

# ============================================================================
# INTEL CPU CONFIGURATION
# ============================================================================
# Intel-specific kernel parameters and microcode updates.
# Imported automatically when hardware.cpu.vendor == "intel".
# ============================================================================

{
  imports = [ ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  boot.kernelParams = [
    "intel_pstate=active"     # Active energy-efficient performance scaling
    "tsc=reliable"            # TSC is invariant on modern Intel CPUs
    "intel_iommu=on"          # Intel IOMMU for DMA protection + VFIO
  ];
}
