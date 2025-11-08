#!/usr/bin/env bash
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
    # helpers and installers
    check-deps.sh
    check-perfsonar-dns.sh
    perfSONAR-pbr-nm.sh
    perfSONAR-install-nftables.sh
    perfSONAR-update-lsregistration.sh
    perfSONAR-extract-lsregistration.sh
    perfSONAR-auto-enroll-psconfig.sh
    seed_testpoint_host_dirs.sh

    # compose examples / templates
    docker-compose.yml
    docker-compose.testpoint.yml
    docker-compose.testpoint-le.yml

    # docs / READMEs (optional, copied so users can view usage offline)
    README.md
    README-lsregistration.md
)

echo "[INFO] Fetching helper scripts into $TOOLS_DIR"
for s in "${scripts[@]}"; do
  echo "  - $s"
  curl -fsSL "$TOOLS_SRC/$s" -o "$TOOLS_DIR/$s"
done

chmod 0755 "$TOOLS_DIR"/*.sh || true

echo "[INFO] Bootstrap complete. Testpoint root: $DEST_ROOT; scripts in $TOOLS_DIR"
