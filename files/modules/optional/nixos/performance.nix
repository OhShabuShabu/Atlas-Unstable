# ============================================================================
# MODULE: performance
# CATEGORY: system
# VERSION: 1.0.0
# TAGS: performance nix gc kernel
# DEPS: none
# INFO: CPU governor, TCP BBR, Nix GC tuning, ZRAM
# ============================================================================
{ lib, ... }:

{
  boot.kernelModules = [ "tcp_bbr" ];

  powerManagement.cpuFreqGovernor = "performance";

  nix.settings = {
    max-jobs = lib.mkDefault "auto";
    cores = lib.mkDefault 0;
    auto-optimise-store = true;
    min-free = 500000000;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };

  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;
}
