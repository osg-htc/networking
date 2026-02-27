#!/usr/bin/env bash
set -euo pipefail

# update-perfsonar-deployment.sh
# --------------------------------
# Update an existing perfSONAR deployment (container or RPM toolkit) to the
# latest helper scripts, configuration files, and templates.
#
# Version: 1.4.0 - 2026-02-26
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Version: 1.0.0 - 2026-02-26
#   - Initial release: container-only update support.
# Version: 1.1.0 - 2026-02-26
#   - Add RPM toolkit deployment support (--type toolkit).
#   - Auto-detect deployment type when --type is not specified.
#   - Phase 3 now checks RPM package updates for toolkit deployments.
#   - Phase 4 restarts native perfSONAR services instead of containers.
# Version: 1.2.0 - 2026-02-26
#   - Add automatic SELinux MCS label fix for LE container variants.
#     Certbot's prior :Z volume mounts stamped private MCS categories onto
#     /etc/letsencrypt and /var/www/html, locking out the perfsonar-testpoint
#     container (Apache 403 / connection refused). The script now detects and
#     corrects stale MCS labels (chcon -R -t container_file_t -l s0) with
#     --apply, and immediately restarts Apache inside the running container
#     when possible to restore service without a full container restart.
# Version: 1.3.0 - 2026-02-26
#   - Self-update relaunch: after Phase 1 downloads a newer version of this
#     script, exec() the new version with the original arguments instead of
#     continuing with the old version. This prevents the prior behaviour where
#     bash would read from an overwritten file and crash mid-run with a syntax
#     error on the first line of new content.
# Version: 1.4.0 - 2026-02-26
#   - Detect and patch stale systemd service files missing the /run/dbus and
#     node_exporter.defaults volume mounts. The service unit written by older
#     versions of install-systemd-units.sh omitted these mounts, causing
#     node_exporter to crash-loop on first scrape (cpufreq panic: "slice bounds
#     out of range") and D-Bus metrics to be unavailable. The update script
#     now detects missing mounts, patches the service file, reloads systemd,
#     and restarts the container to apply the fix automatically.
#
# This script is the recommended way to apply bug fixes, new features, and
# configuration improvements from the osg-htc/networking repository to an
# already-deployed perfSONAR host.  It is safe to run repeatedly (idempotent).
#
# Supported deployment types:
#
#   container  — perfSONAR testpoint running via podman-compose / docker-compose
#   toolkit    — perfSONAR toolkit installed from RPM packages (dnf)
#
# What it updates:
#   Phase 1  Helper scripts   → <base>/tools_scripts/
#   Phase 2  Configuration    → <base>/conf/ (container) or /etc/perfsonar/ (toolkit)
#   Phase 3  Compose / RPMs   → docker-compose.yml (container) or dnf update (toolkit)
#   Phase 4  Services         → recreate container (container) or restart services (toolkit)
#   Phase 5  Systemd units    → re-run install-systemd-units.sh (container only)
#
# Usage:
#   update-perfsonar-deployment.sh [OPTIONS]
#
# Options:
#   --base DIR          Base directory (default: auto-detect)
#   --type TYPE         Deployment type: container or toolkit (default: auto-detect)
#   --apply             Apply compose/config/RPM changes (default: report only)
#   --restart           Restart services after updates (implies --apply)
#   --update-systemd    Re-run install-systemd-units.sh (container only)
#   --yes               Skip interactive confirmations
#   --dry-run           Show what would change without modifying anything
#   --version           Show script version
#   --help, -h          Show this help message
#
# Examples:
#   # See what's changed (safe, read-only):
#   update-perfsonar-deployment.sh
#
#   # Apply all updates and restart (container):
#   update-perfsonar-deployment.sh --apply --restart
#
#   # Apply all updates and restart (RPM toolkit):
#   update-perfsonar-deployment.sh --type toolkit --apply --restart
#
#   # Non-interactive full update:
#   update-perfsonar-deployment.sh --apply --restart --yes

VERSION="1.4.0"

# Captured before parse_args so exec-relaunch can pass identical arguments.
ORIGINAL_ARGS=()
PROG_NAME="$(basename "$0")"

BASE_DIR=""
DEPLOY_TYPE=""   # container | toolkit
APPLY=false
RESTART=false
UPDATE_SYSTEMD=false
AUTO_YES=false
DRY_RUN=false

TOOLS_SRC="https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts"
CHANGES_FOUND=0
COMPOSE_CHANGED=false
CONFIG_CHANGED=false
SERVICE_FILE_CHANGED=false
RPM_UPDATES_AVAILABLE=false

