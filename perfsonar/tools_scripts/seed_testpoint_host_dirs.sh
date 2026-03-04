#!/usr/bin/env bash
set -euo pipefail

# seed_testpoint_host_dirs.sh
# Seed host directories from perfSONAR testpoint image.
# Intended to be run on the host as root (or with sudo) BEFORE first compose up.
#
# Version: 2.0.0 - 2026-03-04
#   - Option A (default): seed only psconfig — /var/www/html and /etc/apache2 are not
#     mounted for plain testpoint, so seeding them is unnecessary. The container's
#     own webroot and Apache config are used directly.
#   - Add --with-le flag for Option B (Let's Encrypt): seeds /var/www/html (for
#     HTTP-01 challenges) and /etc/apache2/sites-available/default-ssl.conf only
#     (the entrypoint wrapper only patches that single file).
#   - Remove node_exporter.defaults copy: the container ships its own complete
#     node_exporter options. Override is only needed if your host has offline/
#     unpopulated CPU sockets (see docs for manual workaround).
# Version: 1.0.1 - 2026-02-26
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# Usage: seed_testpoint_host_dirs.sh [--runtime docker|podman] [--base /opt/perfsonar-tp] [--with-le] [--version|--help]

VERSION="2.0.0"
PROG_NAME="$(basename "$0")"
RUNTIME=""
BASE_DIR="/opt/perfsonar-tp"
WITH_LE=false

# Check for --version flag first
if [ "${1:-}" = "--version" ]; then
    echo "$PROG_NAME version $VERSION"
    exit 0
fi

usage() {
    cat <<EOF
Usage: $0 [--runtime docker|podman] [--base DIR] [--with-le] [--version|--help]

Prepares host directories for perfSONAR testpoint container bind-mounts by
copying baseline content from the container image. This must be run BEFORE
the first 'podman-compose up' command.

Without --with-le (Option A, testpoint-only):
  Creates and populates:
  - $BASE_DIR/psconfig  → mounted to /etc/perfsonar/psconfig (perfSONAR config)

  /var/www/html and /etc/apache2 are NOT mounted for Option A — the container
  uses its own internal Apache webroot and config. They do not need seeding.

With --with-le (Option B, Let's Encrypt):
  Additionally creates and populates:
  - /var/www/html       → mounted to /var/www/html (for certbot HTTP-01 challenges)
  - /etc/apache2/sites-available/default-ssl.conf  (only this file — the
    entrypoint wrapper patches it to use LE certs; rest of Apache config stays
    inside the container)

Note: node_exporter options are NOT seeded. The container ships its own complete
/etc/default/node_exporter with all needed collectors. If your host has offline/
unpopulated CPU sockets and node_exporter panics (procfs v0.10.0 cpufreq bug),
see the documentation for how to create an override file manually.

Note: /etc/letsencrypt does NOT need seeding - certbot creates it automatically.
Note: /run/dbus is mounted read-only for node_exporter --collector.systemd;
      on EL9 with SELinux enforcing you may need to enable the
      container_use_dbusd boolean: setsebool -P container_use_dbusd 1

Options:
  --runtime RUNTIME   Specify container runtime (docker or podman)
  --base DIR          Base directory for perfSONAR testpoint (default: /opt/perfsonar-tp)
  --with-le           Also seed for Let's Encrypt (Option B): adds /var/www/html
                      and /etc/apache2/sites-available/default-ssl.conf
  --version           Show version information
  --help, -h          Show this help message

Examples:
  sudo $0                         # Option A: seed psconfig only
  sudo $0 --with-le               # Option B: seed psconfig + webroot + SSL conf
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
        --with-le)
            WITH_LE=true; shift;;
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
[ "$WITH_LE" = true ] && echo "==> Mode: Option B (Let's Encrypt) — seeding webroot and Apache SSL config"
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

    if [ "$WITH_LE" = true ]; then
        if [ -d "/var/www/html" ] && [ "$(ls -A /var/www/html 2>/dev/null)" ]; then
            echo "    /var/www/html already has content"
        else
            all_exist=false
        fi

        if [ -f "/etc/apache2/sites-available/default-ssl.conf" ]; then
            echo "    /etc/apache2/sites-available/default-ssl.conf already present"
        else
            all_exist=false
        fi
    fi

    if [ "$all_exist" = "true" ]; then
        echo
        echo "==> All required directories already seeded. Skipping."
        echo "    To re-seed, remove or rename existing directories first."
        exit 0
    fi
}

