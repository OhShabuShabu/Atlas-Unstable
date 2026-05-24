{ pkgs, ... }:
{
  # ============================================================================
  # MINECRAFT CONFIGURATION
  # ============================================================================
  # Installs: PrismLauncher, Blockbench
  # ============================================================================

  # ============================================================================
  # SECTION 1: MINECRAFT TOOLS
  # ============================================================================
  # Minecraft launcher and development tools
  environment.systemPackages = with pkgs; [
    # PrismLauncher (modded Minecraft launcher)
    prismlauncher

    # Blockbench (3D modeling for Minecraft)
    blockbench
  ];
}