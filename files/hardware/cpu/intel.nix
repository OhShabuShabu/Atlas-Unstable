{ config, pkgs, lib, ... }:

# ============================================================================
# INTEL CPU CONFIGURATION
# ============================================================================
# Intel-specific kernel parameters and microcode updates.
# Guarded by mkIf so it only activates when hardware.cpu.vendor == "intel".
# ============================================================================

lib.mkIf (config.hardware.cpu.vendor == "intel") {
  imports = [ ];

  boot.kernelParams = [
    "intel_pstate=active"     # Active energy-efficient performance scaling
    "tsc=reliable"            # TSC is invariant on modern Intel CPUs
    "intel_iommu=on"          # Intel IOMMU for DMA protection + VFIO
  ];
}
