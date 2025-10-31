#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source the script (functions are defined; main execution is deferred)
# shellcheck source=../perfSONAR-pbr-nm.sh
source "$DIR/perfSONAR-pbr-nm.sh"

fail() { echo "[FAIL] $*"; exit 1; }
pass() { echo "[PASS] $*"; }

# Prepare arrays with CR and NUL characters embedded
# Use printf to create values with control characters
CR=$'\r'
NUL=$(printf '\000')

NIC_NAMES=("eth0")
NIC_IPV4_ADDRS=("$(printf '192.0.2.10%s' "$CR")")
NIC_IPV4_PREFIXES=("/24")
NIC_IPV4_GWS=("$(printf '192.0.2.1%s' "$CR")")
NIC_IPV4_ADDROUTE=("-")
NIC_IPV6_ADDRS=("-")
NIC_IPV6_PREFIXES=("-")
NIC_IPV6_GWS=("-")
DEFAULT_ROUTE_NIC="$(printf 'eth0%s' "$CR")"

# Call sanitize_config to strip CR and NUL
sanitize_config

# Assert values were cleaned
[ "${NIC_IPV4_ADDRS[0]}" = "192.0.2.10" ] || fail "NIC_IPV4_ADDRS not sanitized: '${NIC_IPV4_ADDRS[0]}'"
[ "${NIC_IPV4_GWS[0]}" = "192.0.2.1" ] || fail "NIC_IPV4_GWS not sanitized: '${NIC_IPV4_GWS[0]}'"
[ "$DEFAULT_ROUTE_NIC" = "eth0" ] || fail "DEFAULT_ROUTE_NIC not sanitized: '$DEFAULT_ROUTE_NIC'"

pass "sanitize_config removed CR/NUL characters"

echo "Sanitize tests passed."
