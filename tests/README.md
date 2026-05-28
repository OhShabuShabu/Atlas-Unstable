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
| `test_systemd.sh` | Service definitions, timers, path units, hardening consistency, deps | None |
| `test_scripts.sh` | atlas-health, detect-hardware, fix_rgb_color, CLI command parsing | `python3` |

Tools marked **optional** gracefully skip their behavioral tests if unavailable.

## Test Architecture

```
tests/
├── run.sh               # Main entry point — runs all modules, aggregates results
├── helpers.sh           # Shared utilities: temp dirs, assertions, reporting, EICAR helper
├── test_clamav.sh       # ClamAV virus detection tests
├── test_metadata.sh     # Metadata stripper tests
├── test_snout.sh        # Snout quarantine watcher tests
├── test_quarantine.sh   # Quarantine system tests
├── test_aide.sh         # AIDE integrity tests
├── test_snort.sh        # Snort NIDS tests
├── test_systemd.sh      # Systemd integration tests
├── test_scripts.sh      # CLI script tests
└── README.md            # This file
```

## Testing Strategy

1. **Script Extraction**: Inline shell scripts from `.nix` files are extracted
   and analyzed for correctness (argument handling, edge cases, error paths).

2. **Sandboxed Execution**: Behavioral tests create files in `mktemp -d`
   directories. No real system paths are modified.

3. **Tool Integration**: When `clamscan`, `exiftool`, `aide`, or `snort` are
   installed, tests validate actual tool behavior (EICAR detection, metadata
   removal, etc.). When absent, tests skip gracefully.

4. **Service Definition Analysis**: Systemd service files are validated for
   proper Type, Restart, After/Before dependencies, and hardening directives.

5. **Log Format Validation**: Expected log patterns (JSON, CSV, timestamped
   entries) are verified against the daemon specifications.

6. **Edge Case Coverage**: Idempotency, empty state handling, missing
   dependencies, timeout protection, and malformed input are tested.

## CI Integration

The test suite returns standard exit codes:
- `0` — All tests passed
- `1` — One or more tests failed
- `2` — All tests were skipped (tools unavailable)

Output is TAP-friendly and color-coded for terminal viewing.
