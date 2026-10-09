#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# check-perfsonar-dns.sh
# Quick forward/reverse DNS consistency check for addresses in
# /etc/perfSONAR-multi-nic-config.conf
#
# Version: 1.1.0 - 2026-10-08
#   - Add --check-resolver / --fix-resolver: detect the glibc parallel A/AAAA
#     query stall (one reply dropped, typically by a stateful firewall /
#     conntrack race, so every dual-stack lookup waits for the 5 s resolver
#     timeout). pScheduler gives up on name lookups after 2-3 s, so
#     'pscheduler troubleshoot' reports "Not resolvable or timed out" /
#     "Resolving timed out after 3000 milliseconds". The fix sets
#     'single-request-reopen' persistently through NetworkManager. Before
#     re-applying a connection it makes sure the profile itself holds DNS
#     servers (copying the ones in use if it has none), because re-applying a
#     static profile without DNS removes the DHCP-learned servers.
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# Usage: ./check-perfsonar-dns.sh [--check-resolver|--fix-resolver [--host FQDN] [--no-restart]] [--version|--help]
# Depends on: dig (bind-utils on EL, dnsutils on Debian/Ubuntu); python3 and
#             nmcli for the resolver checks

VERSION="1.1.0"
PROG_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage: $PROG_NAME [--version|--help]
       $PROG_NAME --check-resolver [--host FQDN] [--threshold SECONDS]
       $PROG_NAME --fix-resolver   [--host FQDN] [--threshold SECONDS] [--no-restart]

Default mode: validates forward and reverse DNS consistency for all IP
addresses configured in /etc/perfSONAR-multi-nic-config.conf.

--check-resolver
    Time a dual-stack (A + AAAA) lookup of this host's FQDN the way
    pScheduler does it. If it is slow, repeat it with the glibc option
    'single-request-reopen' to tell the parallel-query stall (one of the two
    replies dropped, e.g. by a stateful firewall) from a generally slow DNS.
    Makes no changes.

--fix-resolver
    As --check-resolver, and if the parallel-query stall is found, add
    'single-request-reopen' to the DNS options of the active NetworkManager
    connections (persistent), reapply them, verify, and restart
    perfsonar-testpoint.service if it is running (the container copies
    /etc/resolv.conf when it starts). Idempotent.

Options:
  --host FQDN         Name to look up (default: hostname -f)
  --threshold SECS    A lookup slower than this is a stall (default: 1.5;
                      pScheduler gives up after 2)
  --no-restart        Do not restart perfsonar-testpoint after a fix

Requires: dig (bind-utils/dnsutils); python3 and nmcli for resolver modes.

Exit codes:
  0 - All checks passed (resolver modes: lookup fast, nothing to do)
  1 - One or more DNS checks failed (resolver modes: stall found but not
      fixed — check mode, or the fix did not help)
  2 - Config file not found / invalid arguments
  3 - Required tool missing (dig/host, python3 or nmcli)
  5 - Resolver modes: lookups are slow even with single-request-reopen
      (not the parallel-query stall; check the nameservers)
  10 - --fix-resolver: stall found and fixed
EOF
}

MODE="consistency"
LOOKUP_HOST=""
THRESHOLD="1.5"
NO_RESTART=false

while [ $# -gt 0 ]; do
    case "$1" in
        --version) echo "$PROG_NAME version $VERSION"; exit 0 ;;
        --help|-h) usage; exit 0 ;;
        --check-resolver) MODE="check-resolver"; shift ;;
        --fix-resolver) MODE="fix-resolver"; shift ;;
        --host) LOOKUP_HOST="${2:-}"; shift 2 ;;
        --threshold) THRESHOLD="${2:-}"; shift 2 ;;
        --no-restart) NO_RESTART=true; shift ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# --- Resolver (parallel A/AAAA query stall) checks --------------------------

