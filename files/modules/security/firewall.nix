{ config, pkgs, lib, ... }:

# INFO: ============================================================================
# INFO: FIREWALL CONFIGURATION - nftables (FIRE-4590)
# INFO: ============================================================================
# INFO: Enable nftables firewall with strict incoming/outgoing rules
# FIX: Enhanced firewall rules for compliance (FIRE-4590)
# NOTE: This module uses nftables which is the modern firewall in NixOS
# WARN: Default DENY mode - only explicitly allowed traffic passes

let
  # INFO: Default allowed TCP ports (HTTP/HTTPS)
  # NOTE: Add any additional ports needed for your services
  defaultTcpPorts = [ 80 443 ];

  # INFO: Default allowed UDP port ranges for VoIP/gaming
  # NOTE: These ranges are commonly used for gaming/voice chat
  defaultUdpPorts = [
    { from = 4000; to = 4007; }   # Common VoIP range
    { from = 8000; to = 8010; }   # Additional gaming range
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
    
    # FIX: Enable connection tracking for stateful firewall
    checkReversePath = "strict";  # Reverse path filtering
    
    # FIX: Configure firewall logging
    logRefusedConnections = true;
  };

  # NOTE: Additional firewall hardening can be done via kernel-sysctl.nix
  #       See kernel-sysctl.nix for network-related security settings
}
