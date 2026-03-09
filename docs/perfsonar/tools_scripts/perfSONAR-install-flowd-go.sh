#!/usr/bin/env bash
set -euo pipefail

# perfSONAR-install-flowd-go.sh
# Install and configure flowd-go (SciTags flow-marking daemon) for perfSONAR hosts.
#
# Version: 1.6.0 - 2026-10-22
#   - Forward fireflies through a local firefly listener (127.0.0.1:10514)
#     plus the firefly backend, keeping perfsonar-plugin packet marking.
#   - Turn TCP enrichment off (no 'enrichers' block, enrich: false): on EL9
#     flowd-go logs "error getting TCP information: net type 19 not
#     implemented" every minute (seen on psum01.aglt2.org, flowd-go 2.5.0).
#   - New --firefly-bind-port N and --no-firefly-receiver options.
#   (First proposed in March as PR #84; rebuilt on top of 1.5.0.)
# Version: 1.5.0 - 2026-10-19
#   - Install flowd-go from the CERN SciTags repository (written to
#     /etc/yum.repos.d/scitags.repo) instead of a fixed RPM URL. The pinned
#     flowd-go-2.5.0-1 file was removed from the repository, so new installs
#     failed with HTTP 404 (reported by UTA on test01.swt2.uta.edu). The
#     repository for the running EL major version is used, falling back to
#     the EL9 one if it does not exist. dnf now picks the newest flowd-go,
#     and 'dnf update' keeps it current.
#   - New --repo-url URL (repository base URL) and --rpm-url URL (install one
#     RPM, the old behaviour) override the default.
#   - VERSION now matches the header (it still said 1.2.0).
# Version: 1.4.0 - 2026-03-04
#   - Reduce TCP enrichment sampling interval from 15 to 60 seconds for lower overhead
#   - Firefly backend now sends START, periodic (every 60s) + END fireflies
#   - Optimal for long-running flows while maintaining TCP state visibility
# 
# Previous version (1.2.0) changes:
#   - Switch from fireflyp plugin to firefly backend for emitting flow start/end events
#   - Update to flowd-go 2.5.0+ (requires flowd-go >= 2.5.0)
#   - Remove support for flowd-go 2.4.x (use v1.1.0 of this script for 2.4.x support)
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Usage:
#   perfSONAR-install-flowd-go.sh [OPTIONS]
#
# Options:
#   --experiment-id N          Set the SciTags experiment ID (1-14, see --list-experiments)
#   --activity-id N            Set the SciTags activity ID (default: 2 = network testing)
#   --interfaces LIST          Comma-separated list of NIC names for packet marking
#                              (auto-detected from /etc/perfSONAR-multi-nic-config.conf if omitted)
#   --firefly-receiver HOST    Collector address for forwarded fireflies
#                              (default: global.scitags.org; set to empty to disable)
#   --firefly-receiver-port N  UDP port on the firefly collector (default: 10514)
#   --repo-url URL             Base URL of the SciTags RPM repository
#                              (default: CERN scitags<EL>al-testing for this EL version)
#   --rpm-url URL              Install this flowd-go RPM instead of using a repository
#   --firefly-bind-port N      Local UDP port flowd-go listens on for fireflies (default: 10514)
#   --no-firefly-receiver      Disable collector forwarding (eBPF packet marking only)
#   --list-experiments         Show available experiment IDs and exit
#   --yes                      Skip interactive prompts
#   --dry-run                  Preview actions without making changes
#   --uninstall                Remove flowd-go and its configuration
#   --version                  Show script version
#   --help, -h                 Show this help message
#
# Firefly Forwarding:
#   When --firefly-receiver is set (the default), flowd-go listens on 127.0.0.1:10514
#   for local firefly datagrams and forwards valid flow events to the configured collector.
#   This is the supported way to publish perfSONAR fireflies to global.scitags.org while
#   still using the perfsonar plugin for packet marking.

VERSION="1.6.0"
PROG_NAME="$(basename "$0")"
LOG_FILE="/var/log/perfSONAR-install-flowd-go.log"