# Print seconds taken by an AF_UNSPEC getaddrinfo() of $1 (A + AAAA, no
# AI_ADDRCONFIG), i.e. exactly what pScheduler's dns_resolve() does.
# Extra environment (e.g. RES_OPTIONS) is inherited by python3.
time_lookup() {
    python3 -I -c '
import socket, sys, time
t = time.time()
try:
    socket.getaddrinfo(sys.argv[1], 0)
except Exception:
    pass
print("%.3f" % (time.time() - t))
' "$1"
}

is_slow() {
    # $1 = seconds (float); compare against THRESHOLD
    python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' "$1" "$THRESHOLD"
}

# Active NetworkManager connections (name<TAB>device) excluding loopback and
# container/virtual bridges. Prefer the ones that carry DNS servers.
nm_dns_connections() {
    local name dev type dns all=()
    while IFS=: read -r name dev type; do
        [ -z "$dev" ] && continue
        case "$type" in
            loopback|bridge|tun|veth|wireguard|vlan-podman) continue ;;
        esac
        case "$dev" in
            lo|podman*|cni*|veth*|docker*) continue ;;
        esac
        all+=("$name	$dev")
        dns=$(nmcli -g IP4.DNS,IP6.DNS device show "$dev" 2>/dev/null | tr -d '\n' || true)
        if [ -n "$dns" ]; then
            printf '%s\t%s\n' "$name" "$dev"
            DNS_CONN_FOUND=1
        fi
    done < <(nmcli -t -f NAME,DEVICE,TYPE connection show --active 2>/dev/null)
    if [ "${DNS_CONN_FOUND:-0}" -eq 0 ]; then
        printf '%s\n' "${all[@]}"
    fi
}

restart_testpoint_if_running() {
    [ "$NO_RESTART" = true ] && { echo "  (--no-restart) Restart perfsonar-testpoint later so the container picks up /etc/resolv.conf"; return 0; }
    if [ -f /etc/systemd/system/perfsonar-testpoint.service ] && \
       systemctl is-active --quiet perfsonar-testpoint.service 2>/dev/null; then
        echo "  Restarting perfsonar-testpoint.service (the container copies /etc/resolv.conf at start)..."
        systemctl restart perfsonar-testpoint.service || echo "  WARNING: restart failed; run: systemctl restart perfsonar-testpoint" >&2
    fi
}

