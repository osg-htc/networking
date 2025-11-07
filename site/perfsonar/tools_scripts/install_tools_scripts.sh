#!/usr/bin/env bash
<<<<<<< HEAD
# install_tools_scripts.sh
# Helper to populate /opt/perfsonar-tp/tools_scripts with the tools shipped
# in this repository under docs/perfsonar/tools_scripts using a sparse checkout.
# Intended to be idempotent and safe to rerun.

set -euo pipefail
IFS=$'\n\t'

DEST_DIR="/opt/perfsonar-tp/tools_scripts"
REPO_URL="https://github.com/osg-htc/networking.git"
SPARSE_PATH="docs/perfsonar/tools_scripts"
TMPDIR=""
DRY_RUN=0
SKIP_TESTPOINT=0
TESTPOINT_REPO_URL="https://github.com/perfsonar/testpoint.git"
TESTPOINT_DIR="/opt/perfsonar-tp"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--skip-testpoint]

Options:
  --dry-run         Print actions but don't make changes.
  --skip-testpoint  Don't clone the perfSONAR testpoint repo to /opt/perfsonar-tp.
  -h|--help         Show this help and exit.

What this does:
  - Ensures ${DEST_DIR} exists.
  - (Optional) Clones ${TESTPOINT_REPO_URL} to ${TESTPOINT_DIR} if missing.
  - Performs a temporary shallow, sparse checkout of ${REPO_URL} and copies
    ${SPARSE_PATH} into ${DEST_DIR} using rsync (preserves executable bits).

Run as root (or with sudo) since it writes to /opt.
EOF
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 2
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --skip-testpoint) SKIP_TESTPOINT=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
        esac
    done
}

cleanup() {
    if [ -n "${TMPDIR}" ] && [ -d "${TMPDIR}" ]; then
        [ "$DRY_RUN" -eq 0 ] && rm -rf "${TMPDIR}" || echo "DRY: would remove ${TMPDIR}"
    fi
}
trap cleanup EXIT

main() {
    parse_args "$@"

    require_cmd git
    require_cmd rsync

    echo "Destination tools dir: ${DEST_DIR}"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY RUN enabled — no changes will be made"
    fi

    if [ "$SKIP_TESTPOINT" -eq 0 ]; then
        if [ -d "${TESTPOINT_DIR}" ]; then
            echo "Found existing ${TESTPOINT_DIR}; skipping clone of perfSONAR testpoint."
        else
            echo "perfSONAR testpoint repo not present at ${TESTPOINT_DIR}."
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "DRY: would git clone ${TESTPOINT_REPO_URL} to ${TESTPOINT_DIR}"
            else
                echo "Cloning ${TESTPOINT_REPO_URL} -> ${TESTPOINT_DIR}"
                git clone --depth=1 "${TESTPOINT_REPO_URL}" "${TESTPOINT_DIR}"
            fi
        fi
    else
        echo "Skipping testpoint clone by request (--skip-testpoint)."
    fi

    # Ensure destination exists with correct permissions
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY: would mkdir -p '${DEST_DIR}' and set ownership to root"
    else
        mkdir -p "${DEST_DIR}"
        chmod 0755 "${DEST_DIR}"
    fi

    # Create a temporary sparse checkout of just the tools directory
    TMPDIR=$(mktemp -d)
    echo "Using temporary checkout: ${TMPDIR}"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY: would git clone --depth=1 --filter=blob:none --sparse ${REPO_URL} ${TMPDIR}/repo"
        echo "DRY: would git -C ${TMPDIR}/repo sparse-checkout set ${SPARSE_PATH}"
        echo "DRY: would rsync -a ${TMPDIR}/repo/${SPARSE_PATH}/ ${DEST_DIR}/"
    else
        git clone --depth=1 --filter=blob:none --sparse "${REPO_URL}" "${TMPDIR}/repo"
        git -C "${TMPDIR}/repo" sparse-checkout set "${SPARSE_PATH}"

        SRC_DIR="${TMPDIR}/repo/${SPARSE_PATH}"
        if [ ! -d "${SRC_DIR}" ]; then
            echo "ERROR: expected sparse path not found: ${SRC_DIR}" >&2
            exit 3
        fi

        echo "Copying tools from ${SRC_DIR} -> ${DEST_DIR}"
        rsync -a --delete "${SRC_DIR}/" "${DEST_DIR}/"

        echo "Setting executable bit for scripts in ${DEST_DIR}"
        find "${DEST_DIR}" -type f -name '*.sh' -exec chmod 0755 {} + || true
    fi

    echo "Done. Tools installed to: ${DEST_DIR}"
    echo "Tip: run 'ls -1 ${DEST_DIR}' to review installed scripts."
}

main "$@"
=======
set -euo pipefail

# install_tools_scripts.sh (reverted workflow)
# Purpose: Ensure the perfSONAR testpoint repository is cloned and the tools_scripts
#          directory is present under /opt/perfsonar-tp/tools_scripts.

DEST_ROOT=${1:-/opt/perfsonar-tp}
TP_REPO_URL="https://github.com/perfsonar/testpoint.git"
TOOLS_SRC="https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts"

echo "[INFO] Target root: $DEST_ROOT"
mkdir -p "$DEST_ROOT"

if [ ! -d "$DEST_ROOT/.git" ] && [ ! -d "$DEST_ROOT/psconfig" ]; then
  echo "[INFO] Cloning perfSONAR testpoint repository..."
  git clone "$TP_REPO_URL" "$DEST_ROOT"
else
  echo "[INFO] perfSONAR testpoint appears already present; skipping clone."
fi

TOOLS_DIR="$DEST_ROOT/tools_scripts"
mkdir -p "$TOOLS_DIR"

scripts=(
  check-deps.sh
  check-perfsonar-dns.sh
  perfSONAR-pbr-nm.sh
  perfSONAR-install-nftables.sh
  perfSONAR-update-lsregistration.sh
  perfSONAR-extract-lsregistration.sh
  docker-compose.yml
)

echo "[INFO] Fetching helper scripts into $TOOLS_DIR"
for s in "${scripts[@]}"; do
  echo "  - $s"
  curl -fsSL "$TOOLS_SRC/$s" -o "$TOOLS_DIR/$s"
done

chmod 0755 "$TOOLS_DIR"/*.sh || true

echo "[INFO] Bootstrap complete. Testpoint root: $DEST_ROOT; scripts in $TOOLS_DIR"
>>>>>>> e109ae4 (Revert bootstrap workflow: clone perfSONAR testpoint repo and install helper scripts; update quick-deploy and install-testpoint docs; unify script invocation paths; adjust markdownlint line length)
