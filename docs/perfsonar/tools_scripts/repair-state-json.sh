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
Usage: $0 [OPTIONS] [input.json] [output.json]

Repair corrupted JSON state files from fasterdata-tuning.sh.

Modes:
  Single file:  $0 <input.json> [output.json]
  Batch mode:   $0 --repair-all [directory]

Arguments:
  input.json    The corrupted JSON file to repair
  output.json   Output file (default: input.json.repaired)
  directory     Directory to scan (default: /var/lib/fasterdata-tuning/saved-states)

Options:
  -h, --help       Show this help message and exit
  --repair-all     Repair all JSON files in the specified directory
  --in-place       With --repair-all: repair files in place (original → .corrupt, repaired → original name)

Batch mode behavior:
  Without --in-place: Creates .repaired files, keeps originals with .backup
  With --in-place:    Moves corrupted originals to .corrupt, puts repaired files in original location

The script always creates backups before repair.
EOF
  exit 1
}

# Default directory for batch mode
STATE_DIR="/var/lib/fasterdata-tuning/saved-states"
BATCH_MODE=0
IN_PLACE=0

# Parse options
if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --repair-all)
      BATCH_MODE=1
      shift
      if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        STATE_DIR="$1"
        shift
      fi
      ;;
    --in-place)
      IN_PLACE=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

