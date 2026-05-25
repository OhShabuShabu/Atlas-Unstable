{ lib, ... }:

{
  # Load amdgpu in initrd so Plymouth shows KMS at native resolution during LUKS prompt.
  # Only the matching GPU's firmware gets bundled — keeps initrd small for /boot.
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.initrd.availableKernelModules = [ "amdgpu" ];
}
