#!/usr/bin/env bash
set -euo pipefail

# perfSONAR-health-monitor.sh
# ----------------------------
# Watches the health of the perfsonar-testpoint container and restarts the
# systemd service when the container is marked 'unhealthy'.
#
# Designed to run every 5 minutes via the perfsonar-health-monitor.timer
# systemd timer.  Works in conjunction with the compose-file healthcheck:
#
#   healthcheck:
#     test: ["CMD-SHELL", "pscheduler troubleshoot --quick || exit 1"]
#     interval: 60s
#     timeout: 30s
#     retries: 3
#     start_period: 120s
#
# The container healthcheck marks the container 'unhealthy' after 3
# consecutive failures (~3 minutes).  This watchdog then restarts the
# systemd service to trigger a full container recreation.
#
# Typical recovery time from service failure to restart:
#   ~3 min (3 failed health checks) + ≤5 min (next monitor run) ≈ ≤8 minutes
#
# Version: 1.0.0 - 2026-02-26
# Author: OSG perfSONAR deployment tools
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

VERSION="1.0.0"
CONTAINER="perfsonar-testpoint"
SERVICE="perfsonar-testpoint.service"
LOGFILE="/var/log/perfsonar-health-monitor.log"

log() { echo "$(date -Iseconds) [health-monitor v${VERSION}] $*" | tee -a "$LOGFILE"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

log "=== Health monitor check started ==="

# Retrieve the container's current health status from podman.
# Possible values: healthy | unhealthy | starting | (empty if no healthcheck)
health_status=$(podman inspect "$CONTAINER" \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
    2>/dev/null || echo "missing")

case "$health_status" in

    healthy)
        log "Container $CONTAINER is healthy — no action needed"
        ;;

    unhealthy)
        log "ALERT: Container $CONTAINER is unhealthy — restarting $SERVICE"
        if systemctl restart "$SERVICE"; then
            log "Restarted $SERVICE successfully"
        else
            log "ERROR: failed to restart $SERVICE (exit $?)"
        fi
        ;;

    starting)
        log "Container $CONTAINER health check is within start_period — no action"
        ;;

    no-healthcheck)
        # Container is running but has no healthcheck configured.
        log "Container $CONTAINER has no healthcheck defined — skipping"
        ;;

    missing | "")
        # podman inspect returned nothing: container doesn't exist.
        # Only restart if the managing service believes it should be running.
        if systemctl is-active "$SERVICE" &>/dev/null; then
            log "ALERT: Container $CONTAINER not found but $SERVICE is active — restarting"
            if systemctl restart "$SERVICE"; then
                log "Restarted $SERVICE successfully"
            else
                log "ERROR: failed to restart $SERVICE (exit $?)"
            fi
        else
            log "Container $CONTAINER not running and $SERVICE is inactive — no action"
        fi
        ;;

    *)
        log "WARNING: Unknown health status '$health_status' for $CONTAINER — no action taken"
        ;;

esac

log "=== Health monitor check complete ==="
