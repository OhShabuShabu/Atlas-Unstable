# =============================================================================
# Nushell Configuration (like .bashrc)
# =============================================================================
# This file is sourced by Nushell on startup

#$env.PATH = ($env.PATH | append "$HOME/.local/bin")

# INFO: ALIASES
alias motivate = python3 ($env.HOME | path join "Atlas/files/bin/python/motivate")

# INFO: Security tool aliases
alias logs = ^sudo sh -c "ls -1rt /var/log/*.log | fzf --height=40% --layout=reverse --ansi | xargs -r lnav"
alias security-logs = ^sudo sh -c "ls -1rt /var/log/lynis.log /var/log/audit/audit.log /var/log/clamav/*.log /var/log/snout/*.log 2>/dev/null | fzf --height=40% --layout=reverse --ansi | xargs -r lnav"
alias lynis-scan = ^sudo lynis audit system --quick
alias aide-check = ^sudo aide --check
alias snout-status = ^sudo systemctl status snout-daemon
alias snout-logs = ^sudo journalctl -fu snout-daemon
alias snout-scan = ^sudo snout scan

# INFO: Trash aliases
alias trash = ^trash
alias trash-list = ^trash list
alias trash-restore = ^trash restore
alias trash-put = ^trash put

motivate