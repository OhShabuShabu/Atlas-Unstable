{
  # NOTE: aarch64-linux is currently aspirational — all host configurations
  #       hardcode x86_64-linux. When aarch64 hardware is added, add the
  #       relevant nixosConfigurations in hosts.nix.
  systems = [ "x86_64-linux" ];
}
