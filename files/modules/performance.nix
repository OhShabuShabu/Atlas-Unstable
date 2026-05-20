# INFO: ============================================================================
# INFO: PERFORMANCE MODULE
# INFO: Optimized for both low-end and high-end systems
# INFO: ============================================================================

{ lib, ... }:

{
  # INFO: ============================================================================
  # SECTION 1: KERNEL MODULES
  # ============================================================================
  boot.kernelModules = [ "tcp_bbr" ];

  # INFO: ============================================================================
  # SECTION 2: CPU PERFORMANCE
  # ============================================================================
  powerManagement.cpuFreqGovernor = "performance";

  # INFO: ============================================================================
  # SECTION 3: NIX PERFORMANCE
  # ============================================================================
  nix.settings = {
    max-jobs = lib.mkDefault "auto";
    cores = lib.mkDefault 0;  # INFO: Use all available cores
    auto-optimise-store = true;  # INFO: Deduplicate store
    min-free = 500;
  };

  # INFO: Nix garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
  };

  # INFO: ============================================================================
  # SECTION 4: BOOT PERFORMANCE
  # ============================================================================
  boot = {
    kernelParams = [ "quiet" "loglevel=3" ];
    initrd.verbose = false;
    consoleLogLevel = 0;
  };
}