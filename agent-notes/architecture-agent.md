# Agent: Architecture Agent

## Current Objectives
- Implement whiptail/dialog fallback TUI for pure TTY environments
- Add module load verification script
- Enhance module-manager Nix module with verify option
- Add comprehensive tests for module management

## Files Being Modified
- `files/bin/atlas-module-manager.sh` - Add whiptail/dialog fallback
- `files/bin/atlas-module.sh` - Add verify subcommand
- `files/bin/atlas-module-verify.sh` - New module load verification script
- `files/modules/module-manager/default.nix` - Add verify script to packages, add whiptail dep
- `tests/test_module_manager.sh` - Add load verification tests
- `test_config.sh` - Add module manager verification checks
- `files/core/configuration.nix` - Ensure whiptail is available

## Locks / Claimed Areas
- files/bin/ (scripts)
- files/modules/module-manager/ (Nix module)
- tests/ (test suite)
- agent-notes/ (coordination)

## Planned Changes
1. Create agent-notes/ coordination directory
2. Refactor atlas-module-manager.sh to support fallback backends: fzf -> gum -> dialog -> whiptail
3. Create atlas-module-verify.sh for module load verification
4. Update atlas-module.sh with verify subcommand
5. Update module-manager/default.nix to include new scripts and whiptail
6. Enhance tests with load verification
7. Run test_config.sh to validate

## Completed Changes
- Agent notes created
- Repository fully explored and understood
- Created `atlas-module-verify.sh` - module load verification script
- Added whiptail/dialog/tty fallback to atlas-module-manager.sh (fzf -> gum -> dialog -> whiptail -> tty)
- Added ATLAS_MODULE_UI env var to force a specific backend
- Added `verify` and `tui` subcommands to atlas-module.sh
- Added `moduleVerifyScript` to module-manager/default.nix Nix module
- Added `enableVerifyTimer` option with weekly systemd timer
- Added whiptail dependency to module-manager
- Added comprehensive tests (tests 39-56) for load verification, TTY fallback, error handling
- Updated test_config.sh with tests for new files and features

## Known Issues
- ~~TUI currently only works with fzf, no fallback for pure TTY~~ ✓ Fixed with whiptail/dialog/tty fallback
- ~~No module load verification exists~~ ✓ Added atlas-module-verify.sh
- Load verification is adapted to work offline (no root required) in test mode
- Verify script gracefully handles runtime-only checks (systemd, /proc) when testing

## Suggested Follow-Up Work
- Add module update progress with parallel downloads
- Add module rollback on failed rebuild
- Add module config validation per-module
- Add per-module pre/post activation hooks
- Add module uninstall deps cleanup

## Architectural Decisions
- All new scripts follow existing pattern (writeShellScriptBin in Nix module)
- Verify script is separate to maintain single-responsibility principle
- Whiptail is preferred over dialog for minimal dependency (available in almost all NixOS installs)
- Load verification uses declarative checks: systemd units, package presence, config file existence
- TUI backend selection follows priority chain: fzf > gum > dialog > whiptail > tty
- ATLAS_MODULE_UI env var allows forcing a specific backend
- Error handling tests ensure graceful behavior with missing/corrupt state files

## Testing Performed
- Parsing checks on all modified .nix files
- Full test_config.sh run after changes
- Behavioral tests for verify script, TTY fallback, error handling

## Conflicts / Warnings
- Ensure no overlap with any agent modifying the same bin/ files