check_already_seeded

if [ "$WITH_LE" = true ]; then
    echo "==> Creating host directories: $PSCONFIG_DIR /var/www/html /etc/apache2/sites-available"
    mkdir -p "$PSCONFIG_DIR" /var/www/html /etc/apache2/sites-available
else
    echo "==> Creating host directory: $PSCONFIG_DIR"
    mkdir -p "$PSCONFIG_DIR"
fi
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

copy_file_from_image() {
    local image="$1"
    local src_file="$2"
    local dst_file="$3"
    local description="$4"
    local cname
    cname="perfsonar-seed-$$-$(date +%s)"

    echo "==> Seeding: $description"
    echo "    Source: $image:$src_file"
    echo "    Destination: $dst_file"

    # Create container without starting it
    if ! $RUNTIME create --name "$cname" "$image" >/dev/null 2>&1; then
        echo "    ERROR: Failed to create temporary container" >&2
        return 1
    fi

    # Copy single file from container to host
    if $RUNTIME cp "$cname":"$src_file" "$dst_file" 2>/dev/null; then
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

if [ "$WITH_LE" = true ]; then
    copy_from_image "$TP_IMAGE" "/var/www/html" "/var/www/html" "Apache webroot (for LE HTTP-01 challenges)"
    copy_file_from_image "$TP_IMAGE" "/etc/apache2/sites-available/default-ssl.conf" \
        "/etc/apache2/sites-available/default-ssl.conf" \
        "Apache SSL config (patched by entrypoint wrapper with LE certs)"
fi

echo "==> Verifying seeded content..."
if [ -d "$PSCONFIG_DIR" ] && [ "$(ls -A "$PSCONFIG_DIR" 2>/dev/null)" ]; then
    file_count=$(find "$PSCONFIG_DIR" -type f | wc -l)
    echo "    ✓ $PSCONFIG_DIR ($file_count files)"
else
    echo "    ✗ $PSCONFIG_DIR (EMPTY - seeding may have failed!)" >&2
fi

if [ "$WITH_LE" = true ]; then
    for path in "/var/www/html" "/etc/apache2/sites-available/default-ssl.conf"; do
        if [ -d "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]; then
            file_count=$(find "$path" -type f | wc -l)
            echo "    ✓ $path ($file_count files)"
        elif [ -f "$path" ]; then
            echo "    ✓ $path"
        else
            echo "    ✗ $path (MISSING - seeding may have failed!)" >&2
        fi
    done
fi
echo

echo "==> SELinux labels will be applied automatically by Podman when containers start"
echo "    (compose file uses :z and :Z flags on bind mounts)"
echo
echo "==> Note: /run/dbus is bind-mounted read-only for node_exporter --collector.systemd."
echo "    On EL9 hosts with SELinux enforcing, enable access with:"
echo "      setsebool -P container_use_dbusd 1"
echo
echo "==> Note: node_exporter options use the container's own defaults."
echo "    If your host has offline/unpopulated CPU sockets and node_exporter panics"
echo "    (procfs v0.10.0 cpufreq 'slice bounds out of range' bug), create an override:"
echo "      mkdir -p ${BASE_DIR}/conf"
echo "      echo 'NODE_EXPORTER_OPTS=\"--no-collector.cpufreq\"' > ${BASE_DIR}/conf/node_exporter.defaults"
echo "    Then uncomment the node_exporter.defaults volume in docker-compose.yml and restart."
echo

echo "==> Done! Host directories are ready for compose deployment."
if [ "$WITH_LE" = true ]; then
    echo "    Next step: cd /opt/perfsonar-tp && podman-compose up -d"
else
    echo "    Next step: cd /opt/perfsonar-tp && podman-compose up -d"
fi
echo

exit 0