# If batch mode and there's a remaining argument, use it as the directory
if [[ $BATCH_MODE -eq 1 && $# -gt 0 && -d "$1" ]]; then
  STATE_DIR="$1"
  shift
fi

# Function to repair a single file
repair_single_file() {
  local INPUT_FILE="$1"
  local OUTPUT_FILE="$2"
  local SHOW_PROGRESS="${3:-1}"
  
  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Input file not found: $INPUT_FILE" >&2
    return 1
  fi

  # Create backup
  local BACKUP_FILE="${INPUT_FILE}.backup"
  if [[ -f "$BACKUP_FILE" && $SHOW_PROGRESS -eq 1 ]]; then
    echo "WARNING: Backup file already exists: $BACKUP_FILE"
    echo "Press Enter to overwrite or Ctrl-C to cancel..."
    read -r
  fi

  cp "$INPUT_FILE" "$BACKUP_FILE"
  [[ $SHOW_PROGRESS -eq 1 ]] && echo "Created backup: $BACKUP_FILE"

  # Copy input to output for processing (skip if same file for in-place repair)
  if [[ "$INPUT_FILE" != "$OUTPUT_FILE" ]]; then
    cp "$INPUT_FILE" "$OUTPUT_FILE"
  fi

  # Apply fixes
  [[ $SHOW_PROGRESS -eq 1 ]] && echo "Applying JSON repairs..."

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
  if command -v python3 >/dev/null 2>&1; then
    [[ $SHOW_PROGRESS -eq 1 ]] && echo "Using Python to fix embedded newlines and control characters..."
    python3 - "$OUTPUT_FILE" "$SHOW_PROGRESS" <<'PYEOF'
import sys
import re
import json

if len(sys.argv) < 3:
    sys.exit(1)

filename = sys.argv[1]
show_progress = int(sys.argv[2])

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
    
    if show_progress:
        print("Fixed embedded newlines and control characters")
except Exception as e:
    print(f"Warning: Could not fix newlines: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    if [[ $? -ne 0 ]]; then
      return 1
    fi
  else
    [[ $SHOW_PROGRESS -eq 1 ]] && echo "Python3 not available - skipping newline repair"
    [[ $SHOW_PROGRESS -eq 1 ]] && echo "Manual review may be needed for embedded newlines"
  fi

  # Validate JSON
  [[ $SHOW_PROGRESS -eq 1 ]] && echo ""
  [[ $SHOW_PROGRESS -eq 1 ]] && echo "Validating repaired JSON..."

  if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
      [[ $SHOW_PROGRESS -eq 1 ]] && echo "✓ JSON is valid!"
      
      # Optionally pretty-print
      if jq . "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" 2>/dev/null; then
        mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
        [[ $SHOW_PROGRESS -eq 1 ]] && echo "✓ Formatted JSON for readability"
      fi
      return 0
    else
      [[ $SHOW_PROGRESS -eq 1 ]] && echo "✗ JSON validation failed"
      if [[ $SHOW_PROGRESS -eq 1 ]]; then
        echo ""
        echo "Attempting to show errors:"
        jq empty "$OUTPUT_FILE" 2>&1 || true
      fi
      return 1
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$OUTPUT_FILE" > /dev/null 2>&1; then
      [[ $SHOW_PROGRESS -eq 1 ]] && echo "✓ JSON is valid (validated with Python)!"
      return 0
    else
      [[ $SHOW_PROGRESS -eq 1 ]] && echo "✗ JSON validation failed"
      if [[ $SHOW_PROGRESS -eq 1 ]]; then
        echo ""
        python3 -m json.tool "$OUTPUT_FILE" 2>&1 || true
      fi
      return 1
    fi
  else
    [[ $SHOW_PROGRESS -eq 1 ]] && echo "⚠ Cannot validate JSON (jq and python3 not available)"
    [[ $SHOW_PROGRESS -eq 1 ]] && echo "Repair attempted, but validation skipped"
    return 0
  fi
}

# Batch repair mode
if [[ $BATCH_MODE -eq 1 ]]; then
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "ERROR: Directory not found: $STATE_DIR" >&2
    exit 1
  fi
  
  echo "Scanning for JSON files in: $STATE_DIR"
  
  # Find all .json files (excluding .backup, .repaired, and .corrupt files)
  mapfile -t json_files < <(find "$STATE_DIR" -maxdepth 1 -name "*.json" -type f ! -name "*.backup" ! -name "*.repaired" ! -name "*.corrupt" | sort)
  
  if [[ ${#json_files[@]} -eq 0 ]]; then
    echo "No JSON files found in $STATE_DIR"
    exit 0
  fi
  
  echo "Found ${#json_files[@]} JSON file(s) to process"
  echo ""
  
  success_count=0
  fail_count=0
  skip_count=0
  
  for json_file in "${json_files[@]}"; do
    basename_file=$(basename "$json_file")
    echo "Processing: $basename_file"
    
    # Check if already valid
    if command -v jq >/dev/null 2>&1; then
      if jq empty "$json_file" 2>/dev/null; then
        echo "  ✓ Already valid - skipping"
        skip_count=$((skip_count + 1))
        echo ""
        continue
      fi
    fi
    
    # Determine output file
    if [[ $IN_PLACE -eq 1 ]]; then
      output_file="$json_file"
    else
      output_file="${json_file}.repaired"
    fi
    
    # Repair the file
    if repair_single_file "$json_file" "$output_file" 0; then
      echo "  ✓ Repaired successfully"
      
      # For in-place repairs, rename original to .corrupt and put repaired in original location
      if [[ $IN_PLACE -eq 1 ]]; then
        # The repaired file already has the original name (output_file == json_file)
        # Move the backup to .corrupt
        mv "${json_file}.backup" "${json_file}.corrupt"
        echo "  Corrupted original: $(basename "${json_file}.corrupt")"
      else
        echo "  Output: $(basename "$output_file")"
        echo "  Backup: $(basename "${json_file}.backup")"
      fi
      success_count=$((success_count + 1))
    else
      echo "  ✗ Repair failed"
      fail_count=$((fail_count + 1))
    fi
    echo ""
  done
  
  echo "========================================"
  echo "Batch repair complete!"
  echo "  Total files:    ${#json_files[@]}"
  echo "  Already valid:  $skip_count"
  echo "  Repaired:       $success_count"
  echo "  Failed:         $fail_count"
  echo "========================================"
  
  if [[ $fail_count -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

# Single file mode
if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-${INPUT_FILE}.repaired}"

# Repair single file with progress output
if repair_single_file "$INPUT_FILE" "$OUTPUT_FILE" 1; then
  echo ""
  echo "Repaired file: $OUTPUT_FILE"
  echo "Original backup: ${INPUT_FILE}.backup"
  echo ""
  echo "Done!"
  exit 0
else
  echo ""
  echo "The file may need manual repair. Check:"
  echo "  - Backup: ${INPUT_FILE}.backup"
  echo "  - Partial repair: $OUTPUT_FILE"
  exit 1
fi
