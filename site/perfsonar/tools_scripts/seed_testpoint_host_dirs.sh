#!/usr/bin/env bash
"set -euo pipefail"

# Seed host directories from a temporary perfSONAR testpoint and certbot images.
# Intended to be run on the host as root (or with sudo).
# Usage: seed_testpoint_host_dirs.sh [--runtime docker|podman] [--base /opt/perfsonar-tp]

RUNTIME=""
BASE_DIR="/opt/perfsonar-tp"

usage() {
    cat <<EOF
Usage: $0 [--runtime docker|podman] [--base DIR]

Creates directories and copies baseline content out of temporary containers:
  - /opt/perfsonar-tp/psconfig
  - /var/www/html
  - /etc/apache2
  - /etc/letsencrypt (seeded from certbot)

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
        echo "Neither podman nor docker found in PATH." >&2; exit 1
    fi
fi

echo "Using container runtime: $RUNTIME"

PSCONFIG_DIR="$BASE_DIR/psconfig"

echo "Creating host directories: $PSCONFIG_DIR /var/www/html /etc/apache2 /etc/letsencrypt"
mkdir -p "$PSCONFIG_DIR" /var/www/html /etc/apache2 /etc/letsencrypt

cleanup_container() {
    local name="$1"
    if $RUNTIME ps --format '{{.Names}}' 2>/dev/null | grep -qw "${name}"; then
        echo "Removing temporary container: $name"
        $RUNTIME rm -f "$name" >/dev/null 2>&1 || true
    fi
}

create_and_cp() {
    local image="$1"; shift
    local src_path="$1"; shift
    local dst_path="$1"; shift
    local cname="$2"

    # Create container (no start) if possible
    echo "Creating temp container from image: $image"
    $RUNTIME create --name "$cname" "$image" >/dev/null 2>&1 || true
    # Copy path; ignore failures where the path might not exist in the image
    echo "Copying $src_path -> $dst_path"
    $RUNTIME cp "$cname":"$src_path" "$dst_path" 2>/dev/null || true
    cleanup_container "$cname"
}

TMP_NAME_TP="perfsonar-seed-$$"
TMP_NAME_CB="certbot-seed-$$"

# Use the official perfsonar testpoint image (registry tag controlled by docs/compose examples)
TP_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:5.2.3-systemd"

create_and_cp "$TP_IMAGE" "/etc/perfsonar/psconfig" "$PSCONFIG_DIR" "$TMP_NAME_TP"
create_and_cp "$TP_IMAGE" "/var/www/html" "/var/www/html" "$TMP_NAME_TP"
create_and_cp "$TP_IMAGE" "/etc/apache2" "/etc/apache2" "$TMP_NAME_TP"

# Seed letsencrypt from certbot image; be tolerant if there is nothing to copy
CB_IMAGE="certbot/certbot:latest"
create_and_cp "$CB_IMAGE" "/etc/letsencrypt" "/etc/letsencrypt" "$TMP_NAME_CB"

echo "Apply SELinux labels (if running on enforcing SELinux host) by ensuring future bind-mounts use :z/:Z in compose."

echo "Done. Host directories seeded."

exit 0
