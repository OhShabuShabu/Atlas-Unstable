{ config, pkgs, lib, ... }:
{
  # ============================================================================
  # VIRTUALIZATION CONFIGURATION
  # ============================================================================
  # Enables: Docker, Podman, libvirt, Distrobox
  # ============================================================================

  # ============================================================================
  # SECTION 1: VIRT-MANAGER
  # ============================================================================
  # Enable Virt-Manager GUI
  programs.virt-manager.enable = true;


  # ============================================================================
  # SECTION 2: LIBVIRT CONFIGURATION
  # ============================================================================
  # Add user to libvirt group
  users.users.yusa.extraGroups = [ "libvirtd" ];

  # Enable libvirt daemon
  virtualisation.libvirtd = {
    enable = true;
    # Use nftables backend instead of iptables for kernel compatibility
    firewallBackend = "iptables";

    # Allow the VM to access the kvmfr IVSHMEM device (bypass cgroup restrictions)
    qemu.verbatimConfig = ''
      namespaces = []
      cgroup_device_acl = [
        "/dev/null", "/dev/full", "/dev/zero",
        "/dev/random", "/dev/urandom",
        "/dev/ptmx", "/dev/kvm",
        "/dev/kvmfr0",
        "/dev/rtc", "/dev/hpet"
      ]
    '';
  };

  # Ensure the default NAT network is defined, autostarted, and active
  # libvirtd loads persistent network XMLs from /var/lib/libvirt/qemu/networks/
  # but the default network may need to be explicitly started after boot
  systemd.services.libvirtd.postStart = ''
    ${pkgs.libvirt}/bin/virsh net-info default 2>/dev/null || {
      ${pkgs.libvirt}/bin/virsh net-define ${pkgs.libvirt}/var/lib/libvirt/qemu/networks/default.xml
    }
    ${pkgs.libvirt}/bin/virsh net-autostart default 2>/dev/null || true
    ${pkgs.libvirt}/bin/virsh net-start default 2>/dev/null || true
  '';

  # Mullvad VPN's nftables forward chain (inet family, priority 0, policy drop)
  # blocks all forwarded traffic not explicitly allowed — including VM NAT traffic.
  # Create an nftables chain at higher priority (-1) to accept forwarded traffic
  # from virbr0 before Mullvad's chain evaluates it.
  environment.etc."nftables/vm-forward.conf" = {
    mode = "0444";
    text = ''
      table inet allow-vm-forward {
        chain forward {
          type filter hook forward priority -1; policy accept;
          iif "virbr0" accept
        }
      }
    '';
  };

  systemd.services.nft-vm-forward = {
    description = "Allow VM forwarded traffic through nftables";
    after = [ "libvirtd.service" ];
    bindsTo = [ "libvirtd.service" ];
    partOf = [ "libvirtd.service" ];
    wantedBy = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f /etc/nftables/vm-forward.conf";
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet allow-vm-forward 2>/dev/null || true";
      ExecReload = "${pkgs.nftables}/bin/nft -f /etc/nftables/vm-forward.conf";
    };
  };

  # Workaround: upstream libvirtd.service uses LoadCredentialEncrypted which
  # requires TPM2 or systemd credential secret — strip it to avoid failure
  systemd.services.libvirtd.serviceConfig.LoadCredentialEncrypted = lib.mkForce [ "" ];


  # Load kernel modules needed by libvirt for QoS/traffic shaping on virtual networks
  boot.kernelModules = [
    "sch_htb"    # Hierarchical Token Bucket — used by libvirt default network QoS
    "sch_sfq"    # Stochastic Fairness Queueing
    "sch_fq"     # Fair Queueing
    "sch_fq_codel" # Fair Queueing with Controlled Delay
    "sch_prio"   # Priority qdisc
    "cls_u32"    # U32 classifier — used by libvirt for traffic filtering
    "act_police" # Policing action
    "act_csum"   # Checksum action — needed by libvirt default network QoS

    # kvmfr — Looking Glass IVSHMEM device for VM framebuffer relay
    "kvmfr"
  ];

  # Include the kvmfr kernel module package (not built into the default NixOS kernel)
  boot.extraModulePackages = with config.boot.kernelPackages; [ kvmfr ];

  # ============================================================================
  # SECTION 3: DOCKER CONFIGURATION
  # ============================================================================
  # Enable Docker
  virtualisation.docker.enable = true;

  # NOTE: rootless Docker available via virtualisation.docker.rootless.enable if needed

  # Enable SPICE USB redirection (for VM device passthrough)
  virtualisation.spiceUSBRedirection.enable = true;


  # ============================================================================
  # SECTION 4: PODMAN CONFIGURATION
  # ============================================================================
  # Enable Podman (Docker alternative)
  virtualisation.podman = {
    enable = true;
  };


  # ============================================================================
  # SECTION 5: VIRTUALIZATION TOOLS
  # ============================================================================
  # Additional virtualization packages
  environment.systemPackages = with pkgs; [
    # Distrobox for containerized development environments
    distrobox

    # Docker tools
    docker
    docker-compose

    # Looking Glass — KVM Frame Relay for low-latency VM display
    looking-glass-client
  ];


  # ============================================================================
  # SECTION 6: LOOKING GLASS — IVSHMEM SETUP
  # ============================================================================
  # Looking Glass shares the VM framebuffer via a dedicated IVSHMEM device (/dev/kvmfr0).
  # The kvmfr kernel module creates this device when loaded (in-kernel since 6.2).

  # Allocate 64MB to the kvmfr static IVSHMEM device (enough for 4K framebuffer)
  # The module creates /dev/kvmfr0 automatically when loaded with static_size_mb > 0
  boot.extraModprobeConfig = ''
    options kvmfr static_size_mb=64
  '';

  # Set permissions so the user and libvirt can access the shared memory device
  services.udev.extraRules = ''
    KERNEL=="kvmfr*", OWNER="yusa", GROUP="kvm", MODE="0660"
  '';

  # Allow QEMU/libvirt to open /dev/kvmfr0 under AppArmor confinement
  security.apparmor.includes."local/abstractions/libvirt-qemu" = ''
    # Looking Glass IVSHMEM device
    /dev/kvmfr0 rw,
  '';

  # Allocate 2MB hugepages for Looking Glass shared memory
  # 1024 pages × 2048K = 2GB — adjust based on VM resolution needs
  # For 1080p: ~256 pages (512MB) is plenty
  boot.kernel.sysctl."vm.nr_hugepages" = 1024;

  # System-wide Looking Glass config — points to the kvmfr IVSHMEM device
  environment.etc."xdg/looking-glass/client.ini" = {
    text = ''
      [app]
      shmFile=/dev/kvmfr0
    '';
  };
}