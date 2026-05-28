#!/usr/bin/env bash
# ============================================================================
# DAEMON BEHAVIORAL TEST HELPERS
# ============================================================================
# Shared utilities for all daemon/service behavioral tests.
# Sources: source helpers.sh from each test file.
# ============================================================================

set -uo pipefail

# ─── Globals ─────────────────────────────────────────────────────────────────
BASE="${ATLAS_BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PASS=0; FAIL=0; SKIP=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'

# ─── Temp Directory Management ──────────────────────────────────────────────
CLEANUP_DIRS=()

_mktemp() {
  local d
  d=$(mktemp -d "$1" 2>/dev/null) || return 1
  CLEANUP_DIRS+=("$d")
  echo "$d"
}

_cleanup_all() {
  for d in "${CLEANUP_DIRS[@]}"; do
    [ -d "$d" ] && rm -rf "$d" 2>/dev/null || true
  done
}
trap _cleanup_all EXIT

# ─── Test Reporting ─────────────────────────────────────────────────────────
HEADER_DONE=false

header() {
  echo -e "\n${CYAN}════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}════════════════════════════════════════${NC}"
}

pass()  { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $1"; }
skip()  { SKIP=$((SKIP+1)); echo -e "  ${YELLOW}⊘${NC} $1"; }

# ─── Tool Availability ──────────────────────────────────────────────────────
has_tool()   { command -v "$1" &>/dev/null; }
has_binary() { [ -x "$1" ] 2>/dev/null; }

# ─── Assertion Utilities ────────────────────────────────────────────────────
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
    return 0
  else
    fail "$label (expected: '$expected', got: '$actual')"
    return 1
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    pass "$label"
    return 0
  else
    fail "$label (expected output to contain '$needle')"
    echo -e "    ${YELLOW}Output:${NC} $(echo "$haystack" | head -5 | tr '\n' ';')"
    return 1
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    pass "$label"
    return 0
  else
    fail "$label (file '$path' not found)"
    return 1
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    pass "$label"
    return 0
  else
    fail "$label (file '$path' still exists)"
    return 1
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    pass "$label"
    return 0
  else
    fail "$label (output UNEXPECTEDLY contains '$needle')"
    echo -e "    ${YELLOW}Output:${NC} $(echo "$haystack" | head -3 | tr '\n' ';')"
    return 1
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    pass "$label"
    return 0
  else
    fail "$label (exit code $actual, expected $expected)"
    return 1
  fi
}

# ─── Timed command execution ────────────────────────────────────────────────
run_with_timeout() {
  local timeout_sec="$1" desc="$2"
  shift 2
  local result_file out_file
  result_file=$(_mktemp /tmp/test_result.XXXXXX 2>/dev/null)
  out_file=$(_mktemp /tmp/test_out.XXXXXX 2>/dev/null)

  if timeout "$timeout_sec" bash -c "$*" >"$out_file" 2>&1; then
    echo "0" > "$result_file"
  else
    local rc=$?
    echo "$rc" > "$result_file"
  fi

  local rc
  rc=$(cat "$result_file" 2>/dev/null || echo 124)
  local output
  output=$(cat "$out_file" 2>/dev/null || echo "")
  echo "$output"
  return "$rc"
}

# ─── EICAR Test File ────────────────────────────────────────────────────────
create_eicar_file() {
  local dir="$1" name="${2:-eicar.com.txt}"
  echo -n 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > "$dir/$name"
  echo "$dir/$name"
}

create_safe_file() {
  local dir="$1" name="${2:-safe.txt}"
  echo "This is a harmless text file for testing." > "$dir/$name"
  echo "$dir/$name"
}

# ─── Minimal JPEG with EXIF (pure Python, no deps) ─────────────────────────
create_test_jpeg_with_exif() {
  local output="$1"
  python3 -c "
import struct, zlib, os

def make_chunk(chunk_type, data):
    crc = zlib.crc32(chunk_type + data) & 0xffffffff
    return struct.pack('>I', len(data)) + chunk_type + data + struct.pack('>I', crc)

# PNG with text chunks (similar testing concept)
# Minimal 1x1 red PNG with tEXt metadata
width, height = 1, 1
raw_data = b''
for y in range(height):
    raw_data += b'\x00'  # filter none
    for x in range(width):
        raw_data += b'\xff\x00\x00'  # red pixel

compressed = zlib.compress(raw_data)

png = b'\x89PNG\r\n\x1a\n'  # PNG signature
png += make_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
png += make_chunk(b'tEXt', b'Author\x00Test Author Name')
png += make_chunk(b'tEXt', b'Copyright\x00Copyright 2024 Test User')
png += make_chunk(b'tEXt', b'Description\x00Test image with embedded metadata')
png += make_chunk(b'tEXt', b'Software\x00TestCamera v1.0')
png += make_chunk(b'tEXt', b'GPSInfo\x00Latitude: 48.8566N, Longitude: 2.3522E')
png += make_chunk(b'IDAT', compressed)
png += make_chunk(b'IEND', b'')

with open('$output', 'wb') as f:
    f.write(png)
print('Created test PNG: $output')
" 2>&1
}

