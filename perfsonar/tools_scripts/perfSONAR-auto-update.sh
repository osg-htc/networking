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
#   4. If any digest changed, restarts perfsonar-testpoint.service (which
#      manages both the testpoint and certbot containers via podman-compose or
#      direct podman run, depending on how the service was installed).
#
# Logs:
#   /var/log/perfsonar-auto-update.log  (appended on every run)
#
# Author: OSG perfSONAR deployment tools
# Version: 1.0.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

LOGFILE="/var/log/perfsonar-auto-update.log"

# Images managed by this host. Edit if you have pinned a specific digest tag.
TESTPOINT_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production"
CERTBOT_IMAGE="docker.io/certbot/certbot:latest"

# systemd service that starts/stops all perfSONAR containers on this host.
TESTPOINT_SERVICE="perfsonar-testpoint.service"

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

# Pull an image and return "updated" or "unchanged".
# Writes pull output to the log file.
pull_and_check() {
    local image="$1"
    local before after
    before=$(get_image_id "$image")

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

ANY_UPDATED=false

# ── Testpoint image ────────────────────────────────────────────────────────────
result=$(pull_and_check "$TESTPOINT_IMAGE")
[[ "$result" == "updated" ]] && ANY_UPDATED=true

# ── Certbot image (only if a certbot container exists on this host) ────────────
if podman ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^certbot$"; then
    result=$(pull_and_check "$CERTBOT_IMAGE")
    [[ "$result" == "updated" ]] && ANY_UPDATED=true
fi

# ── Stale-container check ──────────────────────────────────────────────────────
# Handle the case where the local image tag was already updated by a prior manual
# pull (pull says "up to date") but the running container is still using the old
# image digest. Compare running container's image ID vs the current local tag.
if [[ "$ANY_UPDATED" == "false" ]]; then
    LATEST_TESTPOINT_ID=$(get_image_id "$TESTPOINT_IMAGE")
    RUNNING_TESTPOINT_ID=$(get_container_image_id "perfsonar-testpoint")
    if [[ "$RUNNING_TESTPOINT_ID" != "none" && "$LATEST_TESTPOINT_ID" != "none" \
          && "$RUNNING_TESTPOINT_ID" != "$LATEST_TESTPOINT_ID" ]]; then
        log "Running container uses stale image ${RUNNING_TESTPOINT_ID:0:12} (latest: ${LATEST_TESTPOINT_ID:0:12}) — forcing restart"
        ANY_UPDATED=true
    fi
fi

# ── Restart if any image changed ───────────────────────────────────────────────
if [[ "$ANY_UPDATED" == "true" ]]; then
    log "New image(s) found — restarting $TESTPOINT_SERVICE"
    if systemctl restart "$TESTPOINT_SERVICE"; then
        log "Restarted $TESTPOINT_SERVICE successfully"
    else
        log "ERROR: failed to restart $TESTPOINT_SERVICE (exit $?)"
        exit 1
    fi
else
    log "All images up to date — no restart needed"
fi

log "=== perfSONAR auto-update check complete ==="
