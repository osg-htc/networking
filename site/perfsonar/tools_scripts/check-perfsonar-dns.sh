#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# check-perfsonar-dns.sh
# Quick forward/reverse DNS consistency check for addresses in
# /etc/perfSONAR-multi-nic-config.conf
#
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# Usage: ./check-perfsonar-dns.sh [--version|--help]
# Depends on: dig (bind-utils on EL, dnsutils on Debian/Ubuntu)

VERSION="1.0.0"
PROG_NAME="$(basename "$0")"

# Check for --version or --help flags
if [ "${1:-}" = "--version" ]; then
    echo "$PROG_NAME version $VERSION"
    exit 0
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<EOF
Usage: $PROG_NAME [--version|--help]

Validates forward and reverse DNS consistency for all IP addresses
configured in /etc/perfSONAR-multi-nic-config.conf.

Requires: dig (from bind-utils/dnsutils package)

Exit codes:
  0 - All DNS checks passed
  1 - One or more DNS checks failed
  2 - Config file not found
  3 - Neither dig nor host command available
EOF
    exit 0
fi

[ -f "/etc/perfSONAR-multi-nic-config.conf" ] || { echo "Config not found: /etc/perfSONAR-multi-nic-config.conf" >&2; exit 2; }
CONFIG=/etc/perfSONAR-multi-nic-config.conf
# shellcheck source=/etc/perfSONAR-multi-nic-config.conf
[ -f "$CONFIG" ] || { echo "Config not found: $CONFIG" >&2; exit 2; }

# Prefer dig but fall back to host if dig is not present
if command -v dig >/dev/null 2>&1; then
  RESOLVER=dig
elif command -v host >/dev/null 2>&1; then
  RESOLVER=host
else
  echo "Error: neither 'dig' nor 'host' found. Install bind-utils (EL) or dnsutils (Debian/Ubuntu)." >&2
  exit 3
fi

# shellcheck source=/etc/perfSONAR-multi-nic-config.conf
# shellcheck disable=SC1091
source "$CONFIG"

check_ip() {
  local ip_raw=$1
  local family=$2
  # strip CIDR if present
  local ip=${ip_raw%%/*}
  [ "$ip" = "-" ] && return 0

  if [ "$RESOLVER" = dig ]; then
    ptr=$(dig +short -x "$ip" | head -n1 || true)
  else
    ptr=$(host "$ip" 2>/dev/null | awk '/pointer/ {print $5; exit}' || true)
  fi

  if [ -z "$ptr" ]; then
    echo "MISSING PTR for $ip"
    return 1
  fi
  ptr=${ptr%.}

  if [ "$RESOLVER" = dig ]; then
    if [ "$family" = "4" ]; then
      fwd=$(dig +short A "$ptr" | tr '\n' ' ')
    else
      fwd=$(dig +short AAAA "$ptr" | tr '\n' ' ')
    fi
  else
    if [ "$family" = "4" ]; then
      fwd=$(host "$ptr" 2>/dev/null | awk '/has address/ {printf "%s ",$4} END{print ""}')
    else
      fwd=$(host -t AAAA "$ptr" 2>/dev/null | awk '/has IPv6 address/ {printf "%s ",$5} END{print ""}')
    fi
  fi

  if ! echo "$fwd" | grep -qw "$ip"; then
    echo "INCONSISTENT: PTR $ptr does not resolve back to $ip (resolved: ${fwd:-<none>})"
    return 1
  fi
  echo "OK: $ip ⇄ $ptr"
  return 0
}

errors=0
for ip in "${NIC_IPV4_ADDRS[@]:-}"; do
  if [ "$ip" != "-" ]; then
    check_ip "$ip" 4 || errors=$((errors+1))
  fi
done
for ip in "${NIC_IPV6_ADDRS[@]:-}"; do
  if [ "$ip" != "-" ]; then
    check_ip "$ip" 6 || errors=$((errors+1))
  fi
done

if (( errors > 0 )); then
  echo "DNS verification failed ($errors problem(s)). Fix DNS (forward/reverse) before running tests." >&2
  exit 1
fi

echo "DNS forward/reverse checks passed for configured addresses."
