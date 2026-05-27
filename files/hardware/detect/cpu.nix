{ lib, ... }:

# ============================================================================
# CPU VENDOR DETECTION
# ============================================================================
# Reads /proc/cpuinfo to detect Intel vs AMD vs generic CPU.
# Falls back to "generic" if /proc/cpuinfo is unavailable (e.g., CI build, pure eval).
#
# NOTE: Guards readFile with builtins.pathExists because pathExists returns false
# cleanly in pure evaluation mode (nixos-install), while tryEval does NOT catch
# readFile's path access errors. The guarded readFile is lazy — the then-branch
# is never evaluated in pure mode.
#
# The detected vendor controls which CPU-specific module is imported:
#   - "intel"   → imports files/hardware/cpu/intel.nix
#   - "amd"     → imports files/hardware/cpu/amd.nix  
#   - "generic" → imports no CPU-specific module (uses safe defaults)
#
# Manual override:
#   hardware.cpu.vendor = lib.mkForce "amd";
# ============================================================================

let
  # Read /proc/cpuinfo — guarded by pathExists to avoid pure-eval crash
  # pathExists returns false for inaccessible paths in pure mode (no error)
  cpuInfo = if builtins.pathExists "/proc/cpuinfo"
    then builtins.readFile "/proc/cpuinfo"
    else "";
  
  # Detect vendor from CPU flags/vendor string
  detected = if cpuInfo != "" then
    if builtins.match ".*GenuineIntel.*" cpuInfo != null then "intel"
    else if builtins.match ".*AuthenticAMD.*" cpuInfo != null then "amd"
    else "generic"
  else "generic";
in {
  options.hardware.cpu = {
    vendor = lib.mkOption {
      type = lib.types.enum [ "intel" "amd" "generic" ];
      default = detected;
      defaultText = lib.literalExpression "Auto-detected from /proc/cpuinfo";
      description = ''
        CPU vendor for hardware-specific kernel modules and microcode updates.
        Auto-detected at evaluation time from /proc/cpuinfo.
        Set manually to override:
        - "intel"   → kvm-intel, intel microcode, intel_pstate
        - "amd"     → kvm-amd, amd microcode, amd_pstate
        - "generic" → safe defaults (no vendor-specific optimization)
      '';
    };

    hasVirtualization = lib.mkOption {
      type = lib.types.bool;
      default = detected != "generic";
      defaultText = lib.literalExpression "true if CPU vendor detected";
      description = "Whether the CPU supports hardware virtualization extensions (VMX/SVM).";
      readOnly = true;
    };
  };
}
