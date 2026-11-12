#!/usr/bin/env bash
set -uo pipefail

# perfSONAR-fix-apache-logrotate.sh
# ---------------------------------
# Make Apache's logs rotate inside the perfsonar-testpoint container.
#
# The testpoint image ships /usr/sbin/policy-rc.d (exit 101), so the
# 'invoke-rc.d apache2 reload' in logrotate's postrotate is silently refused.
# Apache then keeps writing to the renamed access.log.1 forever (about
# 100 MB/day of pScheduler traffic); the file is never compressed or expired
# and the container's /var/log volume grows until the host's /var is full.
#
# This script runs on the HOST and fixes the running container:
#   1. switches /etc/logrotate.d/apache2 to copytruncate (needs no reload);
#   2. if Apache is already writing to access.log.1, reloads Apache so it
#      reopens access.log.
#
# It changes nothing when both are already right, and always exits 0 so it can
# never stop a unit from starting.
#
# Who calls it:
#   - the compose-wrapper unit written by install-systemd-service.sh
#     (ExecStartPost), because only the testpoint-le-auto compose file starts
#     the container through testpoint-entrypoint-wrapper.sh, which applies the
#     same change at container start;
#   - update-perfsonar-deployment.sh --apply, for containers already running.
#
# Usage:
#   perfSONAR-fix-apache-logrotate.sh [--check] [--wait SECONDS] [CONTAINER]
#
#   --check         Report only; exit 1 if a fix is needed, 0 if not.
#   --wait SECONDS  Wait up to SECONDS for the container to be running
#                   (default 60; use 0 to not wait).
#   CONTAINER       Container name (default: perfsonar-testpoint).
#
# Version: 1.0.0 - 2026-11-11
# Author: OSG perfSONAR deployment tools
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

VERSION="1.0.0"
PROG_NAME="$(basename "$0")"
CONTAINER="perfsonar-testpoint"
CHECK_ONLY=false
WAIT=60
LOGROTATE_CONF="/etc/logrotate.d/apache2"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true; shift ;;
        --wait) WAIT="${2:-60}"; shift 2 ;;
        --version) echo "$PROG_NAME version $VERSION"; exit 0 ;;
        -h|--help) sed -n '4,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "$PROG_NAME: unknown option: $1" >&2; exit 0 ;;
        *) CONTAINER="$1"; shift ;;
    esac
done

RUNTIME=""
for r in podman docker; do
    if command -v "$r" >/dev/null 2>&1; then RUNTIME="$r"; break; fi
done
if [[ -z "$RUNTIME" ]]; then
    echo "$PROG_NAME: neither podman nor docker found; nothing to do"
    exit 0
fi

cexec() { "$RUNTIME" exec "$CONTAINER" "$@"; }

# Wait for the container to be running (a unit's ExecStartPost can run a moment
# before 'compose up -d' has it started).
waited=0
while [[ "$("$RUNTIME" inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]]; do
    if [[ "$waited" -ge "$WAIT" ]]; then
        echo "$PROG_NAME: container '$CONTAINER' is not running; nothing to do"
        exit 0
    fi
    sleep 2
    waited=$((waited + 2))
done

if ! cexec test -f "$LOGROTATE_CONF" 2>/dev/null; then
    echo "$PROG_NAME: $LOGROTATE_CONF not found in '$CONTAINER'; nothing to do"
    exit 0
fi

needs_fix=0

# 1. logrotate must use copytruncate
if cexec grep -q '^[[:space:]]*copytruncate' "$LOGROTATE_CONF" 2>/dev/null; then
    echo "$PROG_NAME: OK: Apache logrotate in '$CONTAINER' uses copytruncate"
else
    needs_fix=1
    if [[ "$CHECK_ONLY" == true ]]; then
        echo "$PROG_NAME: NEEDS FIX: Apache logrotate in '$CONTAINER' does not use copytruncate"
    elif cexec sed -i -e '/^[[:space:]]*create\b/d' \
            -e 's/^\([[:space:]]*\)delaycompress\b/&\n\1copytruncate/' "$LOGROTATE_CONF" \
         && cexec grep -q '^[[:space:]]*copytruncate' "$LOGROTATE_CONF"; then
        echo "$PROG_NAME: FIXED: Apache logrotate in '$CONTAINER' switched to copytruncate"
    else
        echo "$PROG_NAME: WARNING: could not patch $LOGROTATE_CONF in '$CONTAINER'"
    fi
fi

# 2. Apache must be writing to access.log, not to a rotated access.log.1.
#    (access.log empty while access.log.1 is newer means Apache still holds
#    the renamed file open.)
if cexec sh -c '[ ! -s /var/log/apache2/access.log ] && [ /var/log/apache2/access.log.1 -nt /var/log/apache2/access.log ]' 2>/dev/null; then
    needs_fix=1
    if [[ "$CHECK_ONLY" == true ]]; then
        echo "$PROG_NAME: NEEDS FIX: Apache in '$CONTAINER' is still writing to access.log.1"
    elif cexec systemctl reload apache2 >/dev/null 2>&1; then
        echo "$PROG_NAME: FIXED: reloaded Apache in '$CONTAINER'; it now writes to access.log"
    else
        echo "$PROG_NAME: WARNING: could not reload Apache in '$CONTAINER' (try: $RUNTIME exec $CONTAINER systemctl reload apache2)"
    fi
fi

if [[ "$CHECK_ONLY" == true && "$needs_fix" -eq 1 ]]; then
    exit 1
fi
exit 0
