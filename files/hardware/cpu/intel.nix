{ pkgs, lib, ... }:

{
  imports = [ ];

  hardware.cpu.intel.updateMicrocode = true;

  boot.kernelParams = [ "intel_pstate=active" ];
}
