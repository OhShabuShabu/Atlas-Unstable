# =============================================================================
# Nushell Configuration (like .bashrc)
# =============================================================================
# This file is sourced by Nushell on startup

#$env.PATH = ($env.PATH | append "$HOME/.local/bin")

# INFO: ALIASES
# INFO: Security tool aliases
alias logs = ^sudo sh -c "ls -1rt /var/log/*.log | fzf --height=40% --layout=reverse --ansi | xargs -r lnav"
alias security-logs = ^sudo sh -c "ls -1rt /var/log/lynis.log /var/log/audit/audit.log /var/log/clamav/*.log /var/log/snout/*.log 2>/dev/null | fzf --height=40% --layout=reverse --ansi | xargs -r lnav"
alias lynis-scan = ^sudo lynis audit system --quick
alias aide-check = ^sudo aide --check
alias snout-status = ^sudo systemctl status snout-daemon
alias snout-logs = ^sudo journalctl -fu snout-daemon
alias snout-scan = ^sudo snout scan
alias snort-status = ^sudo systemctl status snort-daemon
alias snort-alerts = ^sudo tail -f /var/log/snort/alert_csv.txt
alias snortctl = ^sudo snortctl

# INFO: Trash aliases
alias trash = ^trash
alias trash-list = ^trash list
alias trash-restore = ^trash restore
alias trash-put = ^trash put

# ============================================================================
# DEVELOPMENT SHORTCUTS
# ============================================================================

# NixOS shortcuts
alias nr = atlas-rebuild
alias nrb = nixos-rebuild build --flake /home/yusa/Atlas#atlas
alias nix-check = nix flake check --show-trace
alias nix-show = nix flake show
alias test-config = bash /home/yusa/Atlas/test_config.sh

# System health
alias health = atlas-health
alias health-quick = atlas-health quick
alias hardware-detect = atlas-hardware-detect

# Nix searching and profiling
alias nix-search = nix search nixpkgs
alias nix-repl = nix repl

# Package management
alias garbage-collect = nix-collect-garbage -d

# ============================================================================
# GIT SHORTCUTS
# ============================================================================

alias gs = git status
alias ga = git add
alias gc = git commit -m
alias gp = git push
alias gl = git log --oneline -10
alias gd = git diff

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

# Quick system info
alias mem-usage = ^free -h
alias cpu-temp = ^sensors

# ============================================================================
# NAVIGATION SHORTCUTS
# ============================================================================

alias atlas = cd /home/yusa/Atlas
alias la = ls --all
alias ll = ls --long