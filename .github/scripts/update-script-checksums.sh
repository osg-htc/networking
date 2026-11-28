#!/usr/bin/env bash
# update-script-checksums.sh: regenerate the checksum files for the helper
# scripts in docs/perfsonar/tools_scripts. Run it after changing a script,
# then commit the result. CI (verify-site-scripts.sh) only checks; it never
# commits.
#
#   bash .github/scripts/update-script-checksums.sh          # all scripts
#   bash .github/scripts/update-script-checksums.sh a.sh ... # only these
#
# Writes, for each script, "<sha256>  <file>" to <file>.sha256 (the format
# 'sha256sum -c' reads, run inside the directory), and keeps scripts.sha256
# in step: lines updated in place, new scripts appended, lines for files that
# no longer exist removed. Other files listed there (e.g. node_exporter.defaults)
# are kept and updated. Running it twice changes nothing.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
DIR="$ROOT/docs/perfsonar/tools_scripts"
LIST="scripts.sha256"

cd "$DIR"

files=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        base=$(basename "$arg")
        if [[ ! -f "$base" ]]; then
            echo "ERROR: $DIR/$base does not exist" >&2
            exit 1
        fi
        files+=("$base")
    done
else
    mapfile -t files < <(find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | LC_ALL=C sort)
fi

changed=0
write_if_changed() {   # $1 = file, $2 = content
    if [[ ! -f "$1" ]] || [[ "$(cat "$1")" != "$2" ]]; then
        printf '%s\n' "$2" > "$1"
        echo "updated $1"
        changed=1
    fi
}

for f in "${files[@]}"; do
    write_if_changed "$f.sha256" "$(sha256sum "$f")"
done

# Other per-file checksums (e.g. node_exporter.defaults.sha256): refresh when
# the file exists; report the ones whose file is gone.
if [[ $# -eq 0 ]]; then
    while IFS= read -r c; do
        target=${c%.sha256}
        [[ "$c" == "$LIST" || "$target" == *.sh ]] && continue
        if [[ -f "$target" ]]; then
            write_if_changed "$c" "$(sha256sum "$target")"
        else
            echo "NOTE: $c has no $target; delete it if the file was removed"
        fi
    done < <(find . -maxdepth 1 -type f -name '*.sha256' -printf '%f\n' | LC_ALL=C sort)
    for c in *.sh.sha256; do
        [[ -f "${c%.sha256}" ]] || echo "NOTE: $c has no ${c%.sha256}; delete it if the script was removed"
    done
fi

# scripts.sha256: refresh every entry whose file exists, drop the others,
# append scripts that are missing.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
if [[ -f "$LIST" ]]; then
    while read -r _ name; do
        [[ -n "${name:-}" ]] || continue
        if [[ -f "$name" ]]; then
            sha256sum "$name" >> "$tmp"
        else
            echo "removed $name from $LIST (file no longer exists)"
        fi
    done < "$LIST"
fi
while IFS= read -r f; do
    grep -qE "^[0-9a-f]{64}  ${f//./\\.}\$" "$tmp" || sha256sum "$f" >> "$tmp"
done < <(find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | LC_ALL=C sort)
write_if_changed "$LIST" "$(cat "$tmp")"

if [[ $changed -eq 0 ]]; then
    echo "All checksum files are up to date."
fi
