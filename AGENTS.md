# AGENTS.md — Atlas NixOS Configuration Guide

## Project
**Atlas** — NixOS 25.11 flake. Hostname `atlas`, user `yusa`, Niri+Noctalia, Home Manager.

## Structure
```
/home/yusa/Atlas/atlas-unstable/
├── flake.nix                    # Entry point: defines atlas + atlas-installer configs
├── .sops.yaml                   # SOPS encryption config (age keys for secrets)
├── test_config.sh               # 300+ static analysis tests (bash, no root/net)
├── AGENTS.md
├── files/
│   ├── core/
│   │   ├── configuration.nix    # System-wide NixOS config (~700 lines)
│   │   ├── home.nix             # Home Manager user config (~700 lines)
│   │   ├── hardware-configuration.nix  # Auto-generated
│   │   ├── current-system.nix   # Current system reference
│   │   ├── disko.nix            # Disk partitioning (installer only)
│   │   └── preservation.nix     # Persistent data paths
│   ├── hardware/default.nix     # Hardware profile importer
│   ├── profiles/default.nix     # System profile importer
│   ├── modules/
│   │   ├── security/            # 24+ hardening submodules (auto-imported via default.nix)
│   │   │   └── sops.nix         # sops-nix secret management integration
│   │   └── optional/            # External atlas-modules integration
│   │       ├── nixos/default.nix
│   │       └── home/default.nix
│   ├── secrets/                 # Encrypted SOPS-managed secrets
│   │   ├── secrets.yaml         # Main encrypted secrets file
│   │   └── README.md            # Secret management documentation
│   ├── config/niri/             # Niri WM config (KDL files)
│   ├── bin/                     # Shell + Python scripts
│   └── audio/                   # Sound files
```

## Rules
1. **ALL changes within** `/home/yusa/Atlas/atlas-unstable/`
2. **No `sudo`** for file edits (all user-owned)
3. **No imperative packages** — declare in configuration.nix or home.nix
4. **Never edit `flake.lock`** — use `nix flake update`
5. **No force-push, no git history rewrite**
6. **Never modify auto-generated files**: `flake.lock`, `hardware-configuration.nix`, `primary_color.txt`
7. **Security modules**: Do not disable without explicit user consent
8. **sops-nix secrets**: Never commit unencrypted secrets. Always use `sops` to edit `files/secrets/secrets.yaml`. Never commit raw `.age` private key files.

## Key Config Files

| File | Purpose | Key sections |
|------|---------|-------------|
| `files/core/configuration.nix` | System config | imports (~line 14), boot (~65), users (~115), services (~200), security (~540) |
| `files/core/home.nix` | User config | Noctalia, GTK, fonts, packages, git, shell |
| `files/modules/security/sops.nix` | sops-nix module | age keys, default sops file, packages |
| `.sops.yaml` | SOPS encryption rules | age public keys, creation rules |
| `files/secrets/secrets.yaml` | Encrypted secrets | all secret key-value pairs |
| `flake.nix` | Flake entry | `nixosConfigurations.atlas`, `nixosConfigurations.atlas-installer` |

## State Versions (DO NOT CHANGE)
- `system.stateVersion = "25.11"`
- `home.stateVersion = "25.11"`

## Module Architecture
- `configuration.nix` imports `hardware/default.nix`, `profiles/default.nix`, `modules/security/default.nix`, `modules/optional/nixos`
- `security/default.nix` imports all submodules including `sops.nix`
- `snort.nix` and `snout.nix` are imported separately in configuration.nix (not in security/default.nix)
- `sops.nix` configures `sops-nix` with SSH key-derived age keys from `/etc/ssh/ssh_host_ed25519_key`
- External `atlas-modules` repo provides gaming, privacy, dev, virtualization, flatpak, performance modules
- Home Manager imports `noctalia.homeModules.default`, `home.nix`, `modules/optional/home`
- sops-nix modules are added in `flake.nix` to both NixOS (`inputs.sops-nix.nixosModules.sops`) and Home Manager (`inputs.sops-nix.homeManagerModules.sops`)

## Testing
```bash
bash test_config.sh   # 300+ offline static checks, no root needed
```
- Environment overrides: `ATLAS_BASE=/path`, `ATLAS_MODULES_PATH=/path`
- Run before any commit or rebuild suggestion
- Nix validation: `nix flake check && nix flake show`
- **Build/deploy**: Use `atlas-rebuild` (stops tamper-detection services before rebuild, then runs `nixos-rebuild switch --flake .#atlas`)
  - Build only: `atlas-rebuild build --flake .#atlas`
  - Switch: `sudo nixos-rebuild switch --flake .#atlas` (if you've stopped tamper services manually)

## Common Patterns
- **Adding system packages**: Add to `environment.systemPackages` in configuration.nix
- **Adding user packages**: Add to `home.packages` in home.nix
- **Conditional config**: Use `lib.mkIf` or `lib.mkForce`
- **Shell scripts**: Use `pkgs.writeShellScript` or `pkgs.writeShellScriptBin`
- **Using secrets**: Define in `sops.secrets.<name>` in configuration.nix or home.nix; values stored encrypted in `files/secrets/secrets.yaml`; access at `/run/secrets/<name>`

## Flake Inputs
- `nixpkgs` (nixos-unstable), `home-manager` (master), `noctalia-shell` (custom desktop),
  `disko`, `preservation`, `atlas-modules` (external: gaming, privacy, dev, etc.),
  `sops-nix` (secret management, follows nixpkgs)
