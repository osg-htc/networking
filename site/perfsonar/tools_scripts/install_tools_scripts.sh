#!/usr/bin/env bash
set -euo pipefail

# install_tools_scripts.sh (reverted workflow)
# Purpose: Ensure the perfSONAR testpoint repository is cloned and the tools_scripts
#          directory is present under /opt/perfsonar-tp/tools_scripts.
#
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

VERSION="1.0.0"
PROG_NAME="$(basename "$0")"

# Check for --version or --help flags
if [ "${1:-}" = "--version" ]; then
    echo "$PROG_NAME version $VERSION"
    exit 0
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<EOF
Usage: $PROG_NAME [DEST_ROOT] [--version|--help]

Downloads perfSONAR helper scripts and tools to the specified directory.
Optionally clones the perfSONAR testpoint repository if not already present.

Arguments:
  DEST_ROOT    Destination directory (default: /opt/perfsonar-tp)

Options:
  --version    Show version information
  --help, -h   Show this help message

Downloads:
  - perfSONAR helper scripts (check-deps.sh, perfSONAR-pbr-nm.sh, etc.)
  - Docker compose templates
  - Documentation files (README.md, etc.)

Exit codes:
  0 - Success
  1 - Download or installation error
EOF
    exit 0
fi

DEST_ROOT=${1:-/opt/perfsonar-tp}
TP_REPO_URL="https://github.com/perfsonar/testpoint.git"
TOOLS_SRC="https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts"

echo "[INFO] Target root: $DEST_ROOT"
mkdir -p "$DEST_ROOT"

if [ ! -d "$DEST_ROOT/.git" ] && [ ! -d "$DEST_ROOT/psconfig" ]; then
  echo "[INFO] Cloning perfSONAR testpoint repository (non-interactive shallow clone)..."
  # Prevent git from prompting interactively for credentials. If the clone
  # fails (for example if the repo is private or network-restricted), fall
  # back to creating the destination directory and continue fetching helper
  # scripts from the docs tree (these are fetched below via raw.githubusercontent).
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$TP_REPO_URL" "$DEST_ROOT" || {
    echo "[WARN] git clone failed or would prompt for credentials; creating $DEST_ROOT and continuing with helper downloads."
    mkdir -p "$DEST_ROOT"
  }
else
  echo "[INFO] perfSONAR testpoint appears already present; skipping clone."
fi

TOOLS_DIR="$DEST_ROOT/tools_scripts"
mkdir -p "$TOOLS_DIR"

scripts=(
    # helpers and installers
    check-deps.sh
    check-perfsonar-dns.sh
    perfSONAR-pbr-nm.sh
    perfSONAR-install-nftables.sh
    perfSONAR-update-lsregistration.sh
    perfSONAR-auto-enroll-psconfig.sh
    seed_testpoint_host_dirs.sh
    perfSONAR-orchestrator.sh
    
    # SSL certificate helpers
    patch_apache_ssl_for_letsencrypt.sh
    testpoint-entrypoint-wrapper.sh
    certbot-deploy-hook.sh

    # compose examples / templates
    docker-compose.testpoint.yml
    docker-compose.testpoint-le.yml
    docker-compose.testpoint-le-auto.yml

    # docs / READMEs (optional, copied so users can view usage offline)
    README.md
    README-lsregistration.md
)

echo "[INFO] Fetching helper scripts into $TOOLS_DIR"
for s in "${scripts[@]}"; do
  echo "  - $s"
  curl -fsSL "$TOOLS_SRC/$s" -o "$TOOLS_DIR/$s"
done

# Note: The script `perfSONAR-extract-lsregistration.sh` was deprecated and is
# intentionally not included in the fetched helpers. See
# docs/perfsonar/tools_scripts/DEPRECATION.md for details and migration
# instructions.

chmod 0755 "$TOOLS_DIR"/*.sh || true

echo "[INFO] Bootstrap complete. Testpoint root: $DEST_ROOT; scripts in $TOOLS_DIR"
