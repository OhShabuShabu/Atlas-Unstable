{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: KERNEL SYSCTL HARDENING
# INFO: ============================================================================
# INFO: Critical kernel security settings for attack prevention
# NOTE: These settings follow NixOS 25.x hardened profile recommendations
# NOTE: Landlock, Yama, BPF are now enabled by default in NixOS 25.05+
# WARN: Some settings may affect functionality (e.g., perf_event_paranoid)

let
  # INFO: Core dump and memory protection settings
  # NOTE: Updated for 2026 security standards
  memorySettings = {
    "fs.suid_dumpable" = 0;               # INFO: Prevent core dumps from setuid programs
    "vm.mmap_rnd_bits" = 32;               # INFO: ASLR - randomize memory addresses
    "vm.mmap_rnd_compat_bits" = 16;       # INFO: ASLR for 32-bit compatibility
    "kernel.randomize_va_space" = 2;       # INFO: Enable full address space randomization
  };

  # INFO: Kernel pointer/log protection
  # NOTE: kptr_restrict=2 hides even from privileged processes
  kernelProtection = {
    "kernel.kptr_restrict" = 2;            # FIX: Hide kernel pointers even for CAP_SYSLOG
    "kernel.dmesg_restrict" = 1;           # INFO: Restrict kernel log access
  };

  # INFO: Exploit mitigation settings
  # NOTE: Enhanced for 2026 threat landscape
  exploitMitigation = {
    "kernel.unprivileged_bpf_disabled" = 1;   # INFO: Disable unprivileged eBPF
    "dev.tty.ldisc_autoload" = 0;               # INFO: Block unauthorized TTY disciplines
    # WARN: Breaks Wine/proton/VMs that rely on userfaultfd
    # "vm.unprivileged_userfaultfd" = 0;         # INFO: Disable userfaultfd
    "kernel.kexec_load_disabled" = 1;          # INFO: Disable kexec
    # WARN: SysRq useful for debugging hard freezes
    # "kernel.sysrq" = 0;                         # INFO: Disable SysRq completely
    # WARN: perf_event_paranoid=3 breaks profiling, some GPU tools
    # "kernel.perf_event_paranoid" = 3;           # INFO: Restrict perf_event usage
    # WARN: Disabling BPF JIT degrades eBPF performance significantly
    # net.core.bpf_jit_enable = 0;
  };

  # INFO: Network security settings
  # NOTE: Enhanced with additional protections
  networkSettings = {
    "net.ipv4.tcp_syncookies" = 1;           # INFO: Enable SYN cookies (DoS protection)
    "net.ipv4.tcp_rfc1337" = 1;               # INFO: Prevent TIME-WAIT assassination
    "net.ipv4.conf.default.rp_filter" = 1;    # INFO: Reverse path filtering
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0; # INFO: Disable ICMP redirects
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.icmp_echo_ignore_all" = 1;       # INFO: Ignore ICMP echo requests
    # WARN: Docker and libvirt need IP forwarding for NAT networking
    #       Setting mkForce to ensure it stays on across service restarts
    "net.ipv4.conf.all.forwarding" = lib.mkForce 1;
    "net.ipv6.conf.all.forwarding" = lib.mkForce 1;
    "net.ipv4.conf.default.accept_source_route" = 0;  # INFO: Disable source routing
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_ra" = 0;        # INFO: Disable router advertisements
    "net.ipv6.conf.default.accept_ra" = 0;
  };

  # INFO: Additional Lynis-recommended settings
  # NOTE: Enhanced with bpf_jit_harden=2 from hardened profile
  lynisSettings = {
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "kernel.core_uses_pid" = 1;
    "net.core.bpf_jit_harden" = 2;            # FIX: Hardens BPF JIT (from hardened profile)
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "kernel.yama.ptrace_scope" = 1;           # INFO: Allow parent-child ptrace (required by Sober/Flatpak)
  };

  # INFO: Extended hardening from latest NixOS hardened profile
  # NOTE: Provides defense-in-depth beyond standard Lynis recommendations
  extendedHardening = {
    # FIX: ARP security - ignore unsolicited ARP replies
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.all.arp_filter" = 1;
    # FIX: Disable shared media for routing security
    "net.ipv4.conf.all.shared_media" = 0;
    "net.ipv4.conf.default.shared_media" = 0;
    # FIX: TCP SYN flood protection
    "net.ipv4.tcp_syncookies" = 1;            # Already set above - reinforcing
    "net.ipv4.tcp_syn_retries" = 3;
    "net.ipv4.tcp_synack_retries" = 3;
    "net.ipv4.tcp_max_syn_backlog" = 2048;
    # FIX: Disable TCP timestamps (info leak reduction)
    "net.ipv4.tcp_timestamps" = 0;
    # FIX: Kernel panic behaviour
    "kernel.panic" = 10;
    # WARN: GPU drivers can trigger non-fatal oops during boot - panic_on_oops causes boot-loop
    # "kernel.panic_on_oops" = 1;
    # WARN: Benign NMI events (common on modern hardware) trigger panic
    # "kernel.panic_on_unrecovered_nmi" = 1;
    # "kernel.panic_on_io_nmi" = 1;
    # FIX: Restrict ksm (Kernel Same-page Merging - attack surface)
    # NOTE: Only effective if KSM is compiled in (CONFIG_KSM)
    # "kernel.ksm.max_kernel_pages" = 0;
    # "kernel.ksm.use_zero_pages" = 0;
    # WARN: Do NOT set net.core.optmem_max = 0 - breaks SO_ATTACH_FILTER
    #       which systemd-logind needs for udev event monitoring
  };

  # INFO: Filesystem protection
  filesystemSettings = {
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
  };

  # INFO: TCP optimization (performance-friendly)
  # WARN: Disabled for maximum security - uncomment if needed
  tcpOptimization = {
    # "net.ipv4.tcp_fastopen" = 3;
    # "net.ipv4.tcp_congestion_control" = "bbr";
    # "net.core.default_qdisc" = "cake";
  };

  # INFO: User namespace settings (required for containers)
  # NOTE: Can be disabled for higher security if no containers are used
  userNamespaceSettings = { };
in

{
  # INFO: Merge all kernel sysctl settings
  boot.kernel.sysctl = memorySettings // kernelProtection // exploitMitigation 
    // networkSettings // lynisSettings // extendedHardening // filesystemSettings
    // tcpOptimization // userNamespaceSettings;

  # INFO: LSM (Linux Security Modules) - now defaults to landlock,yama,bpf in NixOS 25.05+
  # NOTE: We explicitly configure this to ensure it's set correctly
  #       AppArmor can be added here when enabled in configuration.nix
  # security.lsm = [ "landlock" "yama" "bpf" ];  # Already defaults in NixOS 25.05+
}