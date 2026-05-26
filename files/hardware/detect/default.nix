{ lib, ... }:

# ============================================================================
# HARDWARE DETECTION INFRASTRUCTURE
# ============================================================================
# Provides runtime hardware detection via /proc and /sys filesystem reads
# at evaluation time (nixos-rebuild runs on the target machine).
#
# Each submodule defines an option that defaults to the auto-detected value.
# Manual overrides are always possible:
#
#   hardware.cpu.vendor = lib.mkForce "amd";     # Force AMD CPU config
#   hardware.gpu.vendor = lib.mkForce "nvidia";  # Force NVIDIA GPU config
#   hardware.memory.totalMB = lib.mkForce 4096;  # Override detected RAM
#
# Fallback: If detection files are unavailable (e.g., CI, remote build),
# options default to "generic" / "unknown" / "2048" — a safe minimum that
# boots on any hardware without hardware-specific tuning.
# ============================================================================

{
  imports = [
    ./cpu.nix
    ./gpu.nix
    ./memory.nix
  ];
}