# --- Colours (disabled when piped) ----------------------------------------
if [[ -t 1 ]]; then
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_RED='\033[0;31m'
    C_CYAN='\033[1;36m'
    C_RESET='\033[0m'
else
    C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_RESET=''
fi

# --- Helpers ---------------------------------------------------------------
info()  { printf "${C_GREEN}[INFO]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }
error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
changed() { printf "${C_CYAN}[CHANGED]${C_RESET} %s\n" "$*"; CHANGES_FOUND=1; }
ok()    { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$*"; }

confirm() {
    local msg="$1"
    if [[ "$AUTO_YES" == true ]]; then return 0; fi
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    echo
    read -r -p "$msg [y/N]: " ans
    case "${ans:-n}" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# --- CLI -------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: update-perfsonar-deployment.sh [OPTIONS]

Update an existing perfSONAR deployment (container or RPM toolkit) to the
latest helper scripts, configuration files, and templates.

Options:
  --base DIR          Base directory (default: auto-detect)
  --type TYPE         Deployment type: container or toolkit (default: auto-detect)
  --apply             Apply compose/config/RPM changes (default: report only)
  --restart           Restart services after updates (implies --apply)
  --update-systemd    Re-run install-systemd-units.sh (container only)
  --yes               Skip interactive confirmations
  --dry-run           Show what would change without modifying anything
  --version           Show script version
  --help, -h          Show this help message

Without --apply, the script runs in report-only mode showing what would change.

Deployment types:
  container   perfSONAR testpoint via podman-compose/docker-compose
  toolkit     perfSONAR toolkit installed from RPM packages (dnf)

If --type is omitted, the script auto-detects based on the presence of
docker-compose.yml (container) or perfsonar RPM packages (toolkit).
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)       shift; BASE_DIR="${1:?--base requires a directory}"; shift ;;
            --type)       shift; DEPLOY_TYPE="${1:?--type requires container or toolkit}"; shift ;;
            --apply)      APPLY=true; shift ;;
            --restart)    RESTART=true; APPLY=true; shift ;;
            --update-systemd) UPDATE_SYSTEMD=true; shift ;;
            --yes)        AUTO_YES=true; shift ;;
            --dry-run)    DRY_RUN=true; shift ;;
            --version)    echo "$PROG_NAME version $VERSION"; exit 0 ;;
            -h|--help)    usage; exit 0 ;;
            *)            error "Unknown argument: $1"; usage; exit 2 ;;
        esac
    done

    # Validate --type if supplied
    if [[ -n "$DEPLOY_TYPE" ]] && [[ "$DEPLOY_TYPE" != "container" && "$DEPLOY_TYPE" != "toolkit" ]]; then
        error "--type must be 'container' or 'toolkit' (got: $DEPLOY_TYPE)"
        exit 2
    fi
}

# --- Phase 0: Preflight ---------------------------------------------------

# Auto-detect deployment type
detect_deploy_type() {
    # Explicit base dir with docker-compose → container
    if [[ -n "$BASE_DIR" && -f "$BASE_DIR/docker-compose.yml" ]]; then
        echo "container"
        return
    fi

    # Well-known container locations
    for d in /opt/perfsonar-tp /opt/perfsonar; do
        if [[ -f "$d/docker-compose.yml" ]]; then
            echo "container"
            return
        fi
    done

    # RPM packages present → toolkit
    if rpm -q perfsonar-toolkit &>/dev/null || rpm -q perfsonar-testpoint &>/dev/null; then
        echo "toolkit"
        return
    fi

    # Fallback: check for common perfsonar services
    if systemctl list-unit-files pscheduler-scheduler.service &>/dev/null; then
        echo "toolkit"
        return
    fi

    echo "unknown"
}

# Auto-detect base directory for the deployment type
detect_base_dir() {
    local dtype="$1"
    if [[ "$dtype" == "container" ]]; then
        for d in /opt/perfsonar-tp /opt/perfsonar; do
            if [[ -f "$d/docker-compose.yml" ]]; then
                echo "$d"
                return
            fi
        done
        echo "/opt/perfsonar-tp"
    else
        # Toolkit: look for tools_scripts in common locations
        for d in /opt/perfsonar-toolkit /opt/perfsonar-tp /opt/perfsonar; do
            if [[ -d "$d/tools_scripts" ]]; then
                echo "$d"
                return
            fi
        done
        echo "/opt/perfsonar-toolkit"
    fi
}