# Defaults
EXPERIMENT_ID=""
ACTIVITY_ID=2
INTERFACES=""
AUTO_YES=false
DRY_RUN=false
UNINSTALL=false
MULTI_NIC_CONF="/etc/perfSONAR-multi-nic-config.conf"
FLOWD_GO_CONF="/etc/flowd-go/conf.yaml"
# flowd-go comes from the CERN SciTags repository. %s is the EL major version.
FLOWD_GO_REPO_URL_FMT="https://linuxsoft.cern.ch/repos/scitags%sal-testing/\$basearch/os/"
FLOWD_GO_REPO_URL=""     # --repo-url; default built from FLOWD_GO_REPO_URL_FMT
FLOWD_GO_RPM_URL=""      # --rpm-url; install one RPM instead of using the repo
FLOWD_GO_REPO_FILE="/etc/yum.repos.d/scitags.repo"
FLOWD_GO_MIN_VERSION="2.5.0"

# Firefly backend defaults
# global.scitags.org is the authoritative global SciTags firefly collector.
# Fireflies are sent at the start and end of each flow.
# Regional DNS aliases (e.g. us-east.scitags.org) may be used in future.
FIREFLY_RECEIVER="global.scitags.org"
FIREFLY_RECEIVER_PORT=10514
FIREFLY_BIND_PORT=10514

# Experiment name lookup
declare -A EXPERIMENT_NAMES=(
    [1]="Default (no specific experiment)"
    [2]="ATLAS"
    [3]="CMS"
    [4]="LHCb"
    [5]="ALICE"
    [6]="Belle II"
    [7]="SKA"
    [8]="DUNE"
    [9]="LSST / Rubin Observatory"
    [10]="ILC"
    [11]="Auger"
    [12]="JUNO"
    [13]="NOvA"
    [14]="XENON"
)

log() {
    local ts
    ts="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "$ts $*" | tee -a "$LOG_FILE"
}

