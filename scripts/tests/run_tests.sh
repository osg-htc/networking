#!/usr/bin/env bash
set -euo pipefail

# Simple smoke tests for scripts in scripts/
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES_DIR="$ROOT_DIR/scripts/tests/fixtures"
TMP_DIR="$(mktemp -d)"

echo "Running smoke tests in $TMP_DIR"
cp -r "$FIXTURES_DIR"/* "$TMP_DIR/"

echo "Testing assign_fence_language.py:"
python3 "$ROOT_DIR/scripts/assign_fence_language.py" "$TMP_DIR" || { echo "assign_fence_language failed"; exit 1; }

if grep -E -q '^\s*`{3,}\s*bash' "$TMP_DIR/sample.md"; then
    echo "OK: assign_fence_language.py added a bash fence"
else
    echo "FAIL: assign_fence_language.py did not add a bash fence" >&2
    exit 2
fi

echo "All smoke tests passed. Cleaning up..."
rm -rf "$TMP_DIR"
echo "Done"
