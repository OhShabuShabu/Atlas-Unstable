# Atlas Daemon Behavioral Test Suite

Tests all custom daemons and services for **behavioral correctness** — not just
static existence checks. Tests are safe to run without root, use isolated temp
directories, and clean up after themselves.

## Quick Start

```bash
# Run all tests (single command):
bash tests/run.sh

# Run individual test modules:
bash tests/test_clamav.sh
bash tests/test_metadata.sh
bash tests/test_snout.sh
bash tests/test_quarantine.sh
bash tests/test_aide.sh
bash tests/test_snort.sh
bash tests/test_memory_wipe.sh
bash tests/test_security_base.sh
bash tests/test_ima_evm.sh
bash tests/test_luks_tpm.sh
bash tests/test_systemd.sh
bash tests/test_scripts.sh
```

## Test Modules

| Module | What It Tests | Tools Needed |
|--------|---------------|--------------|
| `test_clamav.sh` | EICAR detection, quarantine workflow, recursive scanning, script logic | `clamscan` (optional) |
| `test_metadata.sh` | EXIF/GPS/author striping, idempotency, recursive dirs, file extension coverage | `exiftool` (optional) |
| `test_snout.sh` | Quarantine monitoring logic, ClamAV integration, event logging | `clamscan` (optional) |
| `test_quarantine.sh` | Setup script, sanitizer logic, shutdown cleanup, list/purge commands | None |
| `test_aide.sh` | Config validation, init/check script logic, binary tests | `aide` (optional) |
| `test_snort.sh` | Rule syntax validation, config parsing, monitor daemon logic, snortctl CLI | `snort` (optional) |
| `test_memory_wipe.sh` | dram-wiper (DRAM cold boot), shutdown-wiper (log/swap shred), sleep-state hardening | None |
| `test_security_base.sh` | Kernel sysctl (40+ params), boot params, module blacklist, firewall rules, network privacy, password policy, telemetry, banner | None |
| `test_ima_evm.sh` | IMA measurement policy, EVM HMAC key setup, evm-sign-binary CLI, kernel params | None |
| `test_luks_tpm.sh` | LUKS keyfile unseal/enroll, TPM PCR policy, swapfile creation, cryptenroll | None |
| `test_systemd.sh` | Auto-discovered service definitions, timers, path units, hardening matrix, deps, types, restart policies | None |
| `test_scripts.sh` | atlas-health, detect-hardware, fix_rgb_color, CLI command parsing | `python3` |

Tools marked **optional** gracefully skip their behavioral tests if unavailable.

## Test Architecture

```
tests/
├── run.sh               # Main entry point — runs all modules, aggregates results
├── helpers.sh           # Shared utilities: temp dirs, assertions, reporting, EICAR helper
├── README.md            # This file
├── test_clamav.sh       # ClamAV virus detection tests
├── test_metadata.sh     # Metadata stripper tests
├── test_snout.sh        # Snout quarantine watcher tests
├── test_quarantine.sh   # Quarantine system tests
├── test_aide.sh         # AIDE integrity tests
├── test_snort.sh        # Snort NIDS tests
├── test_memory_wipe.sh  # Memory wipe + shutdown forensics tests
├── test_security_base.sh# Kernel, firewall, password, telemetry tests
├── test_ima_evm.sh      # IMA/EVM kernel integrity tests
├── test_luks_tpm.sh     # LUKS/TPM encryption tests
├── test_systemd.sh      # Systemd integration tests
├── test_scripts.sh      # CLI script tests
└── tools/
    ├── extract_nix_block.py
    └── extract_writeShellScript.py
```

## Testing Strategy

1. **Script Extraction**: Inline shell scripts from `.nix` files are extracted
   and analyzed for correctness (argument handling, edge cases, error paths).

2. **Sandboxed Execution**: Behavioral tests create files in `mktemp -d`
   directories. No real system paths are modified.

3. **Tool Integration**: When `clamscan`, `exiftool`, `aide`, or `snort` are
   installed, tests validate actual tool behavior (EICAR detection, metadata
   removal, etc.). When absent, tests skip gracefully.

4. **Service Auto-Discovery**: `test_systemd.sh` scans Nix files for
   `systemd.services`, `systemd.paths`, `systemd.timers`, and
   `systemd.user.services` definitions rather than using hardcoded lists.

5. **Hardening Matrix**: All service hardening directives (NoNewPrivileges,
   ProtectSystem, PrivateTmp, etc.) are counted and validated across the
   security module directory.

6. **Log Format Validation**: Expected log patterns are verified against
   daemon specifications for all services.

7. **Edge Case Coverage**: Idempotency, empty state handling, missing
   dependencies, timeout protection, and malformed input are tested.

8. **Service Lifecycle**: Service Type (simple/oneshot), Restart policy,
   dependency ordering (after/before/wants), and wantedBy targets are
   validated for every service.

## CI Integration

The test suite returns standard exit codes:
- `0` — All tests passed
- `1` — One or more tests failed
- `2` — All tests were skipped (tools unavailable)

Output is machine-parseable with `MODULE_RESULT: PASS=N FAIL=N SKIP=N` lines.

## Coverage Map

```
Service/Module              test_config  behavioral  Notes
────────────────────────────────────────────────────────────────
clamav-daemon                    ✓           ✓      EICAR, quarantine, script
clamav-daily-scan                ✓           ✓      Timer, script logic
clamav-tmp-scan                  ✓           ✓      Frequent /tmp scan
metadata-stripper-watcher        ✓           ✓      EXIF stripping, idempotency
metadata-stripper-daily          ✓           ✓      Timer, sweep logic
snout-watcher                    ✓           ✓      Quarantine monitoring
quarantine-setup                 ✓           ✓      Dir creation, permissions
quarantine-sanitizer             ✓           ✓      chmod 0000, chown root
quarantine-cleanup               ✓           ✓      Shred, shutdown cleanup
aide-init                        ✓           ✓      DB init, idempotency
aide-check                       ✓           ✓      Integrity check, timer
snort-daemon                     ✓           ✓      Config, rules, CLI
snort-monitor                    ✓           ✓      Alert parsing, notifications
dram-wiper                       -           ✓      Swapoff, page cache drop
shutdown-wiper                   -           ✓      Log/temp/swap shred
kernel-sysctl                    ✓           ✓      40+ sysctl params
kernel-boot                      ✓           ✓      Boot params, module blocking
firewall                         ✓           ✓      Ports, interfaces, RP filter
network-privacy                  ✓           ✓      MAC randomization
password-policy                  ✓           ✓      YESCRYPT, PASS_MAX_DAYS
telemetry                        ✓           ✓      Avahi/Geoclue disabled
banner                           ✓           ✓      Login warning
IMA/EVM                          -           ✓      Policy, key setup, params
LUKS keyfile                     -           ✓      Unseal, enroll, TPM
TPM enrollment                   -           ✓      systemd-cryptenroll, PCRs
swapfile                         -           ✓      Nodatacow, fallocate
process-accounting               ✓           ✓      accton, aliases
service-hardening                ✓           ✓      All 17 directives counted
usbguard                         ✓           -      Static only (needs root)
sshd                             ✓           -      Static only (needs root)
```

## Test Naming Convention

- `pass` — Test passed successfully
- `fail` — Test found a definite problem
- `skip` — Test skipped (tool not available or optional dependency missing)
- `warn` — Non-critical issue worth noting