preflight() {
    info "perfSONAR Deployment Updater v${VERSION}"
    echo

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (or with sudo)."
        exit 1
    fi

    # Auto-detect deployment type if not specified
    if [[ -z "$DEPLOY_TYPE" ]]; then
        DEPLOY_TYPE=$(detect_deploy_type)
        if [[ "$DEPLOY_TYPE" == "unknown" ]]; then
            error "Could not auto-detect deployment type."
            error "Use --type container or --type toolkit to specify."
            exit 1
        fi
        info "Auto-detected deployment type: $DEPLOY_TYPE"
    fi

    # Auto-detect base directory if not specified
    if [[ -z "$BASE_DIR" ]]; then
        BASE_DIR=$(detect_base_dir "$DEPLOY_TYPE")
    fi

    if [[ ! -d "$BASE_DIR" ]]; then
        error "Base directory $BASE_DIR does not exist."
        error "This script updates an EXISTING deployment. Run the initial installer first."
        exit 1
    fi

    TOOLS_DIR="$BASE_DIR/tools_scripts"
    CONF_DIR="$BASE_DIR/conf"

    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

        if [[ ! -f "$COMPOSE_FILE" ]]; then
            error "No docker-compose.yml found at $COMPOSE_FILE"
            error "This host does not appear to have a deployed container testpoint."
            exit 1
        fi

        # Detect container runtime
        if command -v podman >/dev/null 2>&1; then
            RUNTIME="podman"
            COMPOSE_CMD="podman-compose"
        elif command -v docker >/dev/null 2>&1; then
            RUNTIME="docker"
            COMPOSE_CMD="docker compose"
        else
            error "Neither podman nor docker found."
            exit 1
        fi

        info "Deployment type:   container"
        info "Base directory:    $BASE_DIR"
        info "Compose file:      $COMPOSE_FILE"
        info "Container runtime: $RUNTIME"
    else
        COMPOSE_FILE=""
        RUNTIME=""
        COMPOSE_CMD=""

        info "Deployment type:   toolkit (RPM)"
        info "Base directory:    $BASE_DIR"
        local ps_ver
        ps_ver=$(rpm -q perfsonar-toolkit 2>/dev/null || rpm -q perfsonar-testpoint 2>/dev/null || echo "not installed")
        info "perfSONAR package: $ps_ver"
    fi

    if [[ "$APPLY" == true ]]; then
        info "Mode: APPLY changes"
    else
        info "Mode: REPORT only (use --apply to make changes)"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        info "Dry-run: no changes will be written"
    fi
    echo
}

# --- Phase 1: Update helper scripts ---------------------------------------
phase1_update_scripts() {
    info "Phase 1: Updating helper scripts..."

    if [[ ! -d "$TOOLS_DIR" ]]; then
        mkdir -p "$TOOLS_DIR"
    fi

    # Save current versions for comparison
    local old_versions_file
    old_versions_file=$(mktemp)
    for f in "$TOOLS_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local base ver
        base=$(basename "$f")
        ver=$(grep -m1 '^# Version:' "$f" 2>/dev/null | sed 's/^# Version: *//' || echo "?")
        echo "$base=$ver" >> "$old_versions_file"
    done

    # Re-run bootstrap to download latest scripts
    info "  Downloading latest scripts from repository..."
    local bootstrap_url="$TOOLS_SRC/install_tools_scripts.sh"
    local tmp_bootstrap
    tmp_bootstrap=$(mktemp)

    if ! curl -fsSL "$bootstrap_url" -o "$tmp_bootstrap" 2>/dev/null; then
        error "  Failed to download bootstrap script. Check network connectivity."
        rm -f "$tmp_bootstrap" "$old_versions_file"
        return 1
    fi
    chmod 0755 "$tmp_bootstrap"

    # Run the bootstrap (it downloads all scripts to tools_scripts/)
    if ! bash "$tmp_bootstrap" "$BASE_DIR" 2>&1 | sed 's/^/    /'; then
        warn "  Bootstrap reported warnings (see above)"
    fi
    rm -f "$tmp_bootstrap"

    # Compare versions
    local new_count=0 updated_count=0 unchanged_count=0
    for f in "$TOOLS_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        local base ver_new ver_old
        base=$(basename "$f")
        ver_new=$(grep -m1 '^# Version:' "$f" 2>/dev/null | sed 's/^# Version: *//' || echo "?")
        ver_old=$(grep "^${base}=" "$old_versions_file" 2>/dev/null | cut -d= -f2- || echo "")
        if [[ -z "$ver_old" ]]; then
            changed "  NEW: $base (v${ver_new})"
            new_count=$((new_count + 1))
        elif [[ "$ver_old" != "$ver_new" ]]; then
            changed "  UPDATED: $base (${ver_old} → ${ver_new})"
            updated_count=$((updated_count + 1))
        else
            unchanged_count=$((unchanged_count + 1))
        fi
    done
    rm -f "$old_versions_file"

    info "  Scripts: $updated_count updated, $new_count new, $unchanged_count unchanged"
    echo
}