run() {
    log "CMD: $*"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

confirm() {
    local msg="$1"
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    echo
    read -r -p "$msg [y/N]: " ans
    case "${ans:-}" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

list_experiments() {
    echo "Available SciTags experiment IDs:"
    echo
    printf "  %-4s %s\n" "ID" "Experiment"
    printf "  %-4s %s\n" "----" "----------"
    for id in $(seq 1 14); do
        printf "  %-4s %s\n" "$id" "${EXPERIMENT_NAMES[$id]}"
    done
    echo
    echo "Activity ID 2 (network testing) is used by default for perfSONAR."
}

prompt_experiment_id() {
    if [ -n "$EXPERIMENT_ID" ]; then
        return
    fi

    if [ "$AUTO_YES" = true ]; then
        EXPERIMENT_ID=1
        log "Non-interactive mode: using default experiment ID 1"
        return
    fi

    echo
    list_experiments
    echo
    local good=0
    while [ "$good" -eq 0 ]; do
        read -r -p "Select experiment ID (1-14): " EXPERIMENT_ID
        if [[ "$EXPERIMENT_ID" =~ ^[0-9]+$ ]] && [ "$EXPERIMENT_ID" -ge 1 ] && [ "$EXPERIMENT_ID" -le 14 ]; then
            good=1
        else
            echo "Please enter a number between 1 and 14."
        fi
    done
    log "Selected experiment: ${EXPERIMENT_NAMES[$EXPERIMENT_ID]} (ID=$EXPERIMENT_ID)"
}

detect_interfaces() {
    if [ -n "$INTERFACES" ]; then
        log "Using user-specified interfaces: $INTERFACES"
        return
    fi

    # Try to auto-detect from multi-NIC config
    if [ -f "$MULTI_NIC_CONF" ]; then
        log "Auto-detecting interfaces from $MULTI_NIC_CONF"
        # shellcheck disable=SC1090
        source "$MULTI_NIC_CONF" 2>/dev/null || true
        if [[ -v NIC_NAMES && ${#NIC_NAMES[@]} -gt 0 ]]; then
            INTERFACES=$(IFS=,; echo "${NIC_NAMES[*]}")
            log "Detected interfaces: $INTERFACES"
            return
        fi
    fi

    # Fall back to interfaces with default routes
    log "No multi-NIC config found; detecting interfaces from routing table"
    local ifaces
    ifaces=$(ip -o route show default 2>/dev/null | awk '{print $5}' | sort -u | tr '\n' ',' | sed 's/,$//')
    if [ -n "$ifaces" ]; then
        INTERFACES="$ifaces"
        log "Detected interfaces from routing table: $INTERFACES"
    else
        # Last resort: first non-lo interface
        ifaces=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1)
        INTERFACES="${ifaces:-lo}"
        log "Fallback interface: $INTERFACES"
    fi
}

build_config() {
    # Convert comma-separated interfaces to YAML list
    local iface_yaml="["
    local first=true
    IFS=',' read -ra iface_arr <<< "$INTERFACES"
    for iface in "${iface_arr[@]}"; do
        iface=$(echo "$iface" | xargs)  # trim whitespace
        if [ "$first" = true ]; then
            iface_yaml+="$iface"
            first=false
        else
            iface_yaml+=", $iface"
        fi
    done
    iface_yaml+="]"

    # Build plugin block: perfsonar for marking + optional firefly listener for forwarding.
    local plugins_block
    plugins_block=$(printf 'plugins:\n  perfsonar:\n    activityId: %s\n    experimentId: %s' \
        "$ACTIVITY_ID" "$EXPERIMENT_ID")

    if [ -n "$FIREFLY_RECEIVER" ]; then
        plugins_block=$(printf '%s\n  firefly:\n    bindAddress: "127.0.0.1"\n    bindPort: %s\n    hasSyslogHeader: false' \
            "$plugins_block" "$FIREFLY_BIND_PORT")
    fi

    # Build firefly backend block for collector forwarding.
    local firefly_backend=""
    if [ -n "$FIREFLY_RECEIVER" ]; then
        firefly_backend=$(printf '  firefly:\n    sendToCollector: true\n    collectorAddress: "%s"\n    collectorPort: %s\n    prependSyslog: false\n    enrich: false' \
            "$FIREFLY_RECEIVER" "$FIREFLY_RECEIVER_PORT")
    fi

    # Build marker backend block
    local marker_backend
    marker_backend=$(printf '  marker:\n    targetInterfaces: %s\n    markingStrategy: label\n    forceHookRemoval: true' \
        "$iface_yaml")

    # Combine everything
    local backends_block
    if [ -n "$firefly_backend" ]; then
        backends_block=$(printf 'backends:\n%s\n%s' "$firefly_backend" "$marker_backend")
    else
        backends_block=$(printf 'backends:\n%s' "$marker_backend")
    fi

    printf '%s\n\n%s\n' "$plugins_block" "$backends_block"
}

# Write the SciTags repo file for base URL $1.
write_scitags_repo() {
    local url="$1"
    log "Writing $FLOWD_GO_REPO_FILE (baseurl $url)"
    [ "$DRY_RUN" = true ] && return 0
    cat > "$FLOWD_GO_REPO_FILE" <<REPO
# Written by perfSONAR-install-flowd-go.sh: CERN SciTags packages (flowd-go).
[scitags]
name=SciTags (flowd-go)
baseurl=$url
enabled=1
gpgcheck=0
REPO
}

# Check that the scitags repo answers (its metadata downloads).
scitags_repo_ok() {
    [ "$DRY_RUN" = true ] && return 0
    "$PKG" -q -y --disablerepo='*' --enablerepo=scitags makecache >/dev/null 2>&1
}

install_flowd_go_rpm() {
    PKG=""
    command -v dnf &>/dev/null && PKG=dnf
    [ -z "$PKG" ] && command -v yum &>/dev/null && PKG=yum
    if [ -z "$PKG" ]; then
        log "ERROR: Neither dnf nor yum found. Cannot install flowd-go."
        return 1
    fi

    if [ -n "$FLOWD_GO_RPM_URL" ]; then
        log "Installing flowd-go from $FLOWD_GO_RPM_URL (--rpm-url)"
        run "$PKG" install -y "$FLOWD_GO_RPM_URL" || {
            log "ERROR: could not install $FLOWD_GO_RPM_URL"; return 1; }
        return 0
    fi

    local el_major url
    el_major=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID%%.*}")
    el_major=${el_major:-9}
    if [ -n "$FLOWD_GO_REPO_URL" ]; then
        url="$FLOWD_GO_REPO_URL"
        write_scitags_repo "$url"
    else
        # shellcheck disable=SC2059
        url=$(printf "$FLOWD_GO_REPO_URL_FMT" "$el_major")
        write_scitags_repo "$url"
        if ! scitags_repo_ok && [ "$el_major" != 9 ]; then
            # shellcheck disable=SC2059
            url=$(printf "$FLOWD_GO_REPO_URL_FMT" 9)
            log "WARNING: no SciTags repository for EL${el_major}; using the EL9 one"
            write_scitags_repo "$url"
        fi
    fi
    if ! scitags_repo_ok; then
        log "ERROR: the SciTags repository at $url is not reachable."
        log "       Check network access to linuxsoft.cern.ch, or pass --repo-url / --rpm-url."
        return 1
    fi

    log "Installing flowd-go from the SciTags repository..."
    run "$PKG" install -y --refresh flowd-go || {
        log "ERROR: '$PKG install flowd-go' failed (see above)."; return 1; }

    if [ "$DRY_RUN" != true ]; then
        local ver
        ver=$(rpm -q --queryformat '%{VERSION}' flowd-go 2>/dev/null || true)
        log "Installed flowd-go $ver"
        if [ -n "$ver" ] && [ "$(printf '%s\n%s\n' "$FLOWD_GO_MIN_VERSION" "$ver" | sort -V | head -1)" != "$FLOWD_GO_MIN_VERSION" ]; then
            log "WARNING: flowd-go $ver is older than $FLOWD_GO_MIN_VERSION, which the firefly backend needs."
        fi
    fi
}

install_flowd_go() {
    log "=== flowd-go installation started ==="

    # Check if already installed
    if rpm -q flowd-go &>/dev/null; then
        local installed_ver
        installed_ver=$(rpm -q --queryformat '%{VERSION}' flowd-go)
        log "flowd-go is already installed (version $installed_ver)"
        if ! confirm "Reconfigure flowd-go?"; then
            log "Skipping reconfiguration."
            return
        fi
    else
        install_flowd_go_rpm || return 1
    fi

    # Prompt for experiment
    prompt_experiment_id

    # Detect interfaces
    detect_interfaces

    # Generate and write config
    local config
    config=$(build_config)

    log "Writing configuration to $FLOWD_GO_CONF"
    echo "--- Proposed configuration ---"
    echo "$config"
    echo "------------------------------"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would write the above to $FLOWD_GO_CONF"
    else
        mkdir -p "$(dirname "$FLOWD_GO_CONF")"
        echo "$config" > "$FLOWD_GO_CONF"
        log "Configuration written to $FLOWD_GO_CONF"
    fi

    # Enable and start the service
    log "Enabling and starting flowd-go service"
    run systemctl daemon-reload
    run systemctl enable flowd-go
    run systemctl restart flowd-go

    log "Verifying flowd-go is running..."
    if [ "$DRY_RUN" != true ]; then
        sleep 2
        if systemctl is-active --quiet flowd-go; then
            log "flowd-go is running successfully."
            systemctl status flowd-go --no-pager -l 2>&1 | head -15 | tee -a "$LOG_FILE"
        else
            log "WARNING: flowd-go may not have started correctly. Check: journalctl -u flowd-go"
        fi
    fi

    log "=== flowd-go installation complete ==="
    echo
    echo "flowd-go is now marking egress traffic on interfaces: $INTERFACES"
    echo "  Experiment: ${EXPERIMENT_NAMES[$EXPERIMENT_ID]} (ID=$EXPERIMENT_ID)"
    echo "  Activity:   network testing (ID=$ACTIVITY_ID)"
    if [ -n "$FIREFLY_RECEIVER" ]; then
        echo "  Firefly collector: $FIREFLY_RECEIVER:$FIREFLY_RECEIVER_PORT"
        echo "  Local listener:   127.0.0.1:$FIREFLY_BIND_PORT"
        echo "  (forwarding valid local fireflies to the collector)"
    else
        echo "  Firefly collector: disabled (eBPF packet marking only)"
    fi
    echo
    echo "Verify with:"
    echo "  systemctl status flowd-go"
    echo "  journalctl -u flowd-go --no-pager -n 20"
    echo "  tc qdisc show"
}

uninstall_flowd_go() {
    log "=== flowd-go removal started ==="

    if ! rpm -q flowd-go &>/dev/null; then
        log "flowd-go is not installed. Nothing to remove."
        return
    fi

    if ! confirm "Remove flowd-go and its configuration?"; then
        log "Aborted."
        return
    fi

    log "Stopping and disabling flowd-go service"
    run systemctl stop flowd-go || true
    run systemctl disable flowd-go || true

    log "Removing flowd-go RPM"
    if command -v dnf &>/dev/null; then
        run dnf remove -y flowd-go
    elif command -v yum &>/dev/null; then
        run yum remove -y flowd-go
    fi

    if [ -f "$FLOWD_GO_CONF" ]; then
        log "Removing configuration file $FLOWD_GO_CONF"
        run rm -f "$FLOWD_GO_CONF"
    fi
    if [ -f "$FLOWD_GO_REPO_FILE" ] && grep -q 'perfSONAR-install-flowd-go.sh' "$FLOWD_GO_REPO_FILE"; then
        log "Removing $FLOWD_GO_REPO_FILE"
        run rm -f "$FLOWD_GO_REPO_FILE"
    fi

    log "=== flowd-go removal complete ==="
}

parse_cli() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --experiment-id)
                EXPERIMENT_ID="${2:-}"
                if [[ ! "$EXPERIMENT_ID" =~ ^[0-9]+$ ]] || [ "$EXPERIMENT_ID" -lt 1 ] || [ "$EXPERIMENT_ID" -gt 14 ]; then
                    echo "ERROR: experiment ID must be between 1 and 14" >&2
                    exit 1
                fi
                shift 2 ;;
            --activity-id)
                ACTIVITY_ID="${2:-2}"
                shift 2 ;;
            --interfaces)
                INTERFACES="${2:-}"
                shift 2 ;;
            --firefly-receiver)
                FIREFLY_RECEIVER="${2:-}"
                shift 2 ;;
            --firefly-receiver-port)
                FIREFLY_RECEIVER_PORT="${2:-10514}"
                shift 2 ;;
            --firefly-bind-port)
                FIREFLY_BIND_PORT="${2:-10514}"
                shift 2 ;;
            --no-firefly-receiver)
                FIREFLY_RECEIVER=""
                shift ;;

            --repo-url)
                FLOWD_GO_REPO_URL="${2:-}"
                shift 2 ;;
            --rpm-url)
                FLOWD_GO_RPM_URL="${2:-}"
                shift 2 ;;
            --list-experiments)
                list_experiments
                exit 0 ;;
            --yes) AUTO_YES=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --uninstall) UNINSTALL=true; shift ;;
            --version)
                echo "$PROG_NAME version $VERSION"
                exit 0 ;;
            --help|-h)
                sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
                exit 0 ;;
            *)
                echo "Unknown argument: $1" >&2
                exit 2 ;;
        esac
    done
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root (or with sudo)." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$LOG_FILE")"
    parse_cli "$@"

    if [ "$UNINSTALL" = true ]; then
        uninstall_flowd_go
    else
        install_flowd_go
    fi
}

main "$@"
