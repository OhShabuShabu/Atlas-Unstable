{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: KERNEL BOOT PARAMETERS & MODULE BLOCKING
# INFO: ============================================================================
# INFO: Kernel command-line hardening and module security
# NOTE: Boot parameters use kernelParams, modules use modprobeConfig
# WARN: Some blocked modules may break hardware - review before deploying
# NOTE: Updated for NixOS 25.x/2026 security standards

let
  # INFO: Kernel boot parameters for security
  # NOTE: Enhanced with latest hardened profile recommendations
  bootParams = [
    # Boot experience
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "loglevel=3"

    # Systemd early boot config
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"

    # CPU performance tuning
    "intel_pstate=active"
    "tsc=reliable"

    # Security hardening
    "slab_nomerge"                       # INFO: Disable slab merging
    "init_on_alloc=1"                   # INFO: Zero memory on alloc
    "init_on_free=1"                    # INFO: Zero memory on free
    "page_poison=1"                      # FIX: Poison free pages (from hardened profile)
    "page_alloc.shuffle=1"              # INFO: Randomize page allocator
    "pti=on"                             # INFO: Page Table Isolation
    "randomize_kstack_offset=on"         # INFO: Randomize kernel stack
    # WARN: Breaks older binaries (GPU drivers, X11)
    # "vsyscall=none"                     # INFO: Disable vsyscalls
    "debugfs=off"                        # INFO: Disable debugfs
    # NOTE: oops=panic disabled - GPU drivers trigger non-fatal oops on newer kernels
    # "oops=panic"                        # INFO: Panic on oops
    # NOTE: lockdown disabled - prevents GPU driver and display from working on unstable
    # "lockdown=integrity"             # INFO: Kernel lockdown - prevents unsigned module loading
    "slab_merge=off"                    # INFO: Explicitly disable slab merging
    # FIX: Additional boot hardening
    # WARN: Can crash systems without IOMMU support
    # "iommu=force"                       # INFO: Force IOMMU for DMA protection
    "elevator=none"                     # INFO: Use none scheduler (simplest, least attack surface)
    # WARN: module.sig_enforce will BOOT FAIL if any kernel module is unsigned
    # "module.sig_enforce=1"              # INFO: Only load signed modules
    # WARN: Entropy starvation causes minutes-long boot delays on some hardware
    # "random.trust_cpu=off"              # INFO: Don't trust CPU RNG entropy
    # "random.trust_bootloader=off"       # INFO: Don't trust bootloader RNG entropy
    "console=tty0"                      # INFO: Restrict console to main display
    "intel_iommu=on"                    # INFO: Enable Intel IOMMU (VT-d)
  ];

  # INFO: Modules to block via modprobe (returns /bin/false)
  # NOTE: Hardware that needs these modules should add them to boot.kernelModules
  blockedModules = ''
    install firewire-core /bin/false
    install firewire_core /bin/false
    install firewire-ohci /bin/false
    install firewire_ohci /bin/false
    install firewire_sbp2 /bin/false
    install firewire-sbp2 /bin/false
    install firewire-net /bin/false
    install thunderbolt /bin/false
    install ohci1394 /bin/false
    install sbp2 /bin/false
    install dv1394 /bin/false
    install raw1394 /bin/false
    install video1394 /bin/false
    # WARN: usb-storage BLOCKED - breaks USB boot and initrd USB keyboard
    # WARN: Uncomment below only if you're sure you don't boot from USB
    # install usb-storage /bin/false
  '';

  # INFO: Blacklisted kernel modules (completely disabled)
  # NOTE: Enhanced with additional modules from hardened profile
  blacklistedModules = [
    # INFO: Rare/unused network protocols
    "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom"
    "x25" "rose" "decnet" "econet" "af_802154" "ipx" "appletalk"
    "psnap" "p8023" "p8022" "can" "atm"
    # INFO: Rare filesystems (from hardened profile)
    # WARN: udf/erofs/squashfs kept - NixOS initrd may need them
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus"
    "adfs" "affs" "bfs" "befs" "efs" "exofs"
    "minix" "nilfs2" "ntfs" "omfs" "qnx4" "qnx6" "sysv" "ufs"
    # INFO: Additional rare filesystems
    "hpfs" "romfs"
  ];
in

{
  # INFO: Apply kernel boot parameters
  boot.kernelParams = bootParams;

  # Silent boot - reduce console noise
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # INFO: Apply module blocking config
  boot.extraModprobeConfig = blockedModules;

  # INFO: Blacklist dangerous modules
  boot.blacklistedKernelModules = blacklistedModules;

  # NOTE: Lock kernel module loading is now handled by security.lockKernelModules
  #       in configuration.nix - keeping this as backup
  # WARN: This service may conflict with security.lockKernelModules
  # systemd.services."lock-kernel-modules".enable = false;
}