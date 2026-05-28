#!/usr/bin/env python3
"""
Extract content from a Nix multi-line string (''...'') block.
Usage: extract_nix_block.py <nix_file> <pattern_prefix> [output_file]

The pattern_prefix is text that appears right before the opening ''.
Properly handles Nix '' quoting ('''' for literal ', ''$ for literal $).
Returns exit code 0 if found, 1 if not.
"""
import re, sys

nix_file = sys.argv[1]
pattern_prefix = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

with open(nix_file) as f:
    content = f.read()

# Find the pattern prefix
escaped_prefix = re.escape(pattern_prefix)
m = re.search(escaped_prefix, content)
if not m:
    print(f"ERROR: Pattern '{pattern_prefix}' not found in {nix_file}", file=sys.stderr)
    sys.exit(1)

# Start after the pattern (skip whitespace/newlines to find opening '')
start_idx = m.end()
rest = content[start_idx:]
ws_match = re.match(r'\s*', rest)
if ws_match:
    start_idx += ws_match.end()

# Check for opening ''
if not content[start_idx:start_idx+2] == "''":
    print(f"ERROR: No opening '' after pattern in {nix_file}", file=sys.stderr)
    sys.exit(1)

# Walk through characters to extract until closing ''
pos = start_idx + 2
result_chars = []

while pos < len(content):
    c = content[pos]
    if c == "'" and pos + 1 < len(content) and content[pos + 1] == "'":
        if pos + 2 < len(content) and content[pos + 2] == "'":
            # ''' = literal ' (escaped quote in Nix)
            result_chars.append("'")
            pos += 3
        elif pos + 2 < len(content) and content[pos + 2] == "$":
            # ''$ = literal $ (not Nix interpolation)
            result_chars.append("$")
            pos += 3
        else:
            # '' = end of string
            pos += 2
            break
    elif c == "\\" and pos + 1 < len(content):
        # Preserve backslash sequences (for exiftool, regex patterns, etc.)
        result_chars.append(c)
        result_chars.append(content[pos + 1])
        pos += 2
    else:
        result_chars.append(c)
        pos += 1

result = ''.join(result_chars).strip()
# Remove trailing ';' if present (Nix statement separator)
if result.endswith(';'):
    result = result[:-1].strip()

if not result:
    print(f"ERROR: Empty extraction from {nix_file}", file=sys.stderr)
    sys.exit(1)

if output_file:
    with open(output_file, 'w') as out:
        out.write(result)
    print(f"Extracted {len(result)} bytes to {output_file}")
else:
    print(result)
sys.exit(0)