# --- Phase 2: Update configuration files -----------------------------------

# Registry of host config files: source (relative to tools_scripts/) → dest (relative to base dir)
# Container deployments mount these into the container via compose volumes.
# shellcheck disable=SC2034 # used via nameref config_map
declare -A CONFIG_FILES_CONTAINER=(
    [node_exporter.defaults]="conf/node_exporter.defaults"
)

# Toolkit (RPM) deployments: config files that should be placed on the host.
# These are advisory overrides or additions not managed by the RPM package.
# shellcheck disable=SC2034 # used via nameref config_map
declare -A CONFIG_FILES_TOOLKIT=()
# (Currently empty — toolkit RPMs manage their own configs.  Future entries
# can be added here, e.g. sysctl drop-ins or tuned profiles.)

phase2_update_configs() {
    info "Phase 2: Checking host configuration files..."

    mkdir -p "$CONF_DIR"

    # Select the right registry
    local -n config_map
    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        config_map=CONFIG_FILES_CONTAINER
    else
        config_map=CONFIG_FILES_TOOLKIT
    fi

    if [[ ${#config_map[@]} -eq 0 ]]; then
        ok "  No managed configuration files for $DEPLOY_TYPE deployments"
        echo
        return
    fi

    local updates=0
    for src_name in "${!config_map[@]}"; do
        local src_file="$TOOLS_DIR/$src_name"
        local dst_relative="${config_map[$src_name]}"
        local dst_file="$BASE_DIR/$dst_relative"

        if [[ ! -f "$src_file" ]]; then
            warn "  Source file not found in tools_scripts: $src_name (skipping)"
            continue
        fi

        if [[ ! -f "$dst_file" ]]; then
            changed "  NEW config: $dst_relative (not yet installed)"
            updates=$((updates + 1))
            if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
                mkdir -p "$(dirname "$dst_file")"
                cp -p "$src_file" "$dst_file"
                info "    → Installed $dst_file"
                CONFIG_CHANGED=true
            fi
        elif ! cmp -s "$src_file" "$dst_file"; then
            changed "  UPDATED config: $dst_relative"
            # Show a concise diff
            if command -v diff >/dev/null 2>&1; then
                diff --unified=2 "$dst_file" "$src_file" 2>/dev/null | head -30 | sed 's/^/    /' || true
            fi
            updates=$((updates + 1))
            if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
                local backup
                backup="${dst_file}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
                cp -p "$dst_file" "$backup"
                cp -p "$src_file" "$dst_file"
                info "    → Updated $dst_file (backup: $backup)"
                CONFIG_CHANGED=true
            fi
        else
            ok "  $dst_relative is current"
        fi
    done

    if [[ $updates -eq 0 ]]; then
        ok "  All configuration files are up to date"
    fi
    echo
}

# --- Phase 3: Update compose (container) or RPMs (toolkit) -----------------

detect_compose_variant() {
    local compose_file="$1"
    if grep -q 'testpoint-entrypoint-wrapper' "$compose_file" 2>/dev/null; then
        echo "testpoint-le-auto"
    elif grep -q 'certbot' "$compose_file" 2>/dev/null; then
        echo "testpoint-le"
    else
        echo "testpoint"
    fi
}

phase3_container_compose() {
    info "Phase 3: Checking docker-compose.yml..."

    local variant
    variant=$(detect_compose_variant "$COMPOSE_FILE")
    local template_name="docker-compose.${variant}.yml"
    local template_file="$TOOLS_DIR/$template_name"

    info "  Detected deployment variant: $variant"
    info "  Template: $template_name"

    if [[ ! -f "$template_file" ]]; then
        warn "  Template file $template_file not found (may not have been downloaded yet)"
        echo
        return
    fi

    if cmp -s "$COMPOSE_FILE" "$template_file"; then
        ok "  docker-compose.yml matches the latest template"
    else
        changed "  docker-compose.yml differs from latest $template_name"
        COMPOSE_CHANGED=true

        if command -v diff >/dev/null 2>&1; then
            echo
            info "  Differences (current → new):"
            diff --unified=3 "$COMPOSE_FILE" "$template_file" 2>/dev/null | head -60 | sed 's/^/    /' || true
            echo
        fi

        if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
            if confirm "  Replace $COMPOSE_FILE with latest $template_name?"; then
                local backup
                backup="${COMPOSE_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
                cp -p "$COMPOSE_FILE" "$backup"
                cp -p "$template_file" "$COMPOSE_FILE"
                info "    → Updated $COMPOSE_FILE (backup: $backup)"
            else
                info "    → Skipped compose update"
                COMPOSE_CHANGED=false
            fi
        fi
    fi
    echo
}

phase3_toolkit_rpms() {
    info "Phase 3: Checking for perfSONAR RPM updates..."

    if ! command -v dnf >/dev/null 2>&1; then
        warn "  dnf not found; cannot check RPM updates"
        echo
        return
    fi

    info "  Refreshing repository metadata..."
    dnf clean expire-cache -q 2>/dev/null || true

    local update_list
    update_list=$(dnf check-update 'perfsonar*' 2>/dev/null || true)

    # dnf check-update returns exit 100 when updates exist, 0 when none
    if [[ -z "$update_list" ]] || ! echo "$update_list" | grep -qi 'perfsonar'; then
        ok "  All perfSONAR RPM packages are up to date"
    else
        changed "  perfSONAR RPM updates available:"
        echo "$update_list" | grep -i 'perfsonar' | sed 's/^/    /'
        RPM_UPDATES_AVAILABLE=true

        if [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
            if confirm "  Apply RPM updates now (dnf update 'perfsonar*')?"; then
                info "  Updating perfSONAR packages..."
                dnf update -y 'perfsonar*' 2>&1 | tail -20 | sed 's/^/    /'
                ok "  RPM updates applied"

                # Re-run post-install configuration scripts if they exist
                if [[ -x /usr/lib/perfsonar/scripts/configure_sysctl ]]; then
                    info "  Re-running configure_sysctl..."
                    /usr/lib/perfsonar/scripts/configure_sysctl 2>&1 | sed 's/^/    /' || true
                fi
            else
                info "  RPM update skipped"
                RPM_UPDATES_AVAILABLE=false
            fi
        fi
    fi

    # Also check for OS / kernel updates that matter for measurement hosts
    local os_updates
    os_updates=$(dnf check-update kernel iproute nftables 2>/dev/null | grep -E 'kernel|iproute|nftables' || true)
    if [[ -n "$os_updates" ]]; then
        warn "  Related OS package updates available (not auto-applied):"
        echo "$os_updates" | sed 's/^/    /'
        echo "    Run 'dnf update' to apply OS updates during a maintenance window."
    fi
    echo
}

phase3_update() {
    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        phase3_container_compose
    else
        phase3_toolkit_rpms
    fi
}

# --- SELinux MCS label auto-fix (container LE variants) --------------------
#
# When a container mounts a host directory with :Z (private MCS relabeling)
# it stamps that container's random MCS categories onto the host path.  If
# two containers share the same host directory and one uses :Z, every
# recreation of that container locks the other container out with a 'Permission
# denied' or 'file does not exist' error from Apache.
#
# The compose files were fixed (v1.5.1) to use :z (shared) for certbot, but
# hosts that ran the old :Z compose will have stale MCS labels on disk.  This
# function detects and corrects them with --apply before any container restart.
fix_container_selinux_labels() {
    [[ "$DEPLOY_TYPE" == "container" ]] || return 0

    # Only relevant if SELinux is present and enforcing
    command -v getenforce >/dev/null 2>&1 || return 0
    [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]] || return 0

    # Only applies to LE variants that use certbot
    grep -q 'certbot' "$COMPOSE_FILE" 2>/dev/null || return 0

    info "SELinux label check (shared directories in LE deployment)..."

    local dirs_to_fix=()
    for dir in /etc/letsencrypt /var/www/html; do
        [[ -d "$dir" ]] || continue
        # Private MCS categories appear as :s0:c<N> on the directory itself
        local ctx
        ctx=$(ls -dZ "$dir" 2>/dev/null | awk '{print $1}' || echo "")
        if echo "$ctx" | grep -qE ':s0:c[0-9]'; then
            dirs_to_fix+=("$dir")
        fi
    done

    if [[ ${#dirs_to_fix[@]} -eq 0 ]]; then
        ok "  SELinux labels on shared directories are correct"
        echo
        return 0
    fi

    warn "  Stale private SELinux MCS labels detected on shared directories:"
    for dir in "${dirs_to_fix[@]}"; do
        local ctx
        ctx=$(ls -dZ "$dir" 2>/dev/null | awk '{print $1}')
        warn "    $dir  [$ctx]"
    done
    warn "  These prevent Apache inside the container from reading TLS certificates"
    warn "  or serving web content (symptoms: connection refused / HTTP 403)."

    if [[ "$APPLY" != true ]]; then
        warn "  Run with --apply to automatically correct these labels."
        echo
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "  [DRY-RUN] Would run: chcon -R -t container_file_t -l s0 ${dirs_to_fix[*]}"
        echo
        return 0
    fi

    info "  Correcting labels to shared container_file_t:s0 (no MCS restriction)..."
    local fixed=0
    for dir in "${dirs_to_fix[@]}"; do
        if chcon -R -t container_file_t -l s0 "$dir"; then
            ok "    Fixed: $dir"
            fixed=$((fixed + 1))
        else
            warn "    Failed to fix labels on $dir — check SELinux policy"
        fi
    done

    # If Apache failed inside an already-running container, restart it now so
    # service is restored immediately without needing a full container restart.
    if [[ $fixed -gt 0 ]] && command -v "$RUNTIME" >/dev/null 2>&1; then
        if "$RUNTIME" inspect perfsonar-testpoint &>/dev/null 2>&1; then
            local apache_state
            apache_state=$("$RUNTIME" exec perfsonar-testpoint \
                systemctl is-active apache2 2>/dev/null || echo "inactive")
            if [[ "$apache_state" != "active" ]]; then
                info "  Apache is not running inside container — restarting now..."
                if "$RUNTIME" exec perfsonar-testpoint systemctl start apache2 &>/dev/null; then
                    ok "    Apache started inside perfsonar-testpoint"
                else
                    warn "    Apache start failed — a container restart (--restart) will attempt recovery"
                fi
            else
                ok "    Apache is already running inside container"
            fi
        fi
    fi
    echo
}

# --- Fix stale systemd service file (container only) -----------------------
#
# Older versions of install-systemd-units.sh omitted two volume mounts from
# the perfsonar-testpoint.service unit:
#   1. /run/dbus:/run/dbus:ro  — required for --collector.systemd in node_exporter
#   2. <base>/conf/node_exporter.defaults:/etc/default/node_exporter:z
#        — required for the --no-collector.cpufreq workaround; without it,
#          node_exporter panics on its first scrape (procfs v0.10.0 bug:
#          "slice bounds out of range [13:12]").
#
# This function detects and patches the deployed service file in-place.
# phase4_container_restart handles daemon-reload + service restart.

fix_stale_service_file() {
    if [[ "$DEPLOY_TYPE" != "container" ]]; then
        return
    fi

    local svc="/etc/systemd/system/perfsonar-testpoint.service"
    if [[ ! -f "$svc" ]]; then
        return
    fi

    info "Checking systemd service file for required volume mounts..."

    local missing=()
    grep -q '/run/dbus:/run/dbus' "$svc" || missing+=("/run/dbus")
    grep -q 'node_exporter.defaults' "$svc" || missing+=("node_exporter.defaults")

    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "  Service file has all required volume mounts"
        echo
        return
    fi

    changed "  Service file missing volume mounts: ${missing[*]}"
    CHANGES_FOUND=1

    if [[ "$DRY_RUN" == true ]]; then
        info "  [DRY-RUN] Would patch: $svc"
        echo
        return
    fi

    if [[ "$APPLY" != true ]]; then
        echo
        return
    fi

    # Patch in-place with awk: insert missing mounts after the tools_scripts volume line
    if ! grep -q '/run/dbus:/run/dbus' "$svc"; then
        awk '/tools_scripts.*:ro/{print; print "  -v /run/dbus:/run/dbus:ro \\"; next}1' \
            "$svc" > "${svc}.tmp" && mv "${svc}.tmp" "$svc"
    fi
    if ! grep -q 'node_exporter.defaults' "$svc"; then
        awk -v base="$BASE_DIR" \
            '/tools_scripts.*:ro/{print; print "  -v " base "/conf/node_exporter.defaults:/etc/default/node_exporter:z \\"; next}1' \
            "$svc" > "${svc}.tmp" && mv "${svc}.tmp" "$svc"
    fi

    ok "  ✓ Patched $svc with missing volume mounts"
    SERVICE_FILE_CHANGED=true
    echo
}

# --- Phase 4: Restart services ---------------------------------------------

# perfSONAR toolkit services to restart after RPM updates
TOOLKIT_SERVICES=(
    pscheduler-scheduler
    pscheduler-runner
    pscheduler-archiver
    pscheduler-ticker
    psconfig-pscheduler-agent
    owamp-server
    perfsonar-lsregistrationdaemon
    httpd
)

phase4_container_restart() {
    info "Phase 4: Container management..."

    if [[ "$COMPOSE_CHANGED" != true && "$CONFIG_CHANGED" != true && "$SERVICE_FILE_CHANGED" != true ]]; then
        ok "  No compose, config, or service file changes detected — container restart not needed"
        echo
        return
    fi

    if [[ "$RESTART" != true ]]; then
        if [[ "$COMPOSE_CHANGED" == true || "$CONFIG_CHANGED" == true || "$SERVICE_FILE_CHANGED" == true ]]; then
            warn "  Changes were applied but container was NOT restarted."
            warn "  Run with --restart to recreate the container, or manually:"
            if [[ "$SERVICE_FILE_CHANGED" == true && "$COMPOSE_CHANGED" != true ]]; then
                warn "    systemctl daemon-reload && systemctl restart perfsonar-testpoint.service"
            else
                warn "    cd $BASE_DIR && $COMPOSE_CMD down && $COMPOSE_CMD up -d"
            fi
        fi
        echo
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$SERVICE_FILE_CHANGED" == true && "$COMPOSE_CHANGED" != true ]]; then
            info "  [DRY-RUN] Would run: systemctl daemon-reload && systemctl restart perfsonar-testpoint.service"
        else
            info "  [DRY-RUN] Would recreate containers via: $COMPOSE_CMD down && $COMPOSE_CMD up -d"
        fi
        echo
        return
    fi

    if confirm "  Recreate containers now? This will briefly interrupt perfSONAR services."; then
        if [[ "$SERVICE_FILE_CHANGED" == true && "$COMPOSE_CHANGED" != true ]]; then
            # Service file was patched but compose is unchanged: reload unit and restart service
            info "  Reloading systemd configuration..."
            systemctl daemon-reload 2>&1 | sed 's/^/    /' || true
            info "  Restarting perfsonar-testpoint service..."
            systemctl restart perfsonar-testpoint.service 2>&1 | sed 's/^/    /'
        else
            info "  Stopping containers..."
            (cd "$BASE_DIR" && $COMPOSE_CMD down 2>&1 | sed 's/^/    /')
            info "  Starting containers with updated compose..."
            (cd "$BASE_DIR" && $COMPOSE_CMD up -d 2>&1 | sed 's/^/    /')
        fi

        info "  Waiting 15s for container startup..."
        sleep 15
        if $RUNTIME ps --filter name=perfsonar-testpoint --format '{{.Status}}' 2>/dev/null | grep -qi "up\|healthy"; then
            ok "  Container is running"
        else
            warn "  Container may not be fully ready yet — check with: $RUNTIME ps"
        fi
    else
        info "  Container restart skipped"
    fi
    echo
}

phase4_toolkit_restart() {
    info "Phase 4: Service management..."

    if [[ "$RPM_UPDATES_AVAILABLE" != true && "$CONFIG_CHANGED" != true ]]; then
        ok "  No RPM or config changes detected — service restart not needed"
        echo
        return
    fi

    if [[ "$RESTART" != true ]]; then
        warn "  Changes were applied but services were NOT restarted."
        warn "  Run with --restart to restart perfSONAR services, or manually:"
        warn "    systemctl restart ${TOOLKIT_SERVICES[*]}"
        echo
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "  [DRY-RUN] Would restart: ${TOOLKIT_SERVICES[*]}"
        echo
        return
    fi

    if confirm "  Restart perfSONAR services now? Tests in progress may be interrupted."; then
        info "  Restarting perfSONAR services..."
        local svc
        for svc in "${TOOLKIT_SERVICES[@]}"; do
            if systemctl is-enabled "$svc" &>/dev/null; then
                systemctl restart "$svc" 2>&1 | sed 's/^/    /' || true
                ok "    $svc restarted"
            fi
        done

        # Brief health check
        sleep 5
        local running=0 total=0
        for svc in "${TOOLKIT_SERVICES[@]}"; do
            if systemctl is-enabled "$svc" &>/dev/null; then
                total=$((total + 1))
                if systemctl is-active "$svc" &>/dev/null; then
                    running=$((running + 1))
                fi
            fi
        done
        info "  Services: $running/$total active"
    else
        info "  Service restart skipped"
    fi
    echo
}

phase4_restart() {
    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        phase4_container_restart
    else
        phase4_toolkit_restart
    fi
}

# --- Phase 5: Update systemd units (container only) -----------------------

phase5_systemd() {
    if [[ "$DEPLOY_TYPE" == "toolkit" ]]; then
        # Toolkit deployments manage services via RPM scriptlets, not custom units
        return
    fi

    if [[ "$UPDATE_SYSTEMD" != true ]]; then
        return
    fi

    info "Phase 5: Updating systemd units..."

    local installer="$TOOLS_DIR/install-systemd-units.sh"
    if [[ ! -x "$installer" ]]; then
        warn "  install-systemd-units.sh not found or not executable in $TOOLS_DIR"
        echo
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "  [DRY-RUN] Would run: $installer --install-dir $BASE_DIR --auto-update"
        echo
        return
    fi

    if confirm "  Refresh systemd units (service + auto-update timer)?"; then
        bash "$installer" --install-dir "$BASE_DIR" --auto-update 2>&1 | sed 's/^/    /'
        ok "  Systemd units refreshed"
    fi
    echo
}

# --- Summary ---------------------------------------------------------------

print_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "Deployment type: $DEPLOY_TYPE"
    if [[ "$CHANGES_FOUND" -eq 0 ]]; then
        ok "Deployment is fully up to date. No changes needed."
    elif [[ "$APPLY" == true && "$DRY_RUN" != true ]]; then
        info "Update complete. Changes were applied."
        local needs_restart=false
        if [[ "$DEPLOY_TYPE" == "container" ]]; then
            if [[ "$COMPOSE_CHANGED" == true || "$CONFIG_CHANGED" == true ]]; then
                needs_restart=true
            fi
        else
            if [[ "$RPM_UPDATES_AVAILABLE" == true || "$CONFIG_CHANGED" == true ]]; then
                needs_restart=true
            fi
        fi
        if [[ "$needs_restart" == true && "$RESTART" != true ]]; then
            warn "Service restart pending. Run with --restart or manually:"
            if [[ "$DEPLOY_TYPE" == "container" ]]; then
                echo "  cd $BASE_DIR && $COMPOSE_CMD down && $COMPOSE_CMD up -d"
            else
                echo "  systemctl restart ${TOOLKIT_SERVICES[*]}"
            fi
        fi
    else
        warn "Changes detected but NOT applied (report-only mode)."
        echo "  Re-run with --apply to apply changes."
        echo "  Re-run with --apply --restart to apply and restart services."
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- Self-update relaunch --------------------------------------------------
#
# Phase 1 may download a newer version of this very script into tools_scripts/.
# If the running script is then an older version, bash could:
#   a) continue executing with stale logic (features missing), or
#   b) crash with a syntax error if bash buffered old file contents and
#      then re-reads from the overwritten file at an unexpected offset.
#
# Solution: after Phase 1, compare the version embedded in the newly-installed
# tools_scripts copy with $VERSION. If they differ, exec() the new script with
# the original arguments. exec() replaces this process entirely — the new
# script starts cleanly from line 1 with no risk of reading stale content.
maybe_relaunch_if_self_updated() {
    local new_script="$TOOLS_DIR/update-perfsonar-deployment.sh"
    [[ -f "$new_script" ]] || return 0

    # Extract the leading semver from the first '# Version:' line.
    local new_version
    new_version=$(grep -m1 '^# Version:' "$new_script" 2>/dev/null \
        | awk '{print $3}' || true)
    [[ -n "$new_version" ]] || return 0
    [[ "$new_version" != "$VERSION" ]] || return 0

    echo
    info "This script was updated ($VERSION → $new_version) during Phase 1."
    info "Re-launching updated script to continue with remaining phases..."
    echo
    exec "$new_script" "${ORIGINAL_ARGS[@]}"
}

# --- Main ------------------------------------------------------------------

main() {
    ORIGINAL_ARGS=("$@")
    parse_args "$@"
    preflight
    phase1_update_scripts
    maybe_relaunch_if_self_updated
    phase2_update_configs
    fix_stale_service_file
    phase3_update
    fix_container_selinux_labels
    phase4_restart
    phase5_systemd
    print_summary
}

main "$@"
