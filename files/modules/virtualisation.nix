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
  virtualisation.libvirtd.enable = true;


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
  ];
}