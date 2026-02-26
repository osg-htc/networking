#!/usr/bin/env bash
set -euo pipefail

# seed_testpoint_host_dirs.sh
# Seed host directories from perfSONAR testpoint image.
# Intended to be run on the host as root (or with sudo) BEFORE first compose up.
#
# Version: 1.0.1 - 2026-02-26
#   - Create $BASE_DIR/conf/ and install node_exporter.defaults (adds
#     --no-collector.cpufreq workaround for procfs v0.10.0 cpufreq panic)
#   - Add /run/dbus volume note in output
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# Usage: seed_testpoint_host_dirs.sh [--runtime docker|podman] [--base /opt/perfsonar-tp] [--version|--help]

VERSION="1.0.1"
PROG_NAME="$(basename "$0")"
RUNTIME=""
BASE_DIR="/opt/perfsonar-tp"

# Check for --version flag first
if [ "${1:-}" = "--version" ]; then
    echo "$PROG_NAME version $VERSION"
    exit 0
fi

usage() {
    cat <<EOF
Usage: $0 [--runtime docker|podman] [--base DIR] [--version|--help]

Prepares host directories for perfSONAR testpoint container bind-mounts by
copying baseline content from the container image. This must be run BEFORE
the first 'podman-compose up' command.

Creates and populates:
  - $BASE_DIR/psconfig        → mounted to /etc/perfsonar/psconfig (perfSONAR config)
  - $BASE_DIR/conf/           → host-managed config overrides
    node_exporter.defaults    → /etc/default/node_exporter (adds --no-collector.cpufreq
                                workaround for procfs v0.10.0 cpufreq panic)
  - /var/www/html             → mounted to /var/www/html (Apache webroot)
  - /etc/apache2              → mounted to /etc/apache2 (Apache config for SSL patching)

Note: /etc/letsencrypt does NOT need seeding - certbot creates it automatically.
Note: /run/dbus is mounted read-only for node_exporter --collector.systemd;
      on EL9 with SELinux enforcing you may need to enable the
      container_use_dbusd boolean: setsebool -P container_use_dbusd 1

Options:
  --runtime RUNTIME   Specify container runtime (docker or podman)
  --base DIR          Base directory for perfSONAR testpoint (default: /opt/perfsonar-tp)
  --version           Show version information
  --help, -h          Show this help message

Examples:
  sudo $0
  sudo $0 --runtime podman --base /opt/perfsonar-tp

Exit codes:
  0 - Success (directories seeded or already present)
  1 - Runtime not found
  2 - Invalid arguments
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runtime)
            shift; RUNTIME="$1"; shift;;
        --base)
            shift; BASE_DIR="$1"; shift;;
        -h|--help)
            usage; exit 0;;
        *)
            echo "Unknown arg: $1" >&2; usage; exit 2;;
    esac
done

if [ -z "$RUNTIME" ]; then
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        echo "ERROR: Neither podman nor docker found in PATH." >&2; exit 1
    fi
fi

echo "==> Using container runtime: $RUNTIME"
echo

PSCONFIG_DIR="$BASE_DIR/psconfig"

# Check if directories already have content
check_already_seeded() {
    local all_exist=true
    
    if [ -d "$PSCONFIG_DIR" ] && [ "$(ls -A "$PSCONFIG_DIR" 2>/dev/null)" ]; then
        echo "    $PSCONFIG_DIR already has content"
    else
        all_exist=false
    fi
    
    if [ -d "/var/www/html" ] && [ "$(ls -A /var/www/html 2>/dev/null)" ]; then
        echo "    /var/www/html already has content"
    else
        all_exist=false
    fi
    
    if [ -d "/etc/apache2" ] && [ "$(ls -A /etc/apache2 2>/dev/null)" ]; then
        echo "    /etc/apache2 already has content"
    else
        all_exist=false
    fi
    
    if [ -f "$BASE_DIR/conf/node_exporter.defaults" ]; then
        echo "    $BASE_DIR/conf/node_exporter.defaults already present"
    else
        all_exist=false
    fi

    if [ "$all_exist" = "true" ]; then
        echo
        echo "==> All directories already seeded. Skipping."
        echo "    To re-seed, remove or rename existing directories first."
        exit 0
    fi
}

