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

# Persistent logging: try to write to /var/log, fall back to /tmp
LOGFILE="/var/log/perfsonar-auto-enroll-psconfig.log"
append_log() {
  local msg="$*"
  # ensure timestamped entry
  printf "%s %s\n" "$(date -Is)" "$msg" >> "$LOGFILE" 2>/dev/null || {
    # fallback to /tmp if /var/log not writable
    printf "%s %s\n" "$(date -Is)" "$msg" >> "/tmp/perfsonar-auto-enroll-psconfig.log" 2>/dev/null || true
  }
}

# Wrap log to also persist
logp() { log "$@"; append_log "$@"; }

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
mapfile -t PS_IPS < <(awk -F= '/^NIC_(IPV4|IPV6)_ADDRS=/ {gsub(/"|\(|\)|\r|\n/,"",$2); split($2,a,/[ ,]/); for(i in a) if (a[i] != "" && a[i] != "-") print a[i]; }' "$CONFIG")

if [ ${#PS_IPS[@]} -eq 0 ]; then
  err "No IPs discovered in config; check NIC_*_ADDRS entries"; exit 2
fi

FQDNS=()
for ip in "${PS_IPS[@]}"; do
  dbg "Reverse lookup for $ip"
  # strip CIDR if present (e.g. 192.0.2.10/24)
  ip_addr=${ip%%/*}

  # Only perform reverse lookups for public addresses.
  # Skip RFC1918 private IPv4 ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.
  # If the address contains a colon it's IPv6; we don't filter IPv6 here.
  if [[ "$ip_addr" != *:* ]]; then
    if [[ "$ip_addr" =~ ^10\. ]] || [[ "$ip_addr" =~ ^192\.168\. ]] || [[ "$ip_addr" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
      dbg "Skipping RFC1918 private IPv4 address $ip_addr"
      continue
    fi
  fi

  name=""
  if command -v dig >/dev/null 2>&1; then
    name=$(dig +short -x "$ip_addr" | head -n1) || true
  fi
  if [ -z "$name" ] && command -v getent >/dev/null 2>&1; then
    # getent may return multiple hostnames; we want the canonical one (field 2)
    name=$(getent hosts "$ip_addr" 2>/dev/null | awk '{print $2}') || true
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
for fq in "${UNIQ[@]}"; do
  echo "  - $fq"
  append_log "FQDN: $fq"
done

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
