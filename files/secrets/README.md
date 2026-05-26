# Encrypted Secrets (sops-nix)

This directory stores encrypted secrets managed by [sops-nix](https://github.com/Mic92/sops-nix).

## Architecture

- **Tool**: [SOPS](https://github.com/getsops/sops) (encryption) + [age](https://github.com/C2SP/age) (cryptographic backend)
- **Key source**: SSH host key (`/etc/ssh/ssh_host_ed25519_key`) — automatically converted to an age key by `ssh-to-age`
- **Module**: `files/modules/security/sops.nix` implements the sops-nix integration
- **Config**: `.sops.yaml` at repo root defines which age keys can decrypt secrets

## How to create/edit secrets

### Prerequisites (one-time setup)

1. **Build and deploy** the system so SSH host keys exist:
   ```bash
   nixos-rebuild switch --flake .#atlas
   ```

2. **Get your age public key** from the SSH host key:
   ```bash
   cat /etc/ssh/ssh_host_ed25519_key.pub | nix shell nixpkgs#ssh-to-age -c ssh-to-age
   ```
   This outputs a key like `age1abc123...`.

3. **Update `.sops.yaml`** in the repo root:
   - Uncomment the `&yusa` line under `keys:`
   - Replace `<age-public-key>` with your actual age public key
   - Commit the change

4. **Encrypt the secrets file** with your key:
   ```bash
   sops updatekeys files/secrets/secrets.yaml
   ```
   Or start fresh:
   ```bash
   sops files/secrets/secrets.yaml
   ```

### Daily usage

**Editing an existing secret:**
```bash
sops files/secrets/secrets.yaml
```

**Adding a new secret to the YAML:**
```bash
sops files/secrets/secrets.yaml
# Add your new key: value entry, save, and exit
```

Then reference it in Nix config:

**System-level (configuration.nix or a module):**
```nix
sops.secrets.my_api_key = {
  sopsFile = ../secrets/secrets.yaml;
};
```
Accessible at `/run/secrets/my_api_key`.

**User-level (home.nix):**
```nix
sops.secrets.my_api_key = {
  sopsFile = ../secrets/secrets.yaml;
};
```
Accessible at `/run/secrets/my_api_key` (for NixOS) or `$XDG_RUNTIME_DIR/secrets/my_api_key` (for home-manager).

## How keys are managed

### Key generation

`sops-nix` uses `ssh-to-age` (included via `sshKeyPaths` configuration) to derive an age key from the existing SSH host key at `/etc/ssh/ssh_host_ed25519_key`. This means:

- **No separate age key to manage** — the SSH key is your identity
- **Key persistence** — SSH host keys are already persisted via `preservation.nix` (`/etc/ssh`)
- **On-the-fly conversion** — the age key is derived at activation time, no permanent `.age` file is stored on disk

### Where keys live

| Key | Location | Persistence |
|-----|----------|-------------|
| SSH host private key | `/etc/ssh/ssh_host_ed25519_key` | Persisted via `/persistent/etc/ssh` (preservation module) |
| Age public key | `~/.age/key.txt` or derived from SSH key | Derived at activation time |
| Encrypted secrets | `files/secrets/secrets.yaml` | Committed to repo (encrypted) |

## How to bootstrap a new machine

When setting up Atlas on a new machine:

1. **First build** — the system will build but sops-nix activation will skip decryption (the secrets file has no referenced secrets yet)
2. **Generate host keys** — SSH keys are created at first boot
3. **Get age public key** — run `ssh-to-age` as described above
4. **Add key to `.sops.yaml`** — commit the updated file
5. **Re-encrypt secrets** — run `sops updatekeys files/secrets/secrets.yaml`
6. **Rebuild** — `nixos-rebuild switch --flake .#atlas` — secrets decrypt successfully

## How to rotate keys

If you need to rotate the SSH host key (and therefore the age identity):

1. **Generate new SSH host key**:
   ```bash
   sudo rm /etc/ssh/ssh_host_ed25519_key*
   sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
   ```

2. **Get the new age public key**:
   ```bash
   cat /etc/ssh/ssh_host_ed25519_key.pub | nix shell nixpkgs#ssh-to-age -c ssh-to-age
   ```

3. **Update `.sops.yaml`** with the new public key

4. **Re-encrypt all secrets**:
   ```bash
   sops updatekeys files/secrets/secrets.yaml
   ```

5. **Rebuild** to apply:
   ```bash
   nixos-rebuild switch --flake .#atlas
   ```

### Removing an old key from the key group

Edit `.sops.yaml` and remove the old key entry, then run:
```bash
sops updatekeys files/secrets/secrets.yaml
```

This re-encrypts all secrets so they can no longer be decrypted by the removed key.

## How to add additional secrets

### Workflow

1. Open the secrets file: `sops files/secrets/secrets.yaml`
2. Add your key-value pair:
   ```yaml
   github_token: ghp_abc123def456
   ```
3. Save and exit — `sops` encrypts the file automatically
4. Reference the secret in Nix config:

   **System level** (in `configuration.nix` or a module):
   ```nix
   sops.secrets.github_token = {
     sopsFile = ../secrets/secrets.yaml;
   };
   ```
   
   Then use it in a service:
   ```nix
   systemd.services.my-service = {
     serviceConfig = {
       EnvironmentFile = "/run/secrets/github_token";
     };
   };
   ```

   **User level** (in `home.nix`):
   ```nix
   sops.secrets.github_token = {
     sopsFile = ../secrets/secrets.yaml;
   };
   ```

   Secrets are decrypted to `/run/secrets/<name>` by default.

### Secret ownership and permissions

```nix
sops.secrets.my_secret = {
  sopsFile = ../secrets/secrets.yaml;
  owner = "yusa";
  group = "users";
  mode = "0400";
};
```

## Troubleshooting

### "Age key not found" during activation

Ensure SSH host keys exist:
```bash
ls -la /etc/ssh/ssh_host_ed25519_key*
```
If missing, regenerate: `sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""`

### "Failed to decrypt" errors

The secrets file was encrypted for a different key than what this machine has. Likely caused by:
- Fresh install without updating `.sops.yaml`
- SSH host key rotation without re-encrypting secrets
- Running `sops updatekeys` without your key listed in `.sops.yaml`

Fix: Ensure your age public key is in `.sops.yaml` and re-run `sops updatekeys files/secrets/secrets.yaml`.

### sops CLI not found

The `sops` and `ssh-to-age` packages are included in `environment.systemPackages` via `files/modules/security/sops.nix` and `files/modules/security/default.nix`. Rebuild to make them available.
