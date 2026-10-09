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
# Version: 1.1.0 - 2026-10-09
#   - Rate-limit restarts: at most MAX_RESTARTS (default 3) within
#     RESTART_WINDOW seconds (default 3600). A problem a restart cannot fix
#     (e.g. the host has no DNS or NTP) would otherwise restart the testpoint
#     every few minutes and disrupt its measurements. When the limit is hit
#     the monitor logs an ALERT with what to check instead.
#   - Log the output of the last failed health check before restarting.
#   - Works with the health check that install-systemd-units.sh >= 1.5.0 adds
#     to the systemd unit (--health-cmd), as well as with the compose files.
# Version: 1.0.0 - 2026-02-26
# Author: OSG perfSONAR deployment tools
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

VERSION="1.1.0"
CONTAINER="perfsonar-testpoint"
SERVICE="perfsonar-testpoint.service"
LOGFILE="/var/log/perfsonar-health-monitor.log"
STATE_DIR="/var/lib/perfsonar-health-monitor"
STATE_FILE="$STATE_DIR/restarts"       # one epoch timestamp per restart
MAX_RESTARTS="${MAX_RESTARTS:-3}"
RESTART_WINDOW="${RESTART_WINDOW:-3600}"

log() { echo "$(date -Iseconds) [health-monitor v${VERSION}] $*" | tee -a "$LOGFILE"; }

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

log "=== Health monitor check started ==="

# Restart the service unless the rate limit has been reached.
# $1 = reason (logged)
restart_service() {
    local reason="$1" now recent=0 t
    now=$(date +%s)
    mkdir -p "$STATE_DIR"
    touch "$STATE_FILE"
    # Keep only restarts inside the window
    local kept=()
    while IFS= read -r t; do
        [[ "$t" =~ ^[0-9]+$ ]] || continue
        if (( now - t < RESTART_WINDOW )); then
            kept+=("$t")
        fi
    done < "$STATE_FILE"
    recent=${#kept[@]}
    printf '%s\n' "${kept[@]:-}" | grep -E '^[0-9]+$' > "$STATE_FILE" || true

    if (( recent >= MAX_RESTARTS )); then
        log "ALERT: $reason, but $recent restarts already happened in the last $((RESTART_WINDOW / 60)) min — NOT restarting again."
        log "       A restart is not fixing this. Check: podman exec $CONTAINER pscheduler troubleshoot --quick,"
        log "       host DNS (cat /etc/resolv.conf), time sync (chronyc tracking), journalctl -u $SERVICE"
        return 0
    fi

    log "ALERT: $reason — restarting $SERVICE (restart $((recent + 1)) of max $MAX_RESTARTS per $((RESTART_WINDOW / 60)) min)"
    if systemctl restart "$SERVICE"; then
        echo "$now" >> "$STATE_FILE"
        log "Restarted $SERVICE successfully"
    else
        log "ERROR: failed to restart $SERVICE (exit $?)"
    fi
}

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
        last_output=$(podman inspect "$CONTAINER" \
            --format '{{range .State.Health.Log}}{{.Output}}{{end}}' 2>/dev/null | tail -n 5 || true)
        if [[ -n "$last_output" ]]; then
            log "Last health check output:"
            while IFS= read -r line; do log "  | $line"; done <<< "$last_output"
        fi
        restart_service "Container $CONTAINER is unhealthy"
        ;;

    starting)
        log "Container $CONTAINER health check is within start_period — no action"
        ;;

    no-healthcheck)
        # Container is running but has no healthcheck configured.
        log "Container $CONTAINER has no healthcheck defined — skipping"
        log "  (regenerate the unit: install-systemd-units.sh --force, or update-perfsonar-deployment.sh --apply)"
        ;;

    missing | "")
        # podman inspect returned nothing: container doesn't exist.
        # Only restart if the managing service believes it should be running.
        if systemctl is-active "$SERVICE" &>/dev/null; then
            restart_service "Container $CONTAINER not found but $SERVICE is active"
        else
            log "Container $CONTAINER not running and $SERVICE is inactive — no action"
        fi
        ;;

    *)
        log "WARNING: Unknown health status '$health_status' for $CONTAINER — no action taken"
        ;;

esac

log "=== Health monitor check complete ==="
