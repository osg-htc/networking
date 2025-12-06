
#!/usr/bin/env bash
set -euo pipefail

# Usage: verify-site-scripts.sh [file1 file2 ...]
# If no args are provided, it checks all scripts under docs/perfsonar/tools_scripts

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
DOCS_DIR="$ROOT/docs/perfsonar/tools_scripts"
SITE_DIR="$ROOT/site/perfsonar/tools_scripts"

echo "Verifying docs -> site script sync and SHA256 checks"
EXIT_CODE=0

files_to_check=()
if [[ $# -gt 0 ]]; then
  # Use given list of files; they can be absolute or relative paths
  for arg in "$@"; do
    # normalize to docs dir if necessary
    if [[ "$arg" =~ ^docs/perfsonar/tools_scripts/ || "$arg" =~ ^site/perfsonar/tools_scripts/ ]]; then
      files_to_check+=("$arg")
    elif [[ "$arg" =~ \.sh$ ]]; then
      files_to_check+=("$DOCS_DIR/$arg")
    else
      files_to_check+=("$DOCS_DIR/$arg")
    fi
  done
else
  # Default: all script files in docs dir
  while IFS= read -r -d '' f; do files_to_check+=("$f"); done < <(find "$DOCS_DIR" -maxdepth 1 -type f -name "*.sh" -print0)
fi

for f in "${files_to_check[@]}"; do
  # Normalize base and filename
  if [[ "$f" == "$DOCS_DIR"/* ]]; then
    base=$(basename "$f")
    docf="$f"
  elif [[ "$f" == "$SITE_DIR"/* ]]; then
    base=$(basename "$f")
    docf="$DOCS_DIR/$base"
  else
    # some other path: resolve basis as a filename
    base=$(basename "$f")
    docf="$DOCS_DIR/$base"
  fi

  sitef="$SITE_DIR/$base"
  if [[ ! -f "$sitef" ]]; then
    echo "MISSING site copy for $base"
    EXIT_CODE=1
    continue
  fi
  if [[ ! -f "$docf" ]]; then
    echo "MISSING docs copy for $base"
    EXIT_CODE=1
    continue
  fi
  # Compare content
  if ! cmp -s "$docf" "$sitef"; then
    echo "DIFF: $base differs between docs and site"
    EXIT_CODE=1
  fi
  # Verify sha file entry
  sha_expected=$(sha256sum "$docf" | awk '{print $1}')
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

if [[ $EXIT_CODE -ne 0 ]]; then
  echo "One or more verification checks failed. See above."
fi
exit $EXIT_CODE