check_already_seeded

echo "==> Creating host directories: $PSCONFIG_DIR $BASE_DIR/conf /var/www/html /etc/apache2"
mkdir -p "$PSCONFIG_DIR" "$BASE_DIR/conf" /var/www/html /etc/apache2
echo

cleanup_container() {
    local name="$1"
    if $RUNTIME ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "${name}"; then
        echo "    Removing temporary container: $name"
        $RUNTIME rm -f "$name" >/dev/null 2>&1 || true
    fi
}

copy_from_image() {
    local image="$1"
    local src_path="$2"
    local dst_path="$3"
    local description="$4"
    local cname
    cname="perfsonar-seed-$$-$(date +%s)"

    echo "==> Seeding: $description"
    echo "    Source: $image:$src_path"
    echo "    Destination: $dst_path"
    
    # Create container without starting it
    if ! $RUNTIME create --name "$cname" "$image" >/dev/null 2>&1; then
        echo "    ERROR: Failed to create temporary container" >&2
        return 1
    fi
    
    # Copy content from container to host
    if $RUNTIME cp "$cname":"$src_path"/. "$dst_path"/ 2>/dev/null; then
        echo "    ✓ Copied successfully"
    else
        echo "    WARNING: Failed to copy (path may not exist in image)"
    fi
    
    cleanup_container "$cname"
    echo
}

# Use the production perfsonar testpoint image
TP_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production"

echo "==> Pulling latest perfSONAR testpoint image: $TP_IMAGE"
$RUNTIME pull "$TP_IMAGE" || echo "WARNING: Failed to pull latest image, using cached version"
echo

copy_from_image "$TP_IMAGE" "/etc/perfsonar/psconfig" "$PSCONFIG_DIR" "perfSONAR configuration"
copy_from_image "$TP_IMAGE" "/var/www/html" "/var/www/html" "Apache webroot"
copy_from_image "$TP_IMAGE" "/etc/apache2" "/etc/apache2" "Apache configuration"

# Install node_exporter.defaults from the tools_scripts directory
NE_DEFAULTS_SRC="$(dirname "$0")/node_exporter.defaults"
NE_DEFAULTS_DST="$BASE_DIR/conf/node_exporter.defaults"
echo "==> Installing node_exporter options override"
echo "    Source: $NE_DEFAULTS_SRC"
echo "    Destination: $NE_DEFAULTS_DST"
if [ -f "$NE_DEFAULTS_SRC" ]; then
    cp -p "$NE_DEFAULTS_SRC" "$NE_DEFAULTS_DST"
    echo "    ✓ Installed node_exporter.defaults"
else
    echo "    WARNING: $NE_DEFAULTS_SRC not found; $NE_DEFAULTS_DST will not be created."
    echo "    node_exporter may panic on first scrape (procfs v0.10.0 cpufreq bug)."
fi
echo

echo "==> Verifying seeded content..."
for dir in "$PSCONFIG_DIR" "/var/www/html" "/etc/apache2"; do
    if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
        file_count=$(find "$dir" -type f | wc -l)
        echo "    ✓ $dir ($file_count files)"
    else
        echo "    ✗ $dir (EMPTY - seeding may have failed!)" >&2
    fi
done
if [ -f "$NE_DEFAULTS_DST" ]; then
    echo "    ✓ $NE_DEFAULTS_DST"
else
    echo "    ✗ $NE_DEFAULTS_DST (MISSING - node_exporter may crash on scrape!)" >&2
fi
echo

echo "==> SELinux labels will be applied automatically by Podman when containers start"
echo "    (compose file uses :z and :Z flags on bind mounts)"
echo
echo "==> Note: /run/dbus is bind-mounted read-only for node_exporter --collector.systemd."
echo "    On EL9 hosts with SELinux enforcing, enable access with:"
echo "      setsebool -P container_use_dbusd 1"
echo

echo "==> Done! Host directories are ready for compose deployment."
echo "    Next step: cd /opt/perfsonar-tp && podman-compose up -d"
echo

exit 0

