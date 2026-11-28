#!/usr/bin/env bash
# verify-site-scripts.sh: check the helper scripts in docs/perfsonar/tools_scripts.
#
# Always checks every script (file arguments are accepted for compatibility
# and ignored). It only reads; to fix checksum problems run
#   bash .github/scripts/update-script-checksums.sh
# and commit the result.
#
# Checks:
#   - every *.sh has <script>.sha256 holding "<sha256>  <script>", and every
#     per-file .sha256 passes 'sha256sum -c' (right hash, right file name);
#   - scripts.sha256 lists every *.sh, lists no missing file, and passes
#     'sha256sum -c';
#   - the first '# Version: X.Y.Z' header line matches a VERSION= or
#     SCRIPT_VERSION= variable when a script has both
#     (update-perfsonar-deployment.sh relaunches itself when they differ, so a
#     mismatch there loops forever on every host).

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
DIR="$ROOT/docs/perfsonar/tools_scripts"
LIST="scripts.sha256"
FIX="bash .github/scripts/update-script-checksums.sh"

cd "$DIR" || { echo "ERROR: $DIR not found"; exit 1; }

errors=0
sha_errors=0
fail() { echo "FAIL: $*"; errors=$((errors + 1)); }
sha_fail() { fail "$@"; sha_errors=$((sha_errors + 1)); }

mapfile -t scripts < <(find . -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | LC_ALL=C sort)
echo "Checking ${#scripts[@]} scripts in docs/perfsonar/tools_scripts"

# Per-file checksums
for f in "${scripts[@]}"; do
    if [[ ! -f "$f.sha256" ]]; then
        sha_fail "$f has no $f.sha256"
    elif ! grep -qE "^[0-9a-f]{64}  ${f//./\\.}\$" "$f.sha256"; then
        sha_fail "$f.sha256 is not in the form '<sha256>  $f' (got: $(head -c 120 "$f.sha256"))"
    elif ! sha256sum -c --status "$f.sha256" 2>/dev/null; then
        sha_fail "$f.sha256 does not match $f"
    fi
done
for c in *.sha256; do
    [[ "$c" == "$LIST" ]] && continue
    target=${c%.sha256}
    if [[ ! -f "$target" ]]; then
        sha_fail "$c has no $target"
    elif [[ "$target" != *.sh ]] && ! sha256sum -c --status "$c" 2>/dev/null; then
        sha_fail "$c does not match $target"
    fi
done

# scripts.sha256
if [[ ! -f "$LIST" ]]; then
    sha_fail "$LIST is missing"
else
    while read -r _ name; do
        [[ -n "${name:-}" && ! -f "$name" ]] && sha_fail "$LIST lists $name, which does not exist"
    done < "$LIST"
    for f in "${scripts[@]}"; do
        grep -qE "^[0-9a-f]{64}  ${f//./\\.}\$" "$LIST" || sha_fail "$LIST has no entry for $f"
    done
    while IFS= read -r line; do
        sha_fail "$LIST: $line"
    done < <(sha256sum -c "$LIST" 2>/dev/null | grep -v ': OK$')
fi

# Version header vs VERSION variable
for f in "${scripts[@]}"; do
    hdr=$(grep -m1 -E '^# Version: [0-9]' "$f" | awk '{print $3}' || true)
    var=$(grep -m1 -E '^(VERSION|SCRIPT_VERSION)=' "$f" | sed -E 's/^[A-Z_]+="?([^" ]*)"?.*/\1/' || true)
    if [[ -n "$hdr" && -n "$var" && "$hdr" != "$var" ]]; then
        fail "$f: header says version $hdr, VERSION variable says $var"
    fi
done

if [[ $errors -eq 0 ]]; then
    echo "OK: checksums and version headers are consistent"
    exit 0
fi
echo
echo "$errors problem(s) found."
if [[ $sha_errors -gt 0 ]]; then
    echo "Fix the checksum files with:"
    echo "  $FIX"
    echo "and commit the changes."
fi
exit 1
