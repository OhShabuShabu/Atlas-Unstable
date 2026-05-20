# AGENTS.md — Guidelines for Other Models and Agents

This document provides comprehensive guidance for AI agents and models making changes to the Atlas NixOS flake configuration. Follow these instructions carefully to ensure safe, consistent, and maintainable modifications.

---

## Quick Start for Agents

If this is your first time working on this project, follow these steps:

1. **Read Section 1 (Project Overview)** — Understand what this system is
2. **Understand the location constraint (Section 3.1)** — ALL changes must stay in `/home/yusa/Atlas/`
3. **Never use `sudo` for file edits (Section 3.2)** — Use the Edit tool instead
4. **Read Section 4 (Tool Usage)** — Learn which tools to use and when
5. **Follow the Validation Checklist (Section 22)** — Before finishing any change
6. **Update documentation (Section 6)** — After every modification

**When in doubt:** Ask the user for clarification rather than guessing.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Directory Structure](#2-complete-directory-structure)
3. [Absolute Rules for Agents](#3-absolute-rules-for-agents)
4. [Tool Usage Guide](#4-tool-usage-guide)
5. [Code Style Standards](#5-code-style-standards)
6. [Documentation Requirements](#6-documentation-update-md-files-after-changes)
7. [Testing Changes](#7-testing-changes)
8. [Workflow Example](#8-workflow-example-adding-a-new-tool)
9. [Common Pitfalls](#9-common-pitfalls-and-how-to-avoid-them)
10. [Key Configuration Files](#10-key-configuration-file-reference)
11. [State Versions](#11-state-versions)
12. [Command Reference](#12-quick-command-reference)
13. [Emergency Revert](#13-emergency-reverting-a-bad-change)
14. [Final Checklist](#14-final-checklist-for-every-change)
15. [Help and Issues](#15-getting-help-and-reporting-issues)
16. [Module Organization](#16-module-organization-and-editing-guide)
17. [Git Workflow](#17-git-workflow-and-change-tracking)
18. [Performance and Optimization](#18-performance-and-build-optimization)
19. [Nix Language Basics](#19-nix-language-basics-for-agents)
20. [Environment Variables](#20-environment-variables-and-paths)
21. [Advanced Flake Usage](#21-advanced-working-with-flake-outputs)
22. [Verification Checklist](#22-verification-and-quality-checklist)
23. [Common Scenarios](#23-common-scenarios-and-solutions)
24. [File Modification Patterns](#24-file-modification-patterns)
25. [Documentation Templates](#25-documentation-template)
26. [Final Notes](#26-final-notes-for-agents)

---

## 1. Project Overview

**Atlas** is a personal NixOS 25.11 flake configuration with the following stack:

- **Hostname**: `atlas`
- **User**: `yusa` (home: `/home/yusa`)
- **Window Manager**: Niri (scrolling Wayland compositor)
- **Desktop Shell**: Noctalia (Wayland desktop shell)
- **Terminal**: Ghostty + Nushell
- **Editor**: Neovim (LazyVim configuration) with opencode CLI tool
- **System**: NixOS with flakes, Home Manager, and LUKS encryption
- **State Versions**: NixOS 25.11, Home Manager 25.11

### Flake Inputs

The `flake.nix` file declares 3 inputs:
1. `nixpkgs` (version 25.11)
2. `home-manager`
3. `noctalia-shell` (custom desktop shell)

All dependency versions are pinned in `flake.lock`. **Never modify `flake.lock` directly** — use `nix flake update` instead.

---

## 2. Complete Directory Structure

```
/home/yusa/Atlas/
├── flake.nix                          # Flake entry point (main config)
├── flake.lock                         # Locked dependency versions
├── README.md                          # Full project documentation
├── AGENTS.md                          # This file (agent guidelines)
├── .gitignore                         # Git ignore rules
│
└── files/
    ├── core/
    │   ├── configuration.nix          # System-level NixOS config (~540 lines)
    │   ├── home.nix                   # Home Manager user config (~208 lines)
    │   ├── hardware-configuration.nix # Auto-generated hardware config
    │   └── config/
    │       ├── shellrc.nu             # Nushell config (aliases, prompts, keybindings)
    │       └── nix/nix.conf           # User nix daemon configuration
    │
    ├── config/
    │   ├── niri/                      # Niri window manager config (7 files)
    │   │   ├── *.kdl                  # KDL config files
    │   │   └── animations/            # Active animation presets
    │   ├── vicinae/vicinae.json       # App launcher configuration
    │   ├── .icons/oreo_black_cursors/ # Active cursor theme
    │   ├── primary_color.txt          # Current RGB color value (auto-generated)
    │   └── primary_color_template.txt # Matugen template for theming
    │
    ├── modules/
    │   ├── security/                  # 17 security hardening submodules
    │   ├── dev/
    │   │   ├── dev.nix                # Development tools (git, rust, go, etc.)
    │   │   └── nvim/                  # Neovim LazyVim configuration
    │   ├── gaming/
    │   │   ├── gaming.nix             # Steam + MangoHUD config
    │   │   └── millennium/            # Steam Millennium theme configuration
    │   ├── privacy/
    │   │   ├── privacy.nix            # Mullvad VPN + metadata cleaner
    │   │   └── mullvadbrowser/        # Mullvad browser profile (config only)
    │   ├── flatpak.nix                # Flathub + Flatpak applications
    │   ├── minecraft.nix              # PrismLauncher + Blockbench
    │   ├── performance.nix            # CPU governor + Nix optimization
    │   ├── tools.nix                  # CLI utilities and shell tools
    │   └── virtualisation.nix         # Docker, Podman, libvirt configuration
    │
    ├── audio/
    │   ├── startup.mp3                # Startup notification sound
    │   └── close_window.mp3           # Window close notification sound
    │
    └── bin/
        ├── python/
        │   ├── fix_rgb_color.py       # OpenRGB color synchronization script
        │   └── motivate                # Daily motivational quote generator
        └── shell/
            └── startup.sh             # Niri startup initialization script
```

---

## 3. Absolute Rules for Agents

These rules are non-negotiable and must be followed for every change.

### 3.1 Location Constraints: Stay Inside `/home/yusa/Atlas/`

- **ALL changes must be within `/home/yusa/Atlas/` directory**
- **NEVER create files outside this directory**
- **NEVER modify files in:**
  - `/etc/nixos/` — managed exclusively by the flake
  - `/run/` — ephemeral runtime directory
  - `/tmp/` — temporary files (use `/home/yusa/Atlas/` instead)
  - `/nix/store/` — read-only store
  - `~/.config/`, `~/.local/`, or other user directories outside this repo

**Why?** This is a flake-managed system. All source configuration lives in this repository. The flake build system converts these files into system-wide configuration at rebuild time.

### 3.2 Never Use `sudo` for File Operations

- **NEVER use `sudo` to edit or create files**
- **ALL files in `/home/yusa/Atlas/` are user-owned** (`yusa:users`)
- File operations must use the working user (`yusa`)
- `sudo` is **only permitted** for: `sudo nixos-rebuild switch --flake .#atlas`

**Why?** The flake runs as root during build, so source files must remain user-editable. Using `sudo` on source files creates permission issues.

### 3.3 No Imperative Package Installation

- **DO NOT use:**
  - `nix profile install`
  - `apt install`
  - `pacman -S`
  - Any other imperative package manager

- **ALL packages must be declared in:**
  - `files/core/configuration.nix` (system packages)
  - `files/core/home.nix` (user packages)
  - Relevant module files in `files/modules/`

**Why?** NixOS is declarative. Imperative installs won't survive rebuilds and break reproducibility.

### 3.4 Never Modify `flake.lock` Directly

- **NEVER hand-edit `flake.lock`**
- Use `nix flake update` command to update dependencies
- Run: `nix flake update` from `/home/yusa/Atlas/`
- Then rebuild: `sudo nixos-rebuild switch --flake .#atlas`

**Why?** `flake.lock` is auto-generated by Nix. Manual edits cause corruption and dependency conflicts.

### 3.5 Never Force-Push or Modify Git History

- **NEVER use:**
  - `git push --force`
  - `git rebase -i` or other history rewriting
  - `git reset --hard`

- **NEVER modify `.git/` internals directly**
- Always let the user make git decisions

**Why?** Destructive git operations can lose work. The user must control version control.

### 3.6 Do Not Modify Auto-Generated Files

Files that are auto-generated by system tools must not be modified:

- `flake.lock` — auto-generated by `nix flake`
- `files/core/hardware-configuration.nix` — auto-generated by NixOS
- `files/config/primary_color.txt` — auto-generated by theme tools

**Why?** These files are regenerated on system operations. Manual changes get overwritten.

### 3.7 Critical System Files: Handle With Care

Do not modify these files without **explicit user consent**:

- `files/core/configuration.nix` — system-wide configuration
- `files/core/home.nix` — user profile configuration
- `flake.nix` — flake entry point

Always explain changes clearly and verify functionality.

---

## 4. Tool Usage Guide

When modifying files, use the appropriate tools:

### 4.1 Reading Files

**Use the `Read` tool for all file reads:**

```
read(filePath: "/home/yusa/Atlas/files/core/configuration.nix")
```

- Always use absolute paths (never relative paths)
- Use `offset` and `limit` parameters for large files (e.g., read lines 100-200)
- Prefer reading entire files unless they exceed 2000 lines
- Results include line numbers for reference

**Do NOT use Bash commands like `cat`, `head`, `tail`, `grep` to read files.**

### 4.2 Editing Files

**Use the `Edit` tool for all file modifications:**

```
edit(
  filePath: "/home/yusa/Atlas/files/core/configuration.nix",
  oldString: "original text to find",
  newString: "replacement text"
)
```

**Requirements:**
- You MUST read the file first using the `Read` tool
- `oldString` must match exactly (including whitespace and indentation)
- If `oldString` appears multiple times, provide more context or use `replaceAll: true`
- Always preserve indentation exactly as it appears in the file

**Do NOT use Bash commands like `sed`, `awk`, or `vim` for editing.**

### 4.3 Creating New Files

**Use the `Write` tool ONLY when absolutely necessary:**

```
write(
  filePath: "/home/yusa/Atlas/files/bin/new_script.sh",
  content: "#!/usr/bin/env bash\n..."
)
```

**Requirements:**
- Read existing files first if they're part of a related structure
- Only create new files when the user explicitly requests it
- New files must be within `/home/yusa/Atlas/`
- Follow the directory structure conventions
- Include proper file headers (shebangs, license comments if applicable)

**Prefer editing existing files over creating new ones.**

### 4.4 File Search and Discovery

**Use the `Glob` tool to find files by pattern:**

```
glob(pattern: "**/*.nix", path: "/home/yusa/Atlas/")
```

- Returns files matching glob patterns sorted by modification time
- Use patterns like `**/*.nix`, `files/modules/**/*.nix`, `src/**/*.{ts,tsx}`
- Always provide a path or it defaults to working directory

**Use the `Grep` tool to search file contents:**

```
grep(
  pattern: "environment\\.systemPackages",
  include: "*.nix",
  path: "/home/yusa/Atlas/"
)
```

- Searches using regex patterns
- Returns file paths and line numbers
- Use `include` to filter by file type
- Results sorted by modification time

### 4.5 Running Commands

**Use the `Bash` tool ONLY for terminal operations:**

```
bash(
  command: "nix flake check",
  description: "Validate flake syntax",
  workdir: "/home/yusa/Atlas/"
)
```

**Appropriate uses:**
- `nix` commands (build, update, check, etc.)
- `git` commands (status, log, add, commit)
- `nixos-rebuild` for system changes
- Testing compilation or syntax
- Running scripts

**Never use Bash for:**
- File reads (use `Read` tool)
- File edits (use `Edit` tool)
- File searches (use `Glob` or `Grep` tools)
- File creation (use `Write` tool)

**Important Bash guidelines:**
- Always use `workdir` parameter instead of `cd` commands
- Always quote file paths containing spaces: `"/path/with spaces/file.txt"`
- Provide clear 5-10 word descriptions of what commands do
- Check command output for errors before proceeding

---

## 5. Code Style Standards

All modifications must follow these style conventions:

### 5.1 Nix Files

- **Indentation:** 2 spaces (not tabs)
- **Line length:** Keep under 100 characters when practical
- **Comments:** Only explain *why* code exists, not *what* it does (code should be self-documenting)
- **Spacing:** Blank lines between logical sections
- **Syntax:** Follow nixpkgs conventions for consistent style

Example:
```nix
{
  # Disable the graphical shell for minimal systems
  nix.enable = false;

  security.pam.services.login.gnupgSupport = true;
}
```

### 5.2 KDL Files (Niri Config)

- **Standard KDL formatting** (proper indentation and spacing)
- **Comments:** Use `//` for single-line comments
- **Organization:** Group related bindings and rules

### 5.3 Lua Files (Neovim)

- **Follow LazyVim conventions** (if editing Neovim config)
- **Indentation:** 2 spaces
- **Style:** Match existing LazyVim patterns in `files/modules/dev/nvim/`

### 5.4 Shell Scripts

- **Shebang:** `#!/usr/bin/env bash` or `#!/usr/bin/env nush`
- **Indentation:** 2 spaces
- **Error handling:** Use `set -e` or explicit error checks
- **Quoting:** Quote all variable expansions: `"$var"`

---

## 6. Documentation: Update `.md` Files After Changes

**Every time you modify configuration, you must update the relevant `.md` documentation file.**

This is crucial for maintaining accurate documentation that reflects the actual system state.

### 6.1 When to Update Documentation

Update documentation in these situations:

1. **Adding a new package**: Update `README.md` package list or module docs
2. **Adding a new module**: Create or update module documentation
3. **Changing system behavior**: Update feature descriptions
4. **Modifying keybindings**: Update hotkey reference
5. **Adding scripts**: Document script purpose and usage
6. **Changing installation steps**: Update setup instructions

### 6.2 Documentation Files to Update

- **`README.md`** — Main documentation, package lists, setup instructions
- **`AGENTS.md`** — This file (update if agent guidelines change)
- **Module-specific `.md` files** — Create `README.md` or `.md` files in module directories
- **Inline comments** — Explain complex configurations in code

### 6.3 How to Update Documentation

Use the `Edit` tool:

1. Read the existing `.md` file
2. Find the relevant section
3. Update with accurate information about your changes
4. Keep formatting consistent with the existing document
5. Provide clear, user-friendly descriptions

Example: After adding a new gaming module, update `README.md`:

```
## Gaming
- Added PrismLauncher for Minecraft Java Edition
- MangoHUD overlay for performance monitoring
- Steam with Proton for Linux game support
```

### 6.4 Documentation Standards

- **Be accurate:** Documentation must match actual system state
- **Be clear:** Use simple language, avoid jargon
- **Be organized:** Use headers and bullet points for scanability
- **Be specific:** Include file paths, command examples, version numbers
- **Keep it current:** Update docs when reverting changes too

---

## 7. Testing Changes

Before considering a change complete, you must validate it.

### 7.1 Pre-Build Validation

Run these checks before rebuilding:

**1. Syntax validation:**
```bash
nix flake check
```

Checks that all `.nix` files are valid Nix code. Catches syntax errors early.

**2. Flake evaluation:**
```bash
nix flake show
```

Displays available flake outputs. Ensures flake is evaluable.

**3. Build dry-run (check dependencies without building):**
```bash
nixos-rebuild build --flake .#atlas
```

Builds the system derivation without activating it. Catches most errors.

### 7.2 Using the Test Suite

**Run the comprehensive test suite:**

```bash
bash test_config.sh
```

This script performs 150+ static analysis checks covering:
- Flake structure and versioning
- File existence and structure
- Nix syntax validation
- Core configuration options
- Home Manager setup
- Security hardening (17 modules)
- Niri window manager config
- Startup scripts
- Python script validation
- Development tools
- Gaming configuration
- Privacy configuration
- Virtualization setup
- Service dependencies
- Cross-reference consistency

The test suite is **completely offline** — no network, no root required. It uses static pattern matching to verify configuration integrity. Perfect for agents to run before suggesting rebuilds.

**Test output:**
- `✓` (GREEN) — Test passed
- `✗` (RED) — Critical test failed
- `⚠` (YELLOW) — Non-critical warning
- Exit code 0 if all critical tests pass
- Exit code 1 if any critical test fails

**When to run:**
- After making any configuration changes
- Before committing changes
- Before suggesting system rebuild

### 7.3 Building the Configuration

**To test configuration without applying it:**

```bash
nixos-rebuild build --flake .#atlas
```

This:
- Builds the system derivation
- Does NOT activate it system-wide
- Allows testing before live rebuild
- Takes 5-30 minutes depending on complexity

**To apply configuration (requires user authorization):**

```bash
sudo nixos-rebuild switch --flake .#atlas
```

This:
- Builds the system
- Activates it immediately
- Applies all changes system-wide
- **Cannot be undone** (but you can rebuild the previous generation)

### 7.4 Testing Specific Modules

For large changes, test specific modules first:

**Test development module:**
```bash
nix flake check --show-trace
```

**Build only home-manager:**
```bash
home-manager switch -b backup --flake .#yusa@atlas
```

### 7.5 Common Issues and Diagnostics

**Issue: Syntax errors in `.nix` files**
```bash
nix flake check --show-trace
```
Shows detailed error location and context.

**Issue: Package not found**
- Check it exists in `nixpkgs` for version 25.11
- Verify spelling in config file
- Search: `nix search nixpkgs package_name`

**Issue: Module not loading**
- Verify path in `imports` is correct
- Check for typos in module names
- Run `nix flake show` to see available modules

**Issue: Build failures**
- Read error message carefully (usually very specific)
- Check if package is available in nixpkgs 25.11
- Look for conflicting package options
- Test with `nixos-rebuild build` (dry-run) first

### 7.6 Validation Checklist

After making changes, run through this checklist:

- [ ] Run `bash test_config.sh` — all critical tests pass
- [ ] File syntax is valid: `nix flake check`
- [ ] Flake evaluates: `nix flake show`
- [ ] Build succeeds: `nixos-rebuild build --flake .#atlas`
- [ ] Documentation updated (`.md` files)
- [ ] No `sudo` used on file edits
- [ ] All changes within `/home/yusa/Atlas/`
- [ ] No files created outside the project directory
- [ ] Indentation follows code style (2 spaces for Nix)

---

## 8. Workflow Example: Adding a New Tool

Here's a complete example of the correct workflow for adding a new package:

### Scenario: Add `ripgrep` to system packages

**Step 1: Understand current state**
```bash
Read("/home/yusa/Atlas/files/core/configuration.nix")
```

**Step 2: Find the package list**
Search for `environment.systemPackages` section.

**Step 3: Edit the file**
```
Edit(
  filePath: "/home/yusa/Atlas/files/core/configuration.nix",
  oldString: "    pkgs.curl\n    pkgs.git\n  ];",
  newString: "    pkgs.curl\n    pkgs.git\n    pkgs.ripgrep\n  ];"
)
```

**Step 4: Validate syntax**
```bash
bash(command: "nix flake check", workdir: "/home/yusa/Atlas/")
```

**Step 5: Test build**
```bash
bash(command: "nixos-rebuild build --flake .#atlas", workdir: "/home/yusa/Atlas/")
```

**Step 6: Update documentation**
```
Read("/home/yusa/Atlas/README.md")
Edit(...) to add ripgrep to the tools list
```

**Step 7: Communicate completion**
Summarize what was done, why, and next steps for the user.

---

## 9. Common Pitfalls and How to Avoid Them

### Pitfall 1: Using `sudo` for file edits
❌ `sudo nano files/core/configuration.nix`
✅ Use the `Edit` tool (no sudo needed)

### Pitfall 2: Installing packages imperatively
❌ `nix profile install nixpkgs#ripgrep`
✅ Declare in `configuration.nix` or `home.nix`

### Pitfall 3: Creating files outside `/home/yusa/Atlas/`
❌ Creating temp files in `/tmp/`
✅ Use files within the project directory

### Pitfall 4: Modifying `flake.lock` by hand
❌ Editing `flake.lock` in a text editor
✅ Use `nix flake update`

### Pitfall 5: Not updating documentation
❌ Making config changes and leaving docs outdated
✅ Update `.md` files immediately after changes

### Pitfall 6: Assuming packages exist in nixpkgs
❌ Adding a package without verifying it's in nixpkgs 25.11
✅ Search first: `nix search nixpkgs package_name`

### Pitfall 7: Not testing before suggesting rebuild
❌ Making changes without running `nix flake check`
✅ Always validate with pre-build checks

---

## 10. Key Configuration File Reference

This section provides quick guidance on modifying key files:

### `files/core/configuration.nix` (~540 lines)

**What it contains:**
- System-wide NixOS options
- Hardware configuration imports
- Network settings
- Systemwide packages (`environment.systemPackages`)
- Security hardening
- Module imports
- State versions

**When to edit:**
- Adding system packages
- Enabling system services
- Changing system settings
- Importing new modules

### `files/core/home.nix` (~208 lines)

**What it contains:**
- User-specific packages
- Home Manager configuration
- User environment variables
- Dotfile management
- User services

**When to edit:**
- Adding user packages
- Changing user-level configuration
- Managing dotfiles

### `files/modules/dev/dev.nix`

**What it contains:**
- Development tools (Rust, Go, Node.js, etc.)
- Language servers and development environments
- Build tools and compilers

**When to edit:**
- Adding development tools
- Enabling specific language environments

### `flake.nix`

**What it contains:**
- Flake inputs and outputs
- System configuration assembly
- Home Manager configuration
- Flake metadata

**When to edit:**
- **Rarely** — only for structural changes
- Adding new inputs
- Changing output structure

---

## 11. State Versions

**Never change these without explicit reason:**

```nix
system.stateVersion = "25.11"
home.stateVersion = "25.11"
```

These indicate the NixOS version when the system was created. Changing them can cause compatibility issues or trigger unwanted migrations.

---

## 12. Quick Command Reference

| Task | Command |
|------|---------|
| Run test suite (recommended) | `bash test_config.sh` |
| Validate flake syntax | `nix flake check` |
| Show flake outputs | `nix flake show` |
| Build without applying | `nixos-rebuild build --flake .#atlas` |
| Apply changes (needs sudo) | `sudo nixos-rebuild switch --flake .#atlas` |
| Update all inputs | `nix flake update` |
| Build VM for testing | `nixos-rebuild build-vm --flake .#atlas` |
| Search nixpkgs | `nix search nixpkgs pattern` |
| Show git status | `git status` |
| Show git diff | `git diff` |

---

## 13. Emergency: Reverting a Bad Change

If something breaks after a rebuild:

**To boot into previous generation:**

1. At the GRUB boot menu, select previous NixOS generation
2. Once booted, examine what changed:
   ```bash
   git diff HEAD~1
   ```
3. Fix the problematic configuration file
4. Rebuild:
   ```bash
   sudo nixos-rebuild switch --flake .#atlas
   ```

**Never force-push or rewrite git history when reverting.**

---

## 14. Final Checklist for Every Change

Before finishing ANY modification:

- [ ] Read the relevant file(s) first using `Read` tool
- [ ] Used `Edit` tool (NOT `sed`/`awk`/`vim`) for changes
- [ ] Did NOT use `sudo` for file operations
- [ ] Did NOT create files outside `/home/yusa/Atlas/`
- [ ] Did NOT modify `flake.lock` directly
- [ ] Ran `nix flake check` — passed
- [ ] Ran `nixos-rebuild build --flake .#atlas` — passed
- [ ] Updated relevant `.md` documentation files
- [ ] Explained changes clearly to user
- [ ] Provided guidance on how user should rebuild if needed

---

## 15. Getting Help and Reporting Issues

If you encounter problems:

1. **Read error messages carefully** — they usually explain the problem
2. **Run `nix flake check --show-trace`** — provides detailed diagnostics
3. **Check nixpkgs documentation** — for package-specific issues
4. **Report issues** — to user with clear context and error output

Do not proceed with further changes if validation fails.

---

## 15.5 Debugging and Error Handling Strategies

### Common Build Errors and Solutions

**Error: "attribute missing: someAttribute"**
- This usually means a required option wasn't set
- Check the module documentation for required fields
- Verify all nested attributes are properly defined
- Example: If enabling a service, ensure all required sub-options are present

**Error: "infinite recursion detected"**
- This indicates circular dependencies in configuration
- Check for variables referencing themselves
- Verify imports don't create cycles
- Run `nix flake show --all-systems` to see evaluation status

**Error: "Cannot find package"**
- Package doesn't exist in nixpkgs 25.11
- Try alternative package names: `nix search nixpkgs# partial_name`
- Check if it's a library vs executable
- Verify it's not deprecated in this nixpkgs version

**Error: "Permission denied"**
- You used `sudo` where you shouldn't have
- Use `Edit` tool instead for file modifications
- `sudo` is only for `nixos-rebuild switch`

**Error: "Module not found"**
- Check the import path is correct (absolute path from `/home/yusa/Atlas/`)
- Verify file exists and has `.nix` extension
- Ensure module exports what you're trying to use

### Debugging Workflow

1. **Capture full error output** — Include all stderr and stdout
2. **Run with trace for details:** `nix flake check --show-trace`
3. **Isolate the problem:**
   - Test just the syntax: `nix flake check`
   - Test evaluation: `nix flake show`
   - Test build: `nixos-rebuild build --flake .#atlas`
4. **Verify preconditions:**
   - All files exist where referenced
   - All packages are spelled correctly
   - All options are in correct scope (system vs user)
5. **Check git diff** to see exactly what changed: `git diff`
6. **Report with context:** File, line number, exact error message

### Recovery Steps

If changes break the build:

1. **Do NOT panic** — the system can boot to previous generation
2. **Revert immediately:**
   ```bash
   git checkout -- files/path/to/broken/file.nix
   ```
3. **Re-test:**
   ```bash
   nix flake check && nixos-rebuild build --flake .#atlas
   ```
4. **Report to user** with full error details
5. **Do NOT use force push or rewrite git history**

---

## 16. Module Organization and Editing Guide

The `files/modules/` directory contains specialized configuration modules. Understanding this structure is critical for proper modifications.

### 16.1 Security Modules (`files/modules/security/`)

Contains 17 hardening submodules for system security:
- Each module is a separate `.nix` file
- Modules are imported in `files/core/configuration.nix`
- Do NOT disable security modules without explicit user consent
- Document any security changes carefully

**Editing security modules:**
1. Read the specific security module file
2. Understand what protections it provides
3. Document any changes and their security implications
4. Test thoroughly before applying

### 16.2 Development Module (`files/modules/dev/dev.nix`)

Provides development tools and language support:
- Language-specific packages (Rust, Go, Node.js, Python, etc.)
- Build tools and compilers
- Development utilities (git, make, pkg-config, etc.)
- Language servers (LSP) for Neovim integration

**When editing:**
- Add new languages carefully — verify they exist in nixpkgs 25.11
- Group packages by language or purpose
- Update inline comments when adding new language support
- Test that language tools integrate with Neovim properly

### 16.3 Specialized Modules

Other modules handle specific features:
- `gaming.nix` — Steam, MangoHUD, Proton configuration
- `minecraft.nix` — PrismLauncher and Blockbench
- `privacy.nix` — Mullvad VPN and metadata removal
- `flatpak.nix` — Flatpak runtime and applications
- `performance.nix` — CPU governor and Nix cache optimization
- `tools.nix` — CLI utilities and shell tools
- `virtualisation.nix` — Docker, Podman, libvirt

**General module editing rules:**
- Keep modules focused on one feature area
- Use descriptive variable names
- Add comments explaining non-obvious configurations
- Test the entire module function before and after changes

### 16.4 Neovim Configuration (`files/modules/dev/nvim/`)

LazyVim configuration structure:
- Follows LazyVim plugin organization
- Lua-based configuration files
- Plugins managed through `init.lua`
- Keybindings defined in `keymaps.lua`

**When editing Neovim config:**
- Preserve LazyVim structure and conventions
- Test changes in Neovim before and after rebuild
- Document new keybindings in comments
- Ensure plugins are available in nixpkgs 25.11

---

## 17. Git Workflow and Change Tracking

This project uses Git for version control. Follow these guidelines:

### 17.1 Viewing Changes

Before committing, always review what you've changed:

```bash
git status        # See what files are modified
git diff          # See detailed changes
git log --oneline # See recent commits
```

### 17.2 Commit Best Practices

**When the user requests a commit:**

1. Read the modified files to understand changes
2. Run `git diff` to verify the changes are correct
3. Use descriptive commit messages:
   - First line: Short summary (50 chars max)
   - Blank line
   - Detailed explanation of why changes were made
4. Example commit:
   ```
   Add ripgrep to system packages
   
   ripgrep improves search performance in development
   workflows and integrates well with Neovim.
   ```

### 17.3 When NOT to Commit

- **Never commit without explicit user request** — user controls version control
- Never commit files with secrets (`.env`, credentials, API keys)
- Never commit auto-generated files unless specifically requested
- Never force-push or rewrite history

### 17.4 Handling Merge Conflicts

If you encounter merge conflicts while pulling or rebasing:

1. Report the conflict to the user
2. Do NOT attempt to resolve without clear instruction
3. Provide the conflicting file paths and context
4. Wait for user guidance before proceeding

---

## 18. Performance and Build Optimization

### 18.1 Understanding Build Times

NixOS builds can take significant time:
- Initial builds: 10-30 minutes (or longer for large systems)
- Incremental builds: 2-10 minutes depending on changes
- Binary caches (nixpkgs) speed up builds significantly

### 18.2 Minimizing Build Time During Development

When testing changes:

1. **Use `nixos-rebuild build` first** (not `switch`)
   - Catches errors without applying changes
   - Takes same time but safer
   
2. **Test specific modules if possible**
   - Focus on the module you changed
   - Full system rebuild not always necessary

3. **Batch related changes together**
   - Multiple small changes → one rebuild
   - More efficient than rebuilding for each change

### 18.3 Binary Caching

The system uses nixpkgs binary cache. If rebuilding from source:

- Add `extra-binary-caches = https://cache.nixos.org` to `files/config/nix/nix.conf`
- Verify cache settings before large rebuilds
- Binary cache significantly reduces build time

### 18.4 Storage Considerations

NixOS stores build artifacts in `/nix/store/`:

- **Never manually delete files from `/nix/store/`**
- Use `nix-collect-garbage` only when explicitly requested
- Periodically rebuilding can consume significant disk space
- Check available disk space before large changes

---

## 19. Nix Language Basics for Agents

Understanding basic Nix syntax is essential for modifications.

### 19.1 Nix Attribute Set Syntax

Most configurations use attribute sets (similar to JSON objects):

```nix
{
  # Key-value pairs
  name = "value";
  
  # Nested attribute sets
  services = {
    nginx.enable = true;
  };
  
  # Lists
  packages = [ pkg1 pkg2 pkg3 ];
  
  # String interpolation
  message = "Hello, ${user}!";
}
```

### 19.2 Package References

Packages are referenced through `pkgs`:

```nix
# Declaring packages
environment.systemPackages = with pkgs; [
  git
  vim
  neovim
];

# Home packages
home.packages = with pkgs; [
  curl
  jq
  ripgrep
];
```

### 19.3 Conditionals and Functions

Common patterns in NixOS configs:

```nix
# Conditional enable/disable
services.openssh.enable = true;

# Options with conditions
boot.kernelModules = 
  if config.hardware.gpu.enable then [ "nvidia" ] else [];

# Function example (rarely needed for edits)
let
  myPackages = with pkgs; [ git curl ];
in {
  environment.systemPackages = myPackages;
}
```

### 19.4 When in Doubt

- Do NOT try to understand complex Nix expressions
- Focus on declarative option assignments
- Keep edits to simple key-value changes
- Report complex Nix patterns to user if modification required

---

## 20. Environment Variables and Paths

Important paths and variables in this system:

### 20.1 Critical System Paths

| Path | Purpose | Notes |
|------|---------|-------|
| `/home/yusa/Atlas/` | Project root | ALL changes go here |
| `/home/yusa/` | User home | User-owned files |
| `/nix/store/` | Nix store | Read-only, do NOT modify |
| `/etc/nixos/` | System config | Managed by flake, do NOT edit |
| `/run/` | Runtime state | Ephemeral, do NOT edit |

### 20.2 Important Environment Variables

In this system:
- `NIX_PATH` — set by flake (do NOT override)
- `FLAKE_PATH` — usually `/home/yusa/Atlas`
- User shell: Nushell (not Bash by default)

### 20.3 Package Search Path

When looking for packages:
1. Search nixpkgs 25.11 specifically: `nix search nixpkgs#package_name`
2. Verify package name and spelling
3. Check if it's available as binary or must be built from source

---

## 21. Advanced: Working with Flake Outputs

The `flake.nix` defines system outputs. Understanding the structure helps with complex changes:

### 21.1 Available Outputs

```bash
# View available outputs
nix flake show
```

Expected outputs:
- `packages.x86_64-linux.*` — Built packages
- `nixosConfigurations.atlas` — System configuration
- `homeConfigurations.*` — Home Manager configurations

### 21.2 System Outputs

- `nixosConfigurations.atlas` — Complete system configuration
- Available at: `sudo nixos-rebuild switch --flake .#atlas`

### 21.3 Home Manager Outputs

- `homeConfigurations.yusa@atlas` — User configuration
- Available at: `home-manager switch -b backup --flake .#yusa@atlas`

### 21.4 When to Modify `flake.nix`

**Rarely needed.** Only modify `flake.nix` for:
- Adding new flake inputs (very rare)
- Restructuring outputs (requires user consent)
- Major architectural changes

Most changes go in:
- `files/core/configuration.nix` (system-level)
- `files/core/home.nix` (user-level)
- Module files (feature-specific)

---

## 22. Verification and Quality Checklist

Use this comprehensive checklist for every change:

### Pre-Change
- [ ] Understand the current state (read relevant files)
- [ ] Plan the change (explain to user if complex)
- [ ] Identify all files that need modification
- [ ] Document expected outcomes

### During Change
- [ ] Use `Read` tool before `Edit` tool
- [ ] Preserve exact indentation (2 spaces for Nix)
- [ ] Keep oldString/newString context sufficient to be unique
- [ ] Make one logical change at a time
- [ ] Update ALL related files (including docs)

### Post-Change Validation
- [ ] Run `nix flake check` → must pass
- [ ] Run `nix flake show` → must show outputs
- [ ] Run `nixos-rebuild build --flake .#atlas` → must succeed
- [ ] All documentation updated (`.md` files)
- [ ] No file modifications outside `/home/yusa/Atlas/`
- [ ] No `sudo` used on file edits

### Communication
- [ ] Explain what was changed and why
- [ ] List files that were modified
- [ ] Report any validation results (passed/failed)
- [ ] Provide next steps for user (if rebuild needed)
- [ ] Ask user to run rebuild if changes are system-level

---

## 23. Common Scenarios and Solutions

### Scenario: Adding a New System Package

1. Identify appropriate location (system-wide or user-level)
2. Edit `files/core/configuration.nix` or `files/core/home.nix`
3. Find `environment.systemPackages` or `home.packages`
4. Add package to the list
5. Verify package exists: `nix search nixpkgs#package_name`
6. Test: `nix flake check && nixos-rebuild build --flake .#atlas`
7. Update `README.md` if it's a notable addition

### Scenario: Modifying a Module

1. Read the module file to understand structure
2. Make targeted edits with `Edit` tool
3. Preserve module function signature and inputs
4. Test: `nix flake check`
5. Verify functionality: `nixos-rebuild build --flake .#atlas`
6. Document changes in code comments if complex

### Scenario: Debugging Build Failures

1. Read the full error message from build output
2. Note the affected file and line number
3. Run `nix flake check --show-trace` for detailed diagnostics
4. Check syntax with `nix flake show`
5. Verify package availability with `nix search`
6. Fix the issue and rebuild

### Scenario: Reverting a Change

1. Identify the problematic file(s)
2. Check git history: `git log --oneline`
3. Review the change: `git diff HEAD~1 file.nix`
4. Edit files back to working state
5. Test: `nix flake check && nixos-rebuild build --flake .#atlas`
6. If rebuild needed, tell user: `sudo nixos-rebuild switch --flake .#atlas`

---

## 24. File Modification Patterns

### 24.1 Adding to a List

Common pattern for adding items:

```nix
# Original
packages = [ pkg1 pkg2 ];

# After addition
packages = [ pkg1 pkg2 newpkg ];
```

Edit approach:
```
oldString: "packages = [ pkg1 pkg2 ];"
newString: "packages = [ pkg1 pkg2 newpkg ];"
```

### 24.2 Modifying Options

Changing configuration values:

```nix
# Original
services.openssh.enable = false;

# After change
services.openssh.enable = true;
```

Edit approach:
```
oldString: "services.openssh.enable = false;"
newString: "services.openssh.enable = true;"
```

### 24.3 Adding New Sections

Adding entire new configuration sections:

```nix
# Original
{
  services.openssh.enable = true;
}

# After addition
{
  services.openssh.enable = true;
  
  # New section
  services.nginx = {
    enable = true;
    virtualHosts.localhost.root = "/var/www";
  };
}
```

Edit approach:
```
oldString: "  services.openssh.enable = true;\n}"
newString: "  services.openssh.enable = true;\n  \n  # New section\n  services.nginx = {\n    enable = true;\n    virtualHosts.localhost.root = \"/var/www\";\n  };\n}"
```

---

## 25. Documentation Template

When updating or creating documentation files, follow this template:

### For Feature Additions

```markdown
## Feature Name

Brief description of what the feature does.

### Configuration
- File location: `files/path/to/file.nix`
- Key setting: `option.name`
- Default: `value`

### Usage
Step-by-step usage instructions.

### Related Files
- `files/path/file1.nix`
- `files/config/file2.conf`
```

### For Module Documentation

```markdown
# Module: module_name

Description of module purpose and scope.

## Includes
- Feature 1
- Feature 2

## Configuration Files
- `files/modules/module_name/file1.nix`
- `files/modules/module_name/file2.conf`

## Options
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `option1` | bool | true | Description |
| `option2` | string | "value" | Description |
```

---

## 26. Final Notes for Agents

### Be Conservative

- When in doubt, don't make the change
- Ask the user for clarification rather than guessing
- Over-communication is better than under-communication

### Think Declaratively

- NixOS is declarative — describe desired state, not steps
- Don't think in terms of "run this command"
- Think: "How do I declare this in configuration?"

### Test Thoroughly

- Never suggest a rebuild without testing locally first
- Always run `nix flake check` before suggesting rebuild
- Report test results to user explicitly

### Document Everything

- Every configuration change needs documentation update
- Documentation must match actual system state
- Outdated docs are worse than no docs

### Respect the System

- This is a carefully tuned personal system
- Don't make "nice to have" changes without explicit request
- Preserve existing configuration patterns and style
- Ask before making major architectural changes

---

## 27. Communication Best Practices for Agents

How to communicate clearly and effectively with the user about changes:

### Before Making Changes

1. **Explain the plan clearly:**
   - "I will edit `files/core/configuration.nix` to add `ripgrep` to `environment.systemPackages`"
   - "This will make ripgrep available system-wide for all users"

2. **Highlight potential impacts:**
   - "Adding this package will increase build time by ~2 minutes"
   - "This change is system-level and requires rebuild with `sudo nixos-rebuild switch --flake .#atlas`"

3. **Ask for confirmation if uncertain:**
   - "Should I add this to system packages or user packages in home.nix?"
   - "Is there a specific version of this package you need?"

### While Making Changes

1. **Report progress:**
   - "Reading configuration.nix to find the package list..."
   - "Found environment.systemPackages at line 45"
   - "Making the edit now..."

2. **Show what you're doing:**
   - Include the exact oldString/newString in your explanation
   - Reference specific line numbers when relevant
   - Use file paths consistently

### After Making Changes

1. **Summarize what was done:**
   ```
   Modified files:
   - files/core/configuration.nix: Added ripgrep to environment.systemPackages
   - README.md: Updated tools list to include ripgrep
   
   Changes validated:
   - ✓ nix flake check: PASSED
   - ✓ nixos-rebuild build: PASSED
   ```

2. **Provide next steps:**
   - "The configuration is ready. To apply changes, run:"
   - "`sudo nixos-rebuild switch --flake .#atlas`"
   - "This will take about 5-10 minutes to build and apply"

3. **Document the changes:**
   - "Updated README.md with the new tool information"
   - Link to the specific documentation changes

### Error Communication

1. **Be specific about failures:**
   - ❌ "Build failed" (bad)
   - ✅ "Build failed: Package 'oldripgrep' not found in nixpkgs 25.11" (good)

2. **Show the exact error:**
   - Include the error message verbatim
   - Point to the problematic line in the configuration
   - Explain what the error means

3. **Suggest recovery:**
   - "I can revert this change with: `git checkout -- files/core/configuration.nix`"
   - "Or we can fix the issue by..."

### When Asking for Help

Ask the user clearly and specifically:

- ❌ "I'm not sure what to do" (bad)
- ✅ "Should I add this to `environment.systemPackages` (system-wide) or `home.packages` (user-only)? System-wide would make it available to all users, but user-only keeps it just for yusa." (good)

### File References in Communication

Always include file paths and line numbers when referencing specific code:

- "In `files/core/configuration.nix:45`, the environment.systemPackages list begins:"
- "See `files/modules/dev/dev.nix:20-30` for language tool configuration"

---

## 28. Practical Workflow Examples

### Example 1: Adding a Rust Toolchain

**User request:** "Add Rust to the development environment"

**Agent workflow:**
1. Read `files/modules/dev/dev.nix` to understand current structure
2. Identify where Rust dependencies are listed
3. Plan changes: "I'll add rustup, cargo, and rust-analyzer to the dev module"
4. Edit the file to add Rust packages
5. Check if any compiler flags need updating
6. Run `nix flake check` ✓
7. Run `nixos-rebuild build --flake .#atlas` ✓
8. Update `README.md` under Development section
9. Summarize for user with next steps

**Communication:**
```
I've added Rust toolchain support to your development environment:
- Added rustup (Rust installer)
- Added cargo (Rust package manager)
- Added rust-analyzer (Neovim LSP support)

Modified: files/modules/dev/dev.nix, README.md
Validated: nix flake check ✓, nixos-rebuild build ✓

Next: Run `sudo nixos-rebuild switch --flake .#atlas` to apply
```

### Example 2: Enabling a System Service

**User request:** "Enable the OpenSSH server"

**Agent workflow:**
1. Read `files/core/configuration.nix` to find services section
2. Look for existing service configurations
3. Determine if SSH is already partially configured
4. Add appropriate configuration:
   ```nix
   services.openssh = {
     enable = true;
     settings = {
       PasswordAuthentication = false;
       PermitRootLogin = "no";
     };
   };
   ```
5. Validate syntax: `nix flake check` ✓
6. Check build: `nixos-rebuild build --flake .#atlas` ✓
7. Document security implications in comments
8. Update README.md with SSH access instructions

**Communication:**
```
I've enabled OpenSSH with secure defaults:
- Password authentication disabled (key-only)
- Root login prevented
- Standard SSH port (22)

Modified: files/core/configuration.nix, README.md
Important: You'll need SSH keys set up before connecting

To apply: sudo nixos-rebuild switch --flake .#atlas
```

### Example 3: Fixing a Broken Configuration

**Scenario:** Previous agent added a package that doesn't exist, build fails

**Agent workflow:**
1. Read the error message carefully
2. Identify the problematic package name
3. Search for alternatives: `nix search nixpkgs# partial_name`
4. Report to user with options
5. Wait for user confirmation on which package to use
6. Make the correction
7. Revalidate build

**Communication:**
```
Build failed: Package 'oldripgrep' not found in nixpkgs 25.11

This appears to be an old package name. The current package is 'ripgrep'.

I can fix this by replacing 'oldripgrep' with 'ripgrep' in configuration.nix.
Should I proceed?
```

---

## 29. When to Escalate to the User

Some situations require user decision-making. **Always escalate, don't guess:**

### Escalation Scenarios

- **Ambiguous requests:** User says "add a browser" but doesn't specify which one
- **Security decisions:** Before disabling security modules or firewall rules
- **System changes:** Large architectural changes affecting multiple modules
- **Resource-intensive operations:** Adding large tools/services that consume disk space
- **Conflicting requirements:** User wants mutually exclusive configurations
- **Package availability:** When the exact package you need doesn't exist
- **Breaking changes:** When a change might break existing functionality

### How to Escalate

1. **Explain the decision needed clearly**
2. **Provide options with pros/cons**
3. **Ask specifically what the user prefers**
4. **Wait for response before proceeding**

Example:
```
You mentioned adding Python support. Do you want:

Option 1: Full Python development (python, pip, poetry, jupyter)
- Includes: python312, python312-packages, jupyter
- Use case: Data science, ML, general development
- Build impact: ~500MB additional

Option 2: Minimal Python (just python312)
- Lightweight, quick build
- Use case: Running Python scripts
- Build impact: ~50MB

Which would you prefer, or should I add something else?
```

---

## 30. Resource Limits and Considerations

### Disk Space

This system uses NixOS which stores all packages in `/nix/store/`:
- Default `/nix/store/` partition: Usually 50GB+ required
- Each rebuild adds new entries (old ones kept as GC roots)
- Regular garbage collection recommended: `nix-collect-garbage -d`
- Be mindful when adding large packages (databases, ML frameworks, etc.)

### Build Time

Different changes have different build impacts:
- **Small changes** (config tweaks): 1-3 minutes
- **Adding packages**: 2-10 minutes (depending on package)
- **Full rebuild**: 10-30 minutes or more
- **Large dependencies** (rust, haskell, etc.): 20+ minutes

Check before suggesting major additions: "This package may take 15+ minutes to build. Proceed?"

### System Stability

This is a production system being actively used:
- Test changes thoroughly before suggesting rebuild
- Never break critical functionality without recovery plan
- Always know how to revert changes (previous generation boot)
- Be especially careful with core packages and security modules

### Memory Usage During Build

NixOS builds can consume significant RAM:
- Ask user if they want to proceed with large builds
- Suggest doing builds during off-peak hours for system-level changes
- Note that builds may temporarily freeze UI during peak resource usage

---

## 31. Final Verification Before Telling User "Done"

**Never** tell the user a change is complete without verifying ALL of these:

- [ ] All modified files have been read and edited correctly
- [ ] `nix flake check` passes with no warnings or errors
- [ ] `nix flake show` displays expected outputs
- [ ] `nixos-rebuild build --flake .#atlas` completes successfully
- [ ] ALL documentation has been updated (README.md, module docs, comments)
- [ ] No files were created outside `/home/yusa/Atlas/`
- [ ] No `sudo` was used on source file operations
- [ ] Code style is consistent (2-space indentation, proper formatting)
- [ ] Explained changes clearly to user with file paths and line numbers
- [ ] Provided user with next steps (if rebuild needed)
- [ ] Listed all modified files
- [ ] Confirmed no security implications or side effects

If ANY of these are not complete, say so explicitly and finish before declaring success.

---

## 32. Helpful Resources and References

### Tools and Commands Quick Reference

For agents working on this system, these commands are most useful:

```bash
# Validation (run before suggesting rebuild)
nix flake check --show-trace          # Detailed syntax validation
nix flake show                        # Show flake outputs
nixos-rebuild build --flake .#atlas   # Build without applying

# Searching
nix search nixpkgs#package_name       # Find packages
git log --oneline -10                 # Recent commits
git diff HEAD~1 files/core/config.nix # See specific file changes

# System info
git status                            # See modified files
git diff                              # See all changes

# Emergency (as last resort)
git checkout -- files/path/file.nix   # Revert single file
```

### Common File Locations Quick Reference

```
System packages:    files/core/configuration.nix (around line 50-80)
User packages:      files/core/home.nix (search for "packages =")
Dev tools:          files/modules/dev/dev.nix
Security:           files/modules/security/*.nix
Keybindings:        files/modules/dev/nvim/keymaps.lua (or Niri config)
```

### Nix Learning Resources

If you need to understand Nix better:
- NixOS Manual: https://nixos.org/manual/nixos/stable/
- Nixpkgs Manual: https://nixos.org/manual/nixpkgs/stable/
- Search packages: https://search.nixos.org/packages
- This project's flake.nix and modules are good examples

---

## 33. Ethical Guidelines for Agents

As an agent modifying this personal system, follow these principles:

### Transparency
- Always explain exactly what you're changing
- Show old vs new code when making modifications
- Don't hide changes in complex code

### Respect User Autonomy
- Don't make "helpful" changes without permission
- Ask before making anything more than requested
- Let user make final decisions on important changes

### Reliability
- Test before you suggest
- Own your mistakes and fix them
- Report honestly about what you don't know

### Humility
- Don't claim to understand things you don't
- Ask user for clarification
- Admit when something is outside your capability

### Security Awareness
- Never weaken security without explicit user request and understanding
- Document security implications of changes
- Be cautious with system-level modifications

### Efficiency
- Batch related changes together (don't rebuild multiple times)
- Minimize build times when possible
- Respect the user's system resources
