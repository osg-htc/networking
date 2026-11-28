#!/bin/bash
# perfSONAR-auto-update.sh
# ------------------------
# Purpose:
#   Check for updated container images and restart services if new images are
#   found. Uses image digest comparison (Podman-compatible). Does NOT rely on
#   Docker-specific output strings like "Downloaded newer image" which Podman
#   never emits.
#
# Usage:
#   Run as root, typically via the perfsonar-auto-update.timer systemd timer.
#   Can also be invoked manually: bash /usr/local/bin/perfsonar-auto-update.sh
#
# What it does:
#   1. Records the current local image digest for each managed image.
#   2. Pulls each image from the registry.
#   3. Compares the new digest to the old one.
#   4. If the testpoint image changed, restarts perfsonar-testpoint.service.
#      If the image of a long-running certbot sidecar (installs before
#      install-systemd-units.sh 1.9.0) changed, restarts perfsonar-certbot.service.
#      The timer-based certbot of 1.9.0+ runs a pinned image and is not touched.
#
# Which testpoint image: the one the perfsonar-testpoint container was created
# from (so a host pinned to a tag or trialling another tag is compared with
# that tag, not with :production); else the image in the unit's ExecStart;
# else :production. Override with TESTPOINT_IMAGE=... in the environment.
# Images under localhost/ are local builds and are not pulled.
#
# Logs:
#   /var/log/perfsonar-auto-update.log  (appended on every run)
#
# Author: OSG perfSONAR deployment tools
# Version: 1.1.0 - 2026-11-28
#   - Follow the image the testpoint container actually runs instead of always
#     :production. Before, a host running another tag was restarted every night
#     ("stale image"), onto the same tag again.
#   - Certbot sidecar image updates restart perfsonar-certbot.service, not the
#     testpoint.
# Version: 1.0.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

LOGFILE="/var/log/perfsonar-auto-update.log"

DEFAULT_TESTPOINT_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production"
TESTPOINT_CONTAINER="perfsonar-testpoint"
TESTPOINT_SERVICE="perfsonar-testpoint.service"
CERTBOT_CONTAINER="certbot"
CERTBOT_SERVICE="perfsonar-certbot.service"

# ── Helpers ────────────────────────────────────────────────────────────────────

log() { echo "$(date -Iseconds) $*" | tee -a "$LOGFILE"; }

# Return the local image ID, or "none" if image is not present.
get_image_id() {
    podman image inspect "$1" --format "{{.Id}}" 2>/dev/null || echo "none"
}

# Return the image ID of a running container by name, or "none" if the
# container is not running.
get_container_image_id() {
    podman inspect "$1" --format "{{.Image}}" 2>/dev/null || echo "none"
}

# The image the testpoint should run (see header).
detect_testpoint_image() {
    local img
    if [[ -n "${TESTPOINT_IMAGE:-}" ]]; then echo "$TESTPOINT_IMAGE"; return; fi
    img=$(podman inspect "$TESTPOINT_CONTAINER" --format "{{.ImageName}}" 2>/dev/null || true)
    if [[ -z "$img" ]]; then
        img=$(systemctl show "$TESTPOINT_SERVICE" -p ExecStart --value 2>/dev/null \
              | grep -oE '[a-z0-9.-]+(:[0-9]+)?/[^ ;]*perfsonar-testpoint[^ ;]*' | head -n1 || true)
    fi
    echo "${img:-$DEFAULT_TESTPOINT_IMAGE}"
}

# Pull an image and return "updated" or "unchanged".
# Writes pull output to the log file.
pull_and_check() {
    local image="$1"
    local before after
    before=$(get_image_id "$image")

    if [[ "$image" == localhost/* ]]; then
        log "Local image $image — not pulled"
        echo "unchanged"
        return
    fi

    log "Pulling: $image (current: ${before:0:12})"
    if ! podman pull "$image" >> "$LOGFILE" 2>&1; then
        log "WARNING: pull failed for $image — skipping (network issue?)"
        echo "unchanged"
        return
    fi

    after=$(get_image_id "$image")

    if [[ "$after" == "none" ]]; then
        log "WARNING: could not verify image digest after pull: $image"
        echo "unchanged"
    elif [[ "$before" == "none" || "$before" != "$after" ]]; then
        log "UPDATED: $image  ${before:0:12} -> ${after:0:12}"
        echo "updated"
    else
        log "Up to date: $image"
        echo "unchanged"
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────────

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must be run as root" >&2
    exit 1
fi

log "=== perfSONAR auto-update check started ==="

TESTPOINT_IMAGE=$(detect_testpoint_image)
log "Testpoint image: $TESTPOINT_IMAGE"

TESTPOINT_UPDATED=false
result=$(pull_and_check "$TESTPOINT_IMAGE")
[[ "$result" == "updated" ]] && TESTPOINT_UPDATED=true

# ── Stale-container check ──────────────────────────────────────────────────────
# The local tag may already have been updated by an earlier manual pull while
# the container still runs the old image.
if [[ "$TESTPOINT_UPDATED" == "false" ]]; then
    LATEST_TESTPOINT_ID=$(get_image_id "$TESTPOINT_IMAGE")
    RUNNING_TESTPOINT_ID=$(get_container_image_id "$TESTPOINT_CONTAINER")
    if [[ "$RUNNING_TESTPOINT_ID" != "none" && "$LATEST_TESTPOINT_ID" != "none" \
          && "$RUNNING_TESTPOINT_ID" != "$LATEST_TESTPOINT_ID" ]]; then
        log "Running container uses stale image ${RUNNING_TESTPOINT_ID:0:12} (latest: ${LATEST_TESTPOINT_ID:0:12}) — forcing restart"
        TESTPOINT_UPDATED=true
    fi
fi

# ── Certbot sidecar (long-running container from installs before 1.9.0) ────────
CERTBOT_UPDATED=false
if podman ps --format "{{.Names}}" 2>/dev/null | grep -qx "$CERTBOT_CONTAINER"; then
    CERTBOT_IMAGE=$(podman inspect "$CERTBOT_CONTAINER" --format "{{.ImageName}}" 2>/dev/null || true)
    if [[ -n "$CERTBOT_IMAGE" ]]; then
        result=$(pull_and_check "$CERTBOT_IMAGE")
        [[ "$result" == "updated" ]] && CERTBOT_UPDATED=true
    fi
fi

# ── Restarts ───────────────────────────────────────────────────────────────────
restart_unit() {
    if systemctl restart "$1"; then
        log "Restarted $1 successfully"
    else
        log "ERROR: failed to restart $1"
        return 1
    fi
}

rc=0
if [[ "$TESTPOINT_UPDATED" == "true" ]]; then
    log "New testpoint image — restarting $TESTPOINT_SERVICE"
    restart_unit "$TESTPOINT_SERVICE" || rc=1
fi
if [[ "$CERTBOT_UPDATED" == "true" ]]; then
    if systemctl cat "$CERTBOT_SERVICE" >/dev/null 2>&1; then
        log "New certbot image — restarting $CERTBOT_SERVICE"
        restart_unit "$CERTBOT_SERVICE" || rc=1
    else
        log "New certbot image, but $CERTBOT_SERVICE does not exist; restart the certbot container yourself"
    fi
fi
if [[ "$TESTPOINT_UPDATED" == "false" && "$CERTBOT_UPDATED" == "false" ]]; then
    log "All images up to date — no restart needed"
fi

log "=== perfSONAR auto-update check complete ==="
exit $rc
