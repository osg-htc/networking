#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
DOCS_DIR="$ROOT/docs/perfsonar/tools_scripts"
SITE_DIR="$ROOT/site/perfsonar/tools_scripts"
SCRIPTS_SHA="$DOCS_DIR/scripts.sha256"

if [[ $# -eq 0 ]]; then
  echo "No files specified." >&2
  exit 0
fi

changed=()
for arg in "$@"; do
  # Normalize to base file name
  base=$(basename "$arg")
  if [[ "$base" == *.sh ]]; then
    changed+=("$base")
  fi
done

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "No changed script files to update." >&2
  exit 0
fi

modified=0
for base in "${changed[@]}"; do
  docf="$DOCS_DIR/$base"
  sitef="$SITE_DIR/$base"
  if [[ ! -f "$docf" ]]; then
    echo "Docs file not found: $docf" >&2
    continue
  fi
  sha=$(sha256sum "$docf" | awk '{print $1}')
  echo "$sha  $docf" > "$DOCS_DIR/$base.sha256"
  if [[ -d "$SITE_DIR" ]]; then
    echo "$sha  $docf" > "$sitef.sha256"
  fi
  modified=1
  echo "Updated sha for $base -> $sha"
  # Replace line in scripts.sha256
  if [[ -f "$SCRIPTS_SHA" ]]; then
    if grep -q "\s$base$" "$SCRIPTS_SHA"; then
      # replace line for base
      sed -i "s|^[0-9a-f]*\s\+$base\$|$sha  $base|" "$SCRIPTS_SHA" || true
    else
      # add new line
      echo "$sha  $base" >> "$SCRIPTS_SHA"
    fi
  else
    echo "$sha  $base" > "$SCRIPTS_SHA"
  fi
done

if [[ $modified -eq 1 ]]; then
  git add "$DOCS_DIR"/*.sha256 "$SITE_DIR"/*.sha256 "$SCRIPTS_SHA" || true
  git commit -m "chore(scripts): update script sha256 for changed docs scripts" || true
  # Push back to branch
  git push origin HEAD
fi