resolver_mode() {
    command -v python3 >/dev/null 2>&1 || { echo "Error: python3 is required for $MODE" >&2; exit 3; }
    local host t1 t2
    host="${LOOKUP_HOST:-$(hostname -f 2>/dev/null || hostname)}"

    echo "Resolver check: dual-stack lookup of $host (threshold ${THRESHOLD}s)"
    if grep -Eq '^[[:space:]]*options.*single-request(-reopen)?' /etc/resolv.conf 2>/dev/null; then
        echo "  /etc/resolv.conf already sets single-request(-reopen)"
    fi
    t1=$(time_lookup "$host")
    echo "  getaddrinfo (A+AAAA):                     ${t1}s"
    if ! is_slow "$t1"; then
        echo "OK: lookups are fast; nothing to do."
        return 0
    fi
    t2=$(RES_OPTIONS="single-request-reopen" time_lookup "$host")
    echo "  getaddrinfo with single-request-reopen:   ${t2}s"
    if is_slow "$t2"; then
        echo "SLOW DNS: lookups take ${t1}s even with single-request-reopen." >&2
        echo "  This is not the parallel-query stall. Check the nameservers in /etc/resolv.conf" >&2
        echo "  (e.g. 'dig $host @<server>' for each) and their reachability." >&2
        return 5
    fi

    echo "STALL: parallel A/AAAA queries lose a reply (lookups wait for the 5 s resolver"
    echo "  timeout; pScheduler gives up after 2-3 s). Fix: resolver option single-request-reopen."
    if [ "$MODE" = "check-resolver" ]; then
        echo "  Run: $PROG_NAME --fix-resolver"
        return 1
    fi

    command -v nmcli >/dev/null 2>&1 || {
        echo "Error: nmcli not found; add 'options single-request-reopen' to your resolver configuration manually." >&2
        exit 3
    }
    if ! head -n 3 /etc/resolv.conf 2>/dev/null | grep -q 'NetworkManager'; then
        echo "WARNING: /etc/resolv.conf does not appear to be written by NetworkManager;" >&2
        echo "  the NetworkManager change may not take effect. Check 'ls -l /etc/resolv.conf'." >&2
    fi

    local conn dev opts prof live v4 v6 s changed=0
    while IFS=$'\t' read -r conn dev; do
        [ -z "$conn" ] && continue
        opts=$(nmcli -g ipv4.dns-options connection show "$conn" 2>/dev/null || true)
        if echo "$opts" | grep -qw 'single-request-reopen'; then
            echo "  $conn ($dev): single-request-reopen already set"
            continue
        fi

        # Safeguard: re-applying a profile replaces the device's DNS with the
        # profile's. A static profile with no DNS of its own (DNS learned from
        # DHCP before it was made static) would leave the host with none.
        prof=$(nmcli -g ipv4.dns,ipv6.dns connection show "$conn" 2>/dev/null | tr -d '[:space:]' || true)
        if [ -z "$prof" ]; then
            live=$( { nmcli -g IP4.DNS device show "$dev" 2>/dev/null; nmcli -g IP6.DNS device show "$dev" 2>/dev/null; } \
                | tr '|,' '\n\n' | sed -e 's/\\:/:/g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true)
            if [ -z "$live" ]; then
                echo "  $conn ($dev): profile and device have no DNS servers; skipping (re-applying would not help)." >&2
                echo "    Set them first, e.g.: nmcli connection modify \"$conn\" ipv4.dns \"<server1> <server2>\"" >&2
                continue
            fi
            v4=""; v6=""
            for s in $live; do
                case "$s" in
                    *:*) v6="${v6:+$v6 }$s" ;;
                    *.*) v4="${v4:+$v4 }$s" ;;
                esac
            done
            echo "  $conn ($dev): profile has no DNS servers; saving the ones in use (${v4}${v6:+ $v6}) first"
            if [ -n "$v4" ]; then
                nmcli connection modify "$conn" ipv4.dns "$v4" || { echo "  WARNING: could not save ipv4.dns on $conn; skipping" >&2; continue; }
            fi
            if [ -n "$v6" ]; then
                nmcli connection modify "$conn" ipv6.dns "$v6" || echo "  WARNING: could not save ipv6.dns on $conn" >&2
            fi
        fi
        echo "  $conn ($dev): adding ipv4.dns-options single-request-reopen"
        if ! nmcli connection modify "$conn" +ipv4.dns-options single-request-reopen; then
            echo "  WARNING: nmcli modify failed for $conn" >&2
            continue
        fi
        # reapply updates DNS settings without taking the link down;
        # fall back to 'connection up' (brief interruption) if unsupported.
        if ! nmcli device reapply "$dev" >/dev/null 2>&1; then
            echo "  device reapply not possible for $dev; re-activating $conn (brief link interruption)"
            nmcli connection up "$conn" >/dev/null || echo "  WARNING: could not re-activate $conn" >&2
        fi
        changed=1
    done < <(nm_dns_connections)

    sleep 2
    if grep -Eq '^[[:space:]]*options.*single-request-reopen' /etc/resolv.conf 2>/dev/null; then
        echo "  /etc/resolv.conf now contains: $(grep -E '^[[:space:]]*options' /etc/resolv.conf | head -n1)"
    else
        echo "WARNING: single-request-reopen not visible in /etc/resolv.conf yet" >&2
    fi

    t1=$(time_lookup "$host")
    echo "  getaddrinfo (A+AAAA) after fix:           ${t1}s"
    if is_slow "$t1"; then
        echo "FAILED: lookups are still slow after the change." >&2
        return 1
    fi
    echo "FIXED: dual-stack lookups are fast."
    if [ "$changed" -eq 1 ]; then
        restart_testpoint_if_running
    fi
    return 10
}

if [ "$MODE" != "consistency" ]; then
    rc=0
    resolver_mode || rc=$?
    exit "$rc"
fi

# --- Forward/reverse consistency checks (default mode) ----------------------

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
