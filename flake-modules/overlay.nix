{ ... }: {
  flake.modules.nixos.nautilus-overlay = { ... }: {
    nixpkgs.overlays = [
      (final: prev: {
        nautilus = prev.nautilus.overrideAttrs (old: {
          patches = (old.patches or []) ++ [ ./../files/patches/nautilus-hide-system-mounts.patch ];
        });
      })
    ];
  };
}
