#!/usr/bin/env bash
# perfSONAR-auto-enroll-psconfig.sh
# Purpose: Automatically enroll a perfSONAR testpoint container with OSG/WLCG pSConfig
# by deriving FQDNs from IPs listed in /etc/perfSONAR-multi-nic-config.conf (reverse DNS)
# and adding the corresponding auto URLs via `psconfig remote --configure-archives add`.
#
# Usage:
#   perfSONAR-auto-enroll-psconfig.sh [OPTIONS]
#
# Options:
#   -c <container>   Container name (default: perfsonar-testpoint)
#   -f <config>      Path to multi-NIC config (default: /etc/perfSONAR-multi-nic-config.conf)
#   -y               Assume yes; do not prompt for confirmation
#   -n               Dry-run; show FQDNs and planned URLs but do not enroll
#   -v               Verbose output
#   -h               Help
#
# Requirements:
#   - podman (preferred) or docker available
#   - running perfSONAR testpoint container accessible
#   - dig OR getent for reverse lookups
#
# Exit codes:
#   0 success
#   1 usage error
#   2 no FQDNs discovered
#   3 enrollment failures (one or more adds failed)

set -euo pipefail

CONTAINER="perfsonar-testpoint"
CONFIG="/etc/perfSONAR-multi-nic-config.conf"
ASSUME_YES=0
DRY_RUN=0
VERBOSE=0
USE_DOCKER=0

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
dbg() { [ "$VERBOSE" -eq 1 ] && echo "[DEBUG] $*" >&2 || true; }

usage() { sed -n '1,/^$/p' "$0"; }

while getopts ":c:f:ynvh" opt; do
  case $opt in
    c) CONTAINER="$OPTARG";;
    f) CONFIG="$OPTARG";;
    y) ASSUME_YES=1;;
    n) DRY_RUN=1;;
    v) VERBOSE=1;;
    h) usage; exit 0;;
    *) err "Unknown option: -$OPTARG"; usage; exit 1;;
  esac
done

if ! command -v podman >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1; then
    USE_DOCKER=1
    log "podman not found; falling back to docker"
  else
    err "Neither podman nor docker found in PATH"; exit 1
  fi
fi

if [ ! -f "$CONFIG" ]; then
  err "Config file not found: $CONFIG"; exit 1
fi

dbg "Parsing IPs from $CONFIG"
mapfile -t PS_IPS < <(awk -F= '/^NIC_(IPV4|IPV6)_ADDRS=/ {gsub(/"|\r|\n/,"",$2); split($2,a,/[ ,]/); for(i in a) if (a[i] != "" && a[i] != "-") print a[i]; }' "$CONFIG")

if [ ${#PS_IPS[@]} -eq 0 ]; then
  err "No IPs discovered in config; check NIC_*_ADDRS entries"; exit 2
fi

FQDNS=()
for ip in "${PS_IPS[@]}"; do
  dbg "Reverse lookup for $ip"
  name=""
  if command -v getent >/dev/null 2>&1; then
    name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}') || true
  fi
  if [ -z "$name" ] && command -v dig >/dev/null 2>&1; then
    name=$(dig +short -x "$ip" | head -n1) || true
  fi
  name=${name%.}
  if [ -n "$name" ]; then
    FQDNS+=("$name")
  else
    dbg "No PTR found for $ip (skipping)"
  fi
done

# Deduplicate while preserving order
UNIQ=()
for fq in "${FQDNS[@]}"; do
  skip=0
  for u in "${UNIQ[@]}"; do [ "$u" = "$fq" ] && skip=1 && break; done
  [ $skip -eq 0 ] && UNIQ+=("$fq")
done

if [ ${#UNIQ[@]} -eq 0 ]; then
  err "No FQDNs derived from reverse lookups"; exit 2
fi

log "Discovered FQDNs (order preserved):"
for fq in "${UNIQ[@]}"; do echo "  - $fq"; done

if [ $DRY_RUN -eq 1 ]; then
  echo "[DRY-RUN] Would enroll these auto URLs:" >&2
  for fq in "${UNIQ[@]}"; do
    echo "  https://psconfig.opensciencegrid.org/pub/auto/$fq" >&2
  done
  exit 0
fi

if [ $ASSUME_YES -eq 0 ]; then
  read -r -p "Proceed with enrollment (y/N)? " ans
  [ "$ans" = "y" ] || { err "Aborted by user"; exit 1; }
fi

RUNTIME="podman"
[ $USE_DOCKER -eq 1 ] && RUNTIME="docker"

FAILURES=0
for fq in "${UNIQ[@]}"; do
  url="https://psconfig.opensciencegrid.org/pub/auto/$fq"
  log "Enrolling $fq -> $url"
  if ! $RUNTIME exec "$CONTAINER" psconfig remote --configure-archives add "$url"; then
    err "Enrollment failed for $fq"; FAILURES=$((FAILURES+1))
  fi
done

log "Configured remotes:"; $RUNTIME exec "$CONTAINER" psconfig remote list || true

if [ $FAILURES -gt 0 ]; then
  err "$FAILURES enrollment(s) failed"; exit 3
fi

log "Enrollment complete"
