#!/usr/bin/env python3
"""
Extract a writeShellScript or writeShellScriptBin block from a .nix file.
Usage: extract_writeShellScript.py <nix_file> <script_name> [output_file]

Properly handles Nix '' quoting ('''' for literal ', ''$ for literal $).
"""
import re, sys

nix_file = sys.argv[1]
script_name = sys.argv[2]
output_file = sys.argv[3] if len(sys.argv) > 3 else None

with open(nix_file) as f:
    content = f.read()

# Look for writeShellScript "name" '' ... ''
# Nix '' strings: '' opens/closes, '''=' (two quotes+non-dollar) is a literal quote escape,
# '' followed by $ is literal dollar (not a Nix variable)
# We find the opening '' and read until the closing '' that is NOT an escape sequence

# Strategy: find the pattern writeShellScript "name" then locate the '' after it
# Then walk through character by character to find the closing ''
patterns = [
    rf'writeShellScript\s+"{re.escape(script_name)}"\s+',
    rf'writeShellScript\s+"{re.escape(script_name)}\.sh"\s+',
    rf'writeShellScriptBin\s+"{re.escape(script_name)}"\s+',
]

for pattern in patterns:
    m = re.search(pattern, content)
    if not m:
        continue

    # Content starts after the opening '' and closing newline
    start_idx = m.end()
    # Skip whitespace and opening ''
    rest = content[start_idx:]
    if not rest.startswith("''"):
        # Skip any whitespace before ''
        ws_match = re.match(r'\s*', rest)
        if ws_match:
            start_idx += ws_match.end()
            rest = content[start_idx:]
        if not rest.startswith("''"):
            continue
    
    # Skip the opening ''
    pos = start_idx + 2
    result_chars = []
    depth = 0
    
    while pos < len(content):
        c = content[pos]
        # Check for Nix escape sequences within '' string
        if c == "'" and pos + 1 < len(content) and content[pos + 1] == "'":
            if pos + 2 < len(content) and content[pos + 2] == "'":
                # ''' = literal ' (escaped quote)
                result_chars.append("'")
                pos += 3
            elif pos + 2 < len(content) and content[pos + 2] == "$":
                # ''$ = literal $ (not Nix interpolation)
                result_chars.append("$")
                pos += 3
            else:
                # '' = end of string
                # Skip newline after closing '' if present
                break
        elif c == "\n" and result_chars and result_chars[-1] == "\n" and content[pos-2:pos] == "''":
            # This shouldn't happen - already handled above
            pos += 1
        else:
            result_chars.append(c)
            pos += 1

    if result_chars:
        result = ''.join(result_chars).strip()
        # Remove trailing ';' which is Nix statement separator
        if result.endswith(';'):
            result = result[:-1].strip()
        if output_file:
            with open(output_file, 'w') as out:
                out.write(result)
            print(f"Extracted {len(result)} bytes to {output_file}")
        else:
            print(result)
        sys.exit(0)

print(f"ERROR: writeShellScript '{script_name}' not found in {nix_file}", file=sys.stderr)
sys.exit(1)
