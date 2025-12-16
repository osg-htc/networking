#!/usr/bin/env bash
# repair-state-json.sh
# --------------------
# Repair corrupted JSON state files from fasterdata-tuning.sh versions < 1.3.2
#
# This script fixes common JSON formatting issues:
# - Unquoted string values (e.g., :Mini: -> :"Mini:", :auto -> :"auto", :push -> :"push")
# - Newlines embedded in string values
# - Other common JSON formatting errors
#
# Usage: repair-state-json.sh <input.json> [output.json]
#   If output.json is omitted, creates input.json.repaired

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] <input.json> [output.json]

Repair corrupted JSON state files from fasterdata-tuning.sh.

Arguments:
  input.json    The corrupted JSON file to repair
  output.json   Output file (default: input.json.repaired)

Options:
  -h, --help    Show this help message and exit

The script creates a backup at input.json.backup before repair.
EOF
  exit 1
}

# Parse options
if [[ $# -eq 0 ]]; then
  usage
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-${INPUT_FILE}.repaired}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: Input file not found: $INPUT_FILE" >&2
  exit 1
fi

# Create backup
BACKUP_FILE="${INPUT_FILE}.backup"
if [[ -f "$BACKUP_FILE" ]]; then
  echo "WARNING: Backup file already exists: $BACKUP_FILE"
  echo "Press Enter to overwrite or Ctrl-C to cancel..."
  read -r
fi

cp "$INPUT_FILE" "$BACKUP_FILE"
echo "Created backup: $BACKUP_FILE"

# Copy input to output for processing
cp "$INPUT_FILE" "$OUTPUT_FILE"

# Apply fixes
echo "Applying JSON repairs..."

# Fix 1: Quote unquoted 'Mini:' values (ring buffer issue)
# Pattern: :"rx":Mini: -> :"rx":"Mini"
sed -i 's/:Mini:/:Mini/g' "$OUTPUT_FILE"
sed -i 's/:Mini\([,}]\)/:"Mini"\1/g' "$OUTPUT_FILE"

# Fix 2: Quote 'auto' values (nm_mtu issue)
# Pattern: "nm_mtu":auto -> "nm_mtu":"auto"
sed -i 's/"nm_mtu":auto\([,}]\)/"nm_mtu":"auto"\1/g' "$OUTPUT_FILE"

# Fix 3: Quote 'push' values (ring buffer issue)
# Pattern: :"tx":push -> :"tx":"push"
sed -i 's/:push\([,}]\)/:"push"\1/g' "$OUTPUT_FILE"

# Fix 4: Quote other common non-numeric ring buffer values
sed -i 's/:n\/a\([,}]\)/:"n\/a"\1/gi' "$OUTPUT_FILE"
sed -i 's/:N\/A\([,}]\)/:"N\/A"\1/g' "$OUTPUT_FILE"
sed -i 's/:not available\([,}]\)/:"not available"\1/gi' "$OUTPUT_FILE"
sed -i 's/:unknown\([,}]\)/:"unknown"\1/g' "$OUTPUT_FILE"

# Fix 5: Remove embedded newlines and control characters in JSON strings
# This is trickier - we'll use Python if available
if command -v python3 >/dev/null 2>&1; then
  echo "Using Python to fix embedded newlines and control characters..."
  python3 - "$OUTPUT_FILE" <<'PYEOF'
import sys
import re
import json

if len(sys.argv) < 2:
    sys.exit(1)

filename = sys.argv[1]

try:
    with open(filename, 'r') as f:
        content = f.read()
    
    # First, escape tab characters and other control chars that appear in JSON values
    # Replace literal tabs with escaped tabs in string values
    content = content.replace('\t', '\\t')
    
    # Remove newlines that appear inside string values
    # Pattern: Look for newlines between quotes that aren't valid JSON breaks
    # Simple approach: convert literal newlines within quoted strings to spaces
    lines = content.split('\n')
    if len(lines) > 1:
        # The file should be one line of JSON
        # Join with space to fix embedded newlines
        content = ' '.join(line.strip() for line in lines)
    
    with open(filename, 'w') as f:
        f.write(content)
    
    print("Fixed embedded newlines and control characters")
except Exception as e:
    print(f"Warning: Could not fix newlines: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
else
  echo "Python3 not available - skipping newline repair"
  echo "Manual review may be needed for embedded newlines"
fi

# Validate JSON
echo ""
echo "Validating repaired JSON..."

if command -v jq >/dev/null 2>&1; then
  if jq empty "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ JSON is valid!"
    echo ""
    echo "Repaired file: $OUTPUT_FILE"
    echo "Original backup: $BACKUP_FILE"
    
    # Optionally pretty-print
    if jq . "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" 2>/dev/null; then
      mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
      echo "✓ Formatted JSON for readability"
    fi
  else
    echo "✗ JSON validation failed"
    echo ""
    echo "Attempting to show errors:"
    jq empty "$OUTPUT_FILE" 2>&1 || true
    echo ""
    echo "The file may need manual repair. Check:"
    echo "  - Backup: $BACKUP_FILE"
    echo "  - Partial repair: $OUTPUT_FILE"
    exit 1
  fi
elif command -v python3 >/dev/null 2>&1; then
  if python3 -m json.tool "$OUTPUT_FILE" > /dev/null 2>&1; then
    echo "✓ JSON is valid (validated with Python)!"
    echo ""
    echo "Repaired file: $OUTPUT_FILE"
    echo "Original backup: $BACKUP_FILE"
  else
    echo "✗ JSON validation failed"
    echo ""
    python3 -m json.tool "$OUTPUT_FILE" 2>&1 || true
    echo ""
    echo "The file may need manual repair. Check:"
    echo "  - Backup: $BACKUP_FILE"
    echo "  - Partial repair: $OUTPUT_FILE"
    exit 1
  fi
else
  echo "⚠ Cannot validate JSON (jq and python3 not available)"
  echo "Repair attempted, but validation skipped"
  echo ""
  echo "Repaired file: $OUTPUT_FILE"
  echo "Original backup: $BACKUP_FILE"
fi

echo ""
echo "Done!"
