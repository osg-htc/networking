#!/usr/bin/env bash
set -euo pipefail

# Seed host directories from perfSONAR testpoint image.
# Intended to be run on the host as root (or with sudo) BEFORE first compose up.
# Usage: seed_testpoint_host_dirs.sh [--runtime docker|podman] [--base /opt/perfsonar-tp]

RUNTIME=""
BASE_DIR="/opt/perfsonar-tp"

usage() {
    cat <<EOF
Usage: $0 [--runtime docker|podman] [--base DIR]

Prepares host directories for perfSONAR testpoint container bind-mounts by
copying baseline content from the container image. This must be run BEFORE
the first 'podman-compose up' command.

Creates and populates:
  - $BASE_DIR/psconfig        → mounted to /etc/perfsonar/psconfig (perfSONAR config)
  - /var/www/html             → mounted to /var/www/html (Apache webroot)
  - /etc/apache2              → mounted to /etc/apache2 (Apache config for SSL patching)

Note: /etc/letsencrypt does NOT need seeding - certbot creates it automatically.

Examples:
  sudo $0
  sudo $0 --runtime podman --base /opt/perfsonar-tp
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
    
    if [ "$all_exist" = "true" ]; then
        echo
        echo "==> All directories already seeded. Skipping."
        echo "    To re-seed, remove or rename existing directories first."
        exit 0
    fi
}

check_already_seeded

echo "==> Creating host directories: $PSCONFIG_DIR /var/www/html /etc/apache2"
mkdir -p "$PSCONFIG_DIR" /var/www/html /etc/apache2
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

echo "==> Verifying seeded content..."
for dir in "$PSCONFIG_DIR" "/var/www/html" "/etc/apache2"; do
    if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
        file_count=$(find "$dir" -type f | wc -l)
        echo "    ✓ $dir ($file_count files)"
    else
        echo "    ✗ $dir (EMPTY - seeding may have failed!)" >&2
    fi
done
echo

echo "==> SELinux labels will be applied automatically by Podman when containers start"
echo "    (compose file uses :z and :Z flags on bind mounts)"
echo

echo "==> Done! Host directories are ready for compose deployment."
echo "    Next step: cd /opt/perfsonar-tp && podman-compose up -d"
echo

exit 0