create_test_jpeg_without_exif() {
  local output="$1"
  python3 -c "
import struct, zlib

def make_chunk(chunk_type, data):
    crc = zlib.crc32(chunk_type + data) & 0xffffffff
    return struct.pack('>I', len(data)) + chunk_type + data + struct.pack('>I', crc)

width, height = 1, 1
raw_data = b''
for y in range(height):
    raw_data += b'\x00'
    for x in range(width):
        raw_data += b'\x00\xff\x00'

compressed = zlib.compress(raw_data)

png = b'\x89PNG\r\n\x1a\n'
png += make_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
png += make_chunk(b'IDAT', compressed)
png += make_chunk(b'IEND', b'')

with open('$output', 'wb') as f:
    f.write(png)
print('Created clean test PNG: $output')
" 2>&1
}

# ─── Extract inline script from Nix file ──────────────────────────────────
# Prints the content of a Nix inline shell script (writeShellScript) block.
# This is a heuristic: finds the ExecStart line and extracts the script body.
extract_script_from_nix() {
  local nix_file="$1" script_name="$2"
  "$BASE/tests/tools/extract_writeShellScript.py" "$nix_file" "$script_name" 2>/dev/null || return 1
}

# ─── Kernel/Memory/Module Test Helpers ──────────────────────────────────────

# Validate a kernel sysctl value exists in the Nix config
check_sysctl_value() {
  local nix_file="$1" sysctl_name="$2" expected_value="$3"
  local label="${4:-sysctl $sysctl_name = $expected_value}"
  if grep -q "\"$sysctl_name\".*=.*$expected_value" "$nix_file" 2>/dev/null; then
    pass "$label"
    return 0
  else
    fail "$label (not found in $nix_file)"
    return 1
  fi
}

# Validate a kernel boot parameter exists
check_boot_param() {
  local nix_file="$1" param="$2"
  local label="${3:-boot param: $param}"
  if grep -q "\"$param\"" "$nix_file" 2>/dev/null; then
    pass "$label"
    return 0
  else
    fail "$label (not found in $nix_file)"
    return 1
  fi
}

# Check that a blocked/blacklisted module exists
check_blocked_module() {
  local nix_file="$1" module="$2"
  local label="${3:-blocked module: $module}"
  if grep -q "$module" "$nix_file" 2>/dev/null; then
    pass "$label"
    return 0
  else
    fail "$label (not blocked in $nix_file)"
    return 1
  fi
}

# Check a Nix config value exists with given pattern
check_nix_value() {
  local nix_file="$1" pattern="$2"
  local label="${3:-config: $pattern}"
  if grep -q "$pattern" "$nix_file" 2>/dev/null; then
    pass "$label"
    return 0
  else
    fail "$label (not found)"
    return 1
  fi
}

# ─── Service Discovery Utilities ────────────────────────────────────────────

# Discover all systemd.services defined in a .nix file
discover_services() {
  local nix_file="$1"
  grep -oP 'systemd\.services\.\K["]?[a-zA-Z0-9._-]+["]?' "$nix_file" 2>/dev/null | tr -d '"' | sort -u || true
}

# Discover all systemd.paths defined in a .nix file
discover_paths() {
  local nix_file="$1"
  grep -oP 'systemd\.paths\.\K["]?[a-zA-Z0-9._-]+["]?' "$nix_file" 2>/dev/null | tr -d '"' | sort -u || true
}

# Discover all systemd.timers defined in a .nix file
discover_timers() {
  local nix_file="$1"
  grep -oP 'systemd\.timers\.\K["]?[a-zA-Z0-9._-]+["]?' "$nix_file" 2>/dev/null | tr -d '"' | sort -u || true
}

# Discover all systemd.user.services defined in a .nix file
discover_user_services() {
  local nix_file="$1"
  grep -oP 'systemd\.user\.services\.\K["]?[a-zA-Z0-9._-]+["]?' "$nix_file" 2>/dev/null | tr -d '"' | sort -u || true
}

# ─── Service Hardening Utilities ────────────────────────────────────────────

# Check that a service in a Nix file has a specific hardening directive
check_service_hardening() {
  local nix_file="$1" service_name="$2" directive="$3"
  local label="${4:-$service_name: has $directive}"

  # Look for the directive within the serviceConfig block of the named service
  if grep -zP "services\.$service_name.*?serviceConfig.*?$directive" "$nix_file" 2>/dev/null | tr '\0' '\n' | grep -q "$directive"; then
    pass "$label"
    return 0
  fi
  # Broader search: just check directive appears near service name
  if grep -A30 "services\.$service_name\|services\.\"$service_name\"" "$nix_file" 2>/dev/null | grep -q "$directive"; then
    pass "$label"
    return 0
  fi
  fail "$label"
  return 1
}

# ─── Summary ────────────────────────────────────────────────────────────────
print_summary() {
  local suite_name="${1:-Daemon Behavioral Tests}"
  TOTAL=$((PASS + FAIL + SKIP))
  echo -e "\n${CYAN}════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $suite_name — Results${NC}"
  echo -e "${CYAN}════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}PASS:${NC} $PASS"
  echo -e "  ${RED}FAIL:${NC} $FAIL"
  echo -e "  ${YELLOW}SKIP:${NC} $SKIP"
  echo -e "  Total: $TOTAL"
  # Machine-parseable summary line
  echo "MODULE_RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"

  if [ "$FAIL" -gt 0 ]; then
    echo -e "\n  ${RED}✗ FAILURES DETECTED${NC}"
    return 1
  elif [ "$SKIP" -gt 0 ] && [ "$PASS" -eq 0 ]; then
    echo -e "\n  ${YELLOW}⊘ ALL TESTS SKIPPED (no tools available?)${NC}"
    return 2
  else
    echo -e "\n  ${GREEN}✓ ALL TESTS PASSED${NC}"
    return 0
  fi
}
