# Development Module

Provides comprehensive development tools and language runtimes.

## Included Languages
- **Rust** — rustup, cargo, rust-analyzer
- **Go** — go, gopls
- **Node.js** — nodejs, bun
- **Python** — python312, pip
- **C/C++** — gcc, clang, cmake

## Included Tools
- **Git** — version control
- **Neovim** — LazyVim configuration with LSP support
- **Docker/Podman** — containerization
- **Build Tools** — make, cmake, pkg-config

## Neovim Configuration

Located in: `files/modules/dev/nvim/`

Configured with LazyVim with sensible defaults for web, Python, and Rust development.

## Language Servers

Automatically installed LSP servers:
- rust-analyzer (Rust)
- gopls (Go)
- pylsp (Python)
- tsserver (TypeScript/JavaScript)

Use `:LspInfo` in Neovim to see active servers.

## Adding New Languages

To add a new language:

1. Open `files/modules/dev/dev.nix`
2. Find the language section
3. Add package to the list (e.g., `python312`)
4. Rebuild: `sudo nixos-rebuild switch --flake .#atlas`
