#!/usr/bin/env bash
# Simple regression test: verify --mode apply --dry-run does not actually apply packet pacing
set -euo pipefail
SCRIPT="$(pwd)/docs/perfsonar/tools_scripts/fasterdata-tuning.sh"
if [[ ! -x "$SCRIPT" ]]; then
  echo "Script not found or not executable: $SCRIPT" >&2
  exit 1
fi
# Run dry-run apply (may require sudo for access to some commands); expect messages indicating dry-run
OUT=$(sudo "$SCRIPT" --mode apply --target dtn --apply-packet-pacing --dry-run --yes 2>&1 || true)
# Check for dry-run markers
if ! echo "$OUT" | grep -q "Dry-run: would apply packet pacing"; then
  echo "FAIL: dry-run did not report packet pacing skip" >&2
  echo "Output was:\n$OUT" >&2
  exit 2
fi
# Ensure summary does not claim pacing was enabled
if echo "$OUT" | grep -q "Packet pacing: ENABLED"; then
  echo "FAIL: dry-run unexpectedly shows Packet pacing ENABLED" >&2
  exit 3
fi
# Basic success
echo "PASS: dry-run packet pacing behaved as expected"