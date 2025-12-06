#!/usr/bin/env bash
set -euo pipefail

# Verify that docs and site copies for scripts are in sync and that sha256 values match
ROOT=$(dirname "${BASH_SOURCE[0]}")/../..
DOCS_DIR="$ROOT/docs/perfsonar/tools_scripts"
SITE_DIR="$ROOT/site/perfsonar/tools_scripts"

echo "Verifying docs -> site script sync and SHA256 checks"
EXIT_CODE=0

for f in "$DOCS_DIR"/*.sh; do
  base=$(basename "$f")
  sitef="$SITE_DIR/$base"
  if [[ ! -f "$sitef" ]]; then
    echo "MISSING site copy for $base"
    EXIT_CODE=1
    continue
  fi
  # Compare content
  if ! cmp -s "$f" "$sitef"; then
    echo "DIFF: $base differs between docs and site"
    EXIT_CODE=1
  fi
  # Verify sha file entry
  sha_expected=$(sha256sum "$f" | awk '{print $1}')
  shafile="$DOCS_DIR/${base}.sha256"
  if [[ -f "$shafile" ]]; then
    sha_in_file=$(awk '{print $1}' "$shafile")
    if [[ "$sha_expected" != "$sha_in_file" ]]; then
      echo "SHA MISMATCH for $base: $sha_expected != $sha_in_file in $shafile"
      EXIT_CODE=1
    fi
  else
    echo "Missing sha file: $shafile"
    EXIT_CODE=1
  fi
done

exit $EXIT_CODE
