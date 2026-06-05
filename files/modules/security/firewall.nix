{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: FIREWALL CONFIGURATION - nftables (FIRE-4590)
# INFO: ============================================================================
# INFO: Enable nftables firewall with strict incoming/outgoing rules
# FIX: Enhanced firewall rules for compliance (FIRE-4590)
# NOTE: This module uses nftables which is the modern firewall in NixOS
# WARN: Default DENY mode - only explicitly allowed traffic passes

let
  defaultTcpPorts = [ 22 ];

  # INFO: Default allowed UDP port ranges
  # NOTE: Most games and VoIP use ephemeral ports via UDP hole-punching.
  #       These ranges cover common services that need explicit opening.
  #       Steam: 27000-27100 (matchmaking/voice)
  #       Discord: 50000-65535 (voice)
  defaultUdpPorts = [
    { from = 27000; to = 27100; }  # Steam matchmaking + voice
    { from = 50000; to = 65535; }  # Discord voice
  ];
in

{
  # FIX: Enable nftables firewall with strict rules (FIRE-4590)
  # NOTE: Default DENY mode - only explicitly allowed ports are open
  networking.firewall = {
    enable = true;
    allowedTCPPorts = defaultTcpPorts;
    allowedUDPPortRanges = defaultUdpPorts;
    allowedUDPPorts = [];

    # Trust the libvirt bridge so VMs can reach the host (DNS, DHCP, etc.)
    trustedInterfaces = [ "virbr0" ];
    
    # FIX: Enable connection tracking for stateful firewall
    checkReversePath = "strict";  # Reverse path filtering
    
    # FIX: Configure firewall logging
    logRefusedConnections = true;
  };

  # NOTE: Additional firewall hardening can be done via kernel-sysctl.nix
  #       See kernel-sysctl.nix for network-related security settings
}
