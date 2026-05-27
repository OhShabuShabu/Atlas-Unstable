{ lib, ... }:

# ============================================================================
# MEMORY DETECTION
# ============================================================================
# Reads /proc/meminfo to detect total physical RAM.
# Falls back to 2048 MB (2 GB) if /proc/meminfo is unavailable (e.g., pure eval).
#
# NOTE: Guards readFile with builtins.pathExists because pathExists returns false
# cleanly in pure evaluation mode, while tryEval does NOT catch readFile's errors.
#
# The detected values control:
#   - Swap file size (proportional to RAM)
#   - tmpfs size limits (proportional to RAM)
#   - Nix build parallelism (max-jobs, cores)
#
# Manual override:
#   hardware.memory.totalMB = lib.mkForce 16384;  # Force 16 GB
# ============================================================================

let
  # Read /proc/meminfo — guarded by pathExists to avoid pure-eval crash
  memInfo = if builtins.pathExists "/proc/meminfo"
    then builtins.readFile "/proc/meminfo"
    else "";
  
  # Parse MemTotal from /proc/meminfo (in kB, convert to MB)
  totalMB = if memInfo != "" then
    let
      # Extract the MemTotal value (e.g., "MemTotal:       16354328 kB")
      match = builtins.match "[^0-9]*\n?MemTotal:\\s*(\\d+)\\s*kB" memInfo;
      memTotalKB = if match != null then builtins.fromJSON (builtins.head match) else 0;
    in
      if memTotalKB > 0 then memTotalKB / 1024 else 2048  # fallback to 2GB
    else 2048;  # fallback if /proc/meminfo unavailable

  # Tier classification for performance profile hints
  tier = if totalMB >= 32768 then "high"      # 32GB+
    else if totalMB >= 16384 then "mid-high"  # 16-32GB
    else if totalMB >= 8192 then "mid"        # 8-16GB
    else if totalMB >= 4096 then "low-mid"    # 4-8GB
    else "low";                                # < 4GB
    
in {
  options.hardware.memory = {
    totalMB = lib.mkOption {
      type = lib.types.int;
      default = totalMB;
      defaultText = lib.literalExpression "Auto-detected from /proc/meminfo";
      description = ''
        Total system RAM in megabytes.
        Auto-detected from /proc/meminfo at evaluation time.
        Set manually to override adaptive settings (swap size, tmpfs, etc.).
      '';
    };

    tier = lib.mkOption {
      type = lib.types.enum [ "low" "low-mid" "mid" "mid-high" "high" ];
      default = tier;
      description = ''
        Memory tier classification based on total RAM:
        - "low"      (< 4 GB)   — ultra-budget/older hardware
        - "low-mid"  (4-8 GB)   — budget
        - "mid"      (8-16 GB)  — mainstream
        - "mid-high" (16-32 GB) — enthusiast
        - "high"     (32+ GB)   — workstation/server
      '';
      readOnly = true;
    };

    swapSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 
        if totalMB >= 32768 then 8192      # 32GB+ RAM: 8GB swap
        else if totalMB >= 16384 then 8192 # 16-32GB RAM: 8GB swap  
        else if totalMB >= 8192 then 4096  # 8-16GB RAM: 4GB swap
        else if totalMB >= 4096 then 4096  # 4-8GB RAM: 4GB swap
        else 2048;                          # < 4GB RAM: 2GB swap
      defaultText = lib.literalExpression "Auto-calculated from totalMB: 25-50% of RAM";
      description = ''
        Recommended swap file size in megabytes.
        Scales with detected RAM to provide adequate headroom
        without wasting disk space on large machines.
      '';
    };

    tmpfsPercent = lib.mkOption {
      type = lib.types.int;
      default = 
        if totalMB >= 32768 then 10  # 32GB+: 10% for tmpfs (saves RAM)
        else if totalMB >= 16384 then 15
        else if totalMB >= 8192 then 20
        else 25;                       # < 8GB: 25% for tmpfs
      defaultText = lib.literalExpression "Scales inversely with RAM";
      description = ''
        Percentage of total RAM to allocate for tmpfs mounts.
        Higher on low-RAM systems (needs more headroom), lower on
        high-RAM systems (tmpfs rarely needs 25% of 32GB+).
      '';
    };
  };
}
