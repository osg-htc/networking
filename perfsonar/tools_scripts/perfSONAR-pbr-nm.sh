#!/bin/bash
#
# Multi-NIC perfSONAR NetworkManager Configuration Script
# ------------------------------------------------------
# Purpose:
#   Configure static IPv4/IPv6 addressing, create per-NIC routing tables,
#   and apply source-basedrouting rules via NetworkManager (nmcli).
#
# Contract (inputs / outputs):
#   - Input: `/etc/perfSONAR-multi-nic-config.conf` defines parallel arrays that
#     describe NIC names, addresses, prefixes and gateways used by the script.
#   - Output: Writes/overwrites NetworkManager connection files under
#     `/etc/NetworkManager/system-connections/`. May also create routing table
#     mappings under `/etc/iproute2/rt_tables.d/` or append `/etc/iproute2/rt_tables`.
#   - Safety: This script will REMOVE ALL existing NetworkManager connections
#     unless you run it in dry-run mode. Backups are created automatically.
#
# Important notes / success criteria:
#   - Run as root on a machine managed by NetworkManager. Test in a VM/console
#     before running on production hardware. Use --dry-run to preview actions.
#   - One NIC should be designated as the DEFAULT_ROUTE_NIC; others will be
#     configured with their own routing tables and source-based rules.
#
# Author: Shawn McKee - University of Michigan <smckee@umich.edu>
# Version: 1.0.0 - Oct 30 2025

# -------- BEGIN CONFIGURATION --------
# Location of the external config file describing NIC arrays used below.
CONFIG_FILE="/etc/perfSONAR-multi-nic-config.conf"
# If the file does not exist the script can auto-generate an example or a
# detected config (use --generate-config-auto or --generate-config-debug).

# Enable strict mode for safer scripting. Note: some portable shells lack
# `local -n` nameref support - this script requires bash.
set -euo pipefail
IFS=$'\n\t'

# -------- Color Output (for terminal messages) --------
# Small visual hints when printing warnings/summary to interactive console/log.
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
# -----------------------------------------------------

# -------- Logging and runtime flags (defaults) --------
# LOG_FILE: where the script appends time-stamped entries. Ensure write perms
# (the script will attempt to append to this file; running as root is expected).
LOG_FILE="/var/log/perfSONAR-multi-nic-config.log"
# Runtime flags: set by CLI parsing later in the main section.
DRY_RUN=false        # when true: print actions and do not make changes
AUTO_YES=false       # when true: skip interactive confirmation
DEBUG=false          # when true: run commands under bash -x for verbose output

# CLI-controlled behavior defaults
RUN_SHELLCHECK=false
GENERATE_CONFIG_AUTO=true
GENERATE_CONFIG_DEBUG=false

# -----------------------------------------------------

# ----------------- Function definitions follow -----------------
usage() {
    cat <<'EOF'
Usage: $0 [OPTIONS]

Options:
  --help                      Show this help message
  --dry-run                   Print actions without making changes
  --generate-config-auto      Auto-generate /etc/perfSONAR-multi-nic-config.conf from this host and exit
  --generate-config-debug     Same as --generate-config-auto but runs in dry-run/debug mode and prints internal state
  --shellcheck                Enable running shellcheck before executing (default: disabled)
  --yes                       Skip the interactive confirmation prompt
  --debug                     Run commands in debug mode (bash -x)
EOF
}

# CLI parsing is deferred to the MAIN section (end of file) so that all helper
# functions are defined before any of them may be invoked by flags.

log() {
    # Timestamped logging helper (appends to LOG_FILE). Uses `tee -a` so
    # the message is written both to stdout and to the configured log file.
    local ts
    ts="$(date +'%Y-%m-%d %H:%M:%S')"
    # shellcheck disable=SC2086
    printf '%s %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

run_cmd() {
    # Central command runner for all external commands that may modify
    # system state. This wrapper provides three responsibilities:
    #  1) Log a safely escaped, human-readable representation of the
    #     command for auditing (cmd_repr).
    #  2) Support DRY_RUN mode: when enabled, the command is NOT executed.
    #  3) Execute the command while preserving argument boundaries so that
    #     multi-word arguments (for example nmcli route strings) are passed
    #     intact to the invoked program.
    #
    # Security note: run_cmd executes the provided arguments directly. Do
    # not pass untrusted input that requires shell evaluation. This wrapper
    # intentionally avoids building a single shell command string for
    # execution to prevent re-parsing/quoting issues.
    # shellcheck disable=SC2086
    local cmd_repr
    cmd_repr="$(printf '%q ' "$@")"
    log "CMD: $cmd_repr"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $cmd_repr"
        return 0
    fi

    if [ "$DEBUG" = true ]; then
        # Use bash -x to show a trace; 'exec "$@"' preserves arguments.
        bash -x -c 'exec "$@"' -- "$@"
    else
        # Execute command directly to preserve argv semantics.
        "$@"
    fi
}

# Simple helper: return 0 if running interactively on a TTY
is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# Return 0 if the provided gateway IP belongs to the network defined by
# address+prefix. Supports IPv4 and IPv6 using Python's ipaddress module
# when available. Falls back to a permissive 'false' when python3 is missing.
in_same_subnet() {
    local gw=$1 addr=$2 prefix=$3
    [ -z "$gw" ] && return 1
    [ "$addr" = "-" ] && return 1
    [ "$prefix" = "-" ] && return 1
    # prefix is like "/24" or "/64"; ensure no duplicate slash
    local cidr
    cidr="${addr}${prefix}"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$gw" "$cidr" <<'PY'
import sys, ipaddress
gw = sys.argv[1]
cidr = sys.argv[2]
try:
    net = ipaddress.ip_network(cidr, strict=False)
    gip = ipaddress.ip_address(gw)
    sys.exit(0 if gip in net else 1)
except Exception:
    sys.exit(1)
PY
        return $?
    fi
    # Without python3, do a conservative fallback: return non-zero (not in subnet)
    return 1
}

# Persist the current in-memory config arrays back to $CONFIG_FILE
# Writes a temporary file and atomically moves it into place.
save_config_to_file() {
    local target=${1:-"$CONFIG_FILE"}
    local TMPFILE
    TMPFILE="/tmp/perfsonar-save-config-$$.conf"

    {
        echo "# perfSONAR multi-NIC configuration"
        echo "# Saved: $(date)"
        echo ""

        _print_arr() {
            local name="$1"; shift
            printf '%s=(\n' "$name" >> "$TMPFILE"
            for v in "$@"; do
                printf '  "%s"\n' "$v" >> "$TMPFILE"
            done
            printf ')\n\n' >> "$TMPFILE"
        }

        _print_arr NIC_NAMES "${NIC_NAMES[@]}"
        _print_arr NIC_IPV4_ADDRS "${NIC_IPV4_ADDRS[@]}"
        _print_arr NIC_IPV4_PREFIXES "${NIC_IPV4_PREFIXES[@]}"
        _print_arr NIC_IPV4_GWS "${NIC_IPV4_GWS[@]}"
        _print_arr NIC_IPV4_ADDROUTE "${NIC_IPV4_ADDROUTE[@]}"
        _print_arr NIC_IPV6_ADDRS "${NIC_IPV6_ADDRS[@]}"
        _print_arr NIC_IPV6_PREFIXES "${NIC_IPV6_PREFIXES[@]}"
        _print_arr NIC_IPV6_GWS "${NIC_IPV6_GWS[@]}"

        printf 'DEFAULT_ROUTE_NIC="%s"\n' "${DEFAULT_ROUTE_NIC:-}" >> "$TMPFILE"
    }

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN: would write updated config to $target"
        [ -f "$TMPFILE" ] && rm -f "$TMPFILE"
        return 0
    fi

    run_cmd mv "$TMPFILE" "$target" || handle_error "Failed to persist updated configuration to $target"
    run_cmd chmod 0644 "$target" || true
    run_cmd chown root:root "$target" || true
}

# -------- Error handling and rollback helpers --------
# handle_error: centralized failure path. Logs error, attempts rollback,
# and exits with a non-zero status. Use this where a hard failure should
# abort the script and try to restore previous state (if backups exist).
handle_error() {
    local msg=${1:-"Unknown error"}
    log "ERROR: $msg"
    # Attempt rollback if a backup exists and we haven't already rolled back
    if [ "${ROLLBACK_DONE:-false}" != "true" ]; then
        rollback "Error encountered: $msg"
    fi
    exit "${2:-1}"
}

rollback() {
    # Restore backed-up NetworkManager connections if a backup directory exists
    local reason=${1:-"manual rollback"}
    if [ -z "${BACKUP_DIR:-}" ] || [ ! -d "${BACKUP_DIR}" ]; then
        log "No backup available to rollback: $reason"
        ROLLBACK_DONE=true
        return 0
    fi

    log "Attempting rollback using backup at $BACKUP_DIR ($reason)"
    if [ "$DRY_RUN" = true ]; then
        log "Dry-run mode: would restore $BACKUP_DIR to /etc/NetworkManager/system-connections/"
        ROLLBACK_DONE=true
        return 0
    fi

    # Restore using rsync (safer than shell-globbed cp)
    run_cmd rsync -a -- "$BACKUP_DIR"/ /etc/NetworkManager/system-connections/ || log "Rollback: copy failed"
    run_cmd chmod -R 0600 /etc/NetworkManager/system-connections/* || true
    run_cmd chown -R root:root /etc/NetworkManager/system-connections/* || true
    # Reload NetworkManager connections; if reload fails attempt restart and
    # log if both operations fail. Use explicit if/then to avoid shellcheck
    # warning about conditional chaining.
    if ! run_cmd nmcli connection reload; then
        if ! run_cmd systemctl restart NetworkManager; then
            log "Rollback: failed to reload/restart NetworkManager"
        fi
    fi
    log "Rollback complete (attempted)."
    ROLLBACK_DONE=true
}

# Trap unexpected errors to surface a line number and log exit. The ERR
# trap will call handle_error which attempts a rollback if possible.
trap 'handle_error "Unexpected error at line $LINENO"' ERR
# The EXIT trap logs script termination (success or failure). Because ERR
# calls exit, this will also fire after an error path.
trap 'log "Script finished at $(date)"' EXIT

# NOTE: All helper functions are defined above. The script's runtime actions
# (logging start, parsing CLI, generating configs, and applying changes)
# are performed in the MAIN section near the end of this file so that
# functions are available when invoked. See the "---- MAIN SCRIPT ----" marker.

# -------- Static analysis step (optional) --------
# run_shellcheck: run shellcheck -x on this script if available and enabled.
# This is a convenience to catch common scripting mistakes before changes are
# applied. Users may skip static analysis with --no-shellcheck.
run_shellcheck() {
    if [ "${RUN_SHELLCHECK:-false}" != "true" ]; then
        log "Shellcheck disabled (enable with --shellcheck)."
        return 0
    fi
    if ! command -v shellcheck >/dev/null 2>&1; then
        log "shellcheck not installed; skipping static lint step."
        log "(Install via 'dnf -y install shellcheck' to enable this check.)"
        return 0
    fi

    log "Running shellcheck on $0"
    # Run shellcheck and capture output
    local sc_out
    if ! sc_out=$(shellcheck -x -f gcc "$0" 2>&1); then
        log "shellcheck reported issues; please review and fix before proceeding. Output:" 
        echo "$sc_out" | tee -a "$LOG_FILE"
        exit 2
    else
        log "shellcheck passed with no reported issues."
    fi
}

# Note: shellcheck invocation is performed in the main section after
# CLI parsing so user flags (like --shellcheck / --no-shellcheck) are respected.

# -------- Auto-config generator --------
# generate_config_from_system:
#   - Detects physical NICs, extracts primary IPv4/IPv6 addresses, prefixes,
#     and gateways, and writes an auto-generated config file to $CONFIG_FILE
#     (or prints a preview in debug/dry-run mode).
#   - Side effect (export): sets DEFAULT_ROUTE_NIC in the current shell so
#     the caller can inspect which interface was chosen.
generate_config_from_system() {
    log "Auto-detecting network interfaces to generate $CONFIG_FILE"

    local -a NICS=()
    # Prefer nmcli if available to get known devices; fallback to ip
    if command -v nmcli >/dev/null 2>&1; then
        # select physical devices ignoring UNKNOWN/LOOPBACK by checking ip later
        mapfile -t NICS < <(nmcli -t -f DEVICE device | awk -F: '{print $1}' | grep -v '^$')
    else
        mapfile -t NICS < <(ip -o link show | awk -F': ' '{print $2}')
    fi

    local -a NIC_NAMES=()
    local -a NIC_IPV4_ADDRS=()
    local -a NIC_IPV4_PREFIXES=()
    local -a NIC_IPV4_GWS=()
    local -a NIC_IPV4_ADDROUTE=()
    local -a NIC_IPV6_ADDRS=()
    local -a NIC_IPV6_PREFIXES=()
    local -a NIC_IPV6_GWS=()

    # detect system default route device for DEFAULT_ROUTE_NIC
    local DEFAULT_ROUTE_NIC
    DEFAULT_ROUTE_NIC=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}') || true
    [ -z "$DEFAULT_ROUTE_NIC" ] && DEFAULT_ROUTE_NIC=""

    for dev in "${NICS[@]:-}"; do
        # skip obvious non-physical devices
        case "$dev" in
            lo|docker*|veth*|virbr*|br-*|tun*|tap*|wg*|wl*|tmp*)
                continue
                ;;
        esac

        # gather primary IPv4 (first) and prefix
        local v4 v6
        v4=$(ip -o -4 addr show dev "$dev" scope global 2>/dev/null | awk '{print $4; exit}') || true
        if [ -n "$v4" ]; then
            local ipv4_addr=${v4%/*}
            local ipv4_prefix="/${v4#*/}"
        else
            ipv4_addr="-"
            ipv4_prefix="-"
        fi

        # gather primary IPv6 (global) and prefix
        v6=$(ip -o -6 addr show dev "$dev" scope global 2>/dev/null | awk '{print $4; exit}') || true
        if [ -n "$v6" ]; then
            local ipv6_addr=${v6%/*}
            local ipv6_prefix="/${v6#*/}"
        else
            ipv6_addr="-"
            ipv6_prefix="-"
        fi

        # Detect gateways associated with this device (if any).
        # Prefer configured values from NetworkManager connection settings,
        # then fall back to current kernel default routes scoped to this dev.
        local gw4 gw6 connname gtmp
        gw4=""; gw6=""
        if command -v nmcli >/dev/null 2>&1; then
            connname=$(nmcli -t -f GENERAL.CONNECTION device show "$dev" 2>/dev/null | awk -F: '{print $2}') || true
            if [ -n "$connname" ] && [ "$connname" != "--" ]; then
                gtmp=$(nmcli -t -g ipv4.gateway connection show "$connname" 2>/dev/null | tr -d '\r') || true
                if [ -n "$gtmp" ] && [ "$gtmp" != "--" ]; then
                    gw4="$gtmp"; log "Guessed IPv4 gateway for $dev from NM connection $connname: $gw4"
                fi
                gtmp=$(nmcli -t -g ipv6.gateway connection show "$connname" 2>/dev/null | tr -d '\r') || true
                if [ -n "$gtmp" ] && [ "$gtmp" != "--" ]; then
                    gw6="$gtmp"; log "Guessed IPv6 gateway for $dev from NM connection $connname: $gw6"
                fi
            fi
        fi

        # If not found in NM connection settings, look at kernel default routes per dev
        if [ -z "$gw4" ] || ! is_ipv4 "${gw4:-}"; then
            gtmp=$(ip route show default dev "$dev" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}') || true
            if [ -n "$gtmp" ] && is_ipv4 "$gtmp"; then
                gw4="$gtmp"; log "Guessed IPv4 gateway for $dev from kernel default route: $gw4"
            fi
        fi
        if [ -z "$gw6" ] || ! is_ipv6 "${gw6:-}"; then
            gtmp=$(ip -6 route show default dev "$dev" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}') || true
            if [ -n "$gtmp" ] && is_ipv6 "$gtmp"; then
                gw6="$gtmp"; log "Guessed IPv6 gateway for $dev from kernel default route: $gw6"
            fi
        fi

        [ -z "$gw4" ] && gw4="-"
        [ -z "$gw6" ] && gw6="-"

        # only include NICs that have at least one address or are the default device
        # Use DEFAULT_ROUTE_NIC detected above to include the interface that
        # currently holds the system default route even if it lacks an
        # address detected above.
        if [ "$ipv4_addr" = "-" ] && [ "$ipv6_addr" = "-" ] && [ "$dev" != "$DEFAULT_ROUTE_NIC" ]; then
            continue
        fi

        NIC_NAMES+=("$dev")
        NIC_IPV4_ADDRS+=("$ipv4_addr")
        NIC_IPV4_PREFIXES+=("$ipv4_prefix")
        NIC_IPV4_GWS+=("$gw4")
        NIC_IPV4_ADDROUTE+=("-")
        NIC_IPV6_ADDRS+=("$ipv6_addr")
        NIC_IPV6_PREFIXES+=("$ipv6_prefix")
        NIC_IPV6_GWS+=("$gw6")
    done

    # Attempt to reuse any known gateways for NICs missing a gateway when
    # those gateways belong to the NIC's subnet. This helps complete configs
    # on systems where only one NIC currently has the default route set.
    {
        # Build candidate lists
        declare -a CAND_GW4=() CAND_GW6=()
        for g in "${NIC_IPV4_GWS[@]}"; do [ "$g" != "-" ] && is_ipv4 "$g" && CAND_GW4+=("$g"); done
        for g in "${NIC_IPV6_GWS[@]}"; do [ "$g" != "-" ] && is_ipv6 "$g" && CAND_GW6+=("$g"); done
        # De-duplicate
        if ((${#CAND_GW4[@]})); then mapfile -t CAND_GW4 < <(printf '%s\n' "${CAND_GW4[@]}" | awk '!seen[$0]++'); fi
        if ((${#CAND_GW6[@]})); then mapfile -t CAND_GW6 < <(printf '%s\n' "${CAND_GW6[@]}" | awk '!seen[$0]++'); fi

        # Fill missing per NIC if suitable
        for i in "${!NIC_NAMES[@]}"; do
            if [ "${NIC_IPV4_ADDRS[$i]}" != "-" ] && { [ -z "${NIC_IPV4_GWS[$i]}" ] || [ "${NIC_IPV4_GWS[$i]}" = "-" ]; }; then
                for g in "${CAND_GW4[@]:-}"; do
                    if in_same_subnet "$g" "${NIC_IPV4_ADDRS[$i]}" "${NIC_IPV4_PREFIXES[$i]}"; then
                        NIC_IPV4_GWS[$i]="$g"
                        log "Reused IPv4 gateway $g for ${NIC_NAMES[$i]} based on subnet match"
                        break
                    fi
                done
            fi
            if [ "${NIC_IPV6_ADDRS[$i]}" != "-" ] && { [ -z "${NIC_IPV6_GWS[$i]}" ] || [ "${NIC_IPV6_GWS[$i]}" = "-" ]; }; then
                for g in "${CAND_GW6[@]:-}"; do
                    if in_same_subnet "$g" "${NIC_IPV6_ADDRS[$i]}" "${NIC_IPV6_PREFIXES[$i]}"; then
                        NIC_IPV6_GWS[$i]="$g"
                        log "Reused IPv6 gateway $g for ${NIC_NAMES[$i]} based on subnet match"
                        break
                    fi
                done
            fi
        done
    }

    # If any NIC has an address but a missing gateway ('-'), and we're in an
    # interactive session (and not auto-confirm), prompt the user to supply a
    # gateway before writing the configuration file. This ensures the generated
    # config is complete when possible.
    local needs_prompt=false
    for i in "${!NIC_NAMES[@]}"; do
        if { [ "${NIC_IPV4_ADDRS[$i]}" != "-" ] && { [ -z "${NIC_IPV4_GWS[$i]}" ] || [ "${NIC_IPV4_GWS[$i]}" = "-" ]; }; } \
           || { [ "${NIC_IPV6_ADDRS[$i]}" != "-" ] && { [ -z "${NIC_IPV6_GWS[$i]}" ] || [ "${NIC_IPV6_GWS[$i]}" = "-" ]; }; }; then
            needs_prompt=true
            break
        fi
    done

    if [ "$needs_prompt" = true ] && is_interactive && [ "${AUTO_YES:-false}" != true ]; then
        for i in "${!NIC_NAMES[@]}"; do
            dev=${NIC_NAMES[$i]}
            ipv4_addr=${NIC_IPV4_ADDRS[$i]}
            ipv4_pref=${NIC_IPV4_PREFIXES[$i]}
            gw4=${NIC_IPV4_GWS[$i]}
            ipv6_addr=${NIC_IPV6_ADDRS[$i]}
            ipv6_pref=${NIC_IPV6_PREFIXES[$i]}
            gw6=${NIC_IPV6_GWS[$i]}

            if [ "$ipv4_addr" != "-" ] && { [ -z "$gw4" ] || [ "$gw4" = "-" ]; }; then
                echo "No IPv4 gateway detected for $dev ($ipv4_addr$ipv4_pref). Enter IPv4 gateway for $dev or '-' to skip:" >&2
                read -r ans4
                if [ -n "$ans4" ] && [ "$ans4" != "-" ]; then
                    if is_ipv4 "$ans4"; then
                        NIC_IPV4_GWS[$i]="$ans4"
                    else
                        echo "Input '$ans4' is not a valid IPv4 address; leaving '-'" >&2
                        NIC_IPV4_GWS[$i]="-"
                    fi
                else
                    NIC_IPV4_GWS[$i]="-"
                fi
            fi

            if [ "$ipv6_addr" != "-" ] && { [ -z "$gw6" ] || [ "$gw6" = "-" ]; }; then
                echo "No IPv6 gateway detected for $dev ($ipv6_addr$ipv6_pref). Enter IPv6 gateway for $dev or '-' to skip:" >&2
                read -r ans6
                if [ -n "$ans6" ] && [ "$ans6" != "-" ]; then
                    if is_ipv6 "$ans6"; then
                        NIC_IPV6_GWS[$i]="$ans6"
                    else
                        echo "Input '$ans6' is not a valid IPv6 address; leaving '-'" >&2
                        NIC_IPV6_GWS[$i]="-"
                    fi
                else
                    NIC_IPV6_GWS[$i]="-"
                fi
            fi
        done
    fi

    # If generator debug mode was requested, force DRY_RUN and verbose output
    # so the generated file is previewed and not written into /etc.
    if [ "${GENERATE_CONFIG_DEBUG:-false}" = "true" ]; then
        log "Generator debug mode enabled: forcing DRY_RUN and verbose output"
        DRY_RUN=true
        DEBUG=true
    fi

    # Debug: print detected device lists and per-NIC arrays
    if [ "${GENERATE_CONFIG_DEBUG:-false}" = "true" ] || [ "$DEBUG" = true ]; then
        # Use printf to safely join array elements for logging to avoid
        # unquoted expansions which trigger shellcheck SC2086.
        log "Detected devices (NICS): $(printf '%s ' "${NICS[@]:-}")"
        log "Detected NIC_NAMES: $(printf '%s ' "${NIC_NAMES[@]:-}")"
        log "NIC_IPV4_ADDRS: $(printf '%s ' "${NIC_IPV4_ADDRS[@]:-}")"
        log "NIC_IPV4_PREFIXES: $(printf '%s ' "${NIC_IPV4_PREFIXES[@]:-}")"
        log "NIC_IPV4_GWS: $(printf '%s ' "${NIC_IPV4_GWS[@]:-}")"
        log "NIC_IPV6_ADDRS: $(printf '%s ' "${NIC_IPV6_ADDRS[@]:-}")"
        log "NIC_IPV6_PREFIXES: $(printf '%s ' "${NIC_IPV6_PREFIXES[@]:-}")"
        log "NIC_IPV6_GWS: $(printf '%s ' "${NIC_IPV6_GWS[@]:-}")"
        log "DEFAULT_ROUTE_NIC (detected): ${DEFAULT_ROUTE_NIC:-none}"
    fi

    # If no suitable NICs were detected, write a small example config to
    # $CONFIG_FILE so the user has a template to edit. This prevents the
    # script from failing silently on hosts without physical NICs.
    if (( ${#NIC_NAMES[@]} == 0 )); then
        log "No suitable NICs detected; writing example config instead."
    cat <<'EXAMPLE' | tee "$CONFIG_FILE" > /dev/null
# Example /etc/perfSONAR-multi-nic-config.conf
# (no interfaces detected automatically)
NIC_NAMES=("eth0" "eth1")
NIC_IPV4_ADDRS=("192.0.2.10" "198.51.100.10")
NIC_IPV4_PREFIXES=("/24" "/24")
NIC_IPV4_GWS=("192.0.2.1" "198.51.100.1")
NIC_IPV4_ADDROUTE=("-" "-")
NIC_IPV6_ADDRS=("-" "-")
NIC_IPV6_PREFIXES=("-" "-")
NIC_IPV6_GWS=("-" "-")
# Specify the NIC that will hold the default route for this host
DEFAULT_ROUTE_NIC="eth1"
EXAMPLE
    chmod 0644 "$CONFIG_FILE" || true
    chown root:root "$CONFIG_FILE" || true
        echo "Generated example configuration at $CONFIG_FILE." >&2
        echo "Edit it to match your interfaces and rerun this script. Exiting." >&2
        exit 0
    fi

    # Determine default route NIC if unspecified
    # Prefer the previously-detected DEFAULT_ROUTE_NIC (from ip route),
    # otherwise select a NIC with a gateway or fall back to the first NIC.
    local DEFAULT_ROUTE_NIC_DETECTED="${DEFAULT_ROUTE_NIC:-}"
    if [ -z "$DEFAULT_ROUTE_NIC_DETECTED" ]; then
        # pick first NIC with an ipv4 gateway or the first NIC
        for i in "${!NIC_NAMES[@]}"; do
            if [ "${NIC_IPV4_GWS[$i]}" != "-" ]; then
                DEFAULT_ROUTE_NIC_DETECTED="${NIC_NAMES[$i]}"
                break
            fi
        done
    fi
    [ -z "$DEFAULT_ROUTE_NIC_DETECTED" ] && DEFAULT_ROUTE_NIC_DETECTED="${NIC_NAMES[0]}"

    # Export/set DEFAULT_ROUTE_NIC in the current shell so callers/tests can read it
    # and include it in debug output. The generated config file will also contain
    # DEFAULT_ROUTE_NIC (written later).
    DEFAULT_ROUTE_NIC="$DEFAULT_ROUTE_NIC_DETECTED"
    export DEFAULT_ROUTE_NIC

    # Write the detected config to a temp file then (atomically) move it into
    # place under $CONFIG_FILE. When not in DRY_RUN/debug mode the tmp file
    # will be moved into /etc with sudo.
    local TMPFILE
    TMPFILE="/tmp/perfsonar-gen-config-$$.conf"
    {
        echo "# Auto-generated /etc/perfSONAR-multi-nic-config.conf"
        echo "# Generated: $(date)"
        echo "#"
        echo "# This file contains parallel arrays describing network interfaces"
        echo "# for the perfSONAR multi-NIC configuration. The arrays MUST be the"
        echo "# same length and elements at the same index correspond to the same"
        echo "# physical interface. Edit carefully."
        echo ""

        # Helper: print a commented, multiline bash array for readability
        _print_array_multiline() {
            local name="$1"; shift
            printf "%s=(\n" "$name" >> "$TMPFILE"
            for v in "$@"; do
                # Use printf with explicit quoting for values containing spaces
                printf '  "%s"\n' "$v" >> "$TMPFILE"
            done
            printf ")\n\n" >> "$TMPFILE"
        }

        echo "# NIC device names (order matters). Example: (\"eth0\" \"eth1\")"
        echo "NIC_NAMES=(" >> "$TMPFILE"
        for n in "${NIC_NAMES[@]}"; do
            printf '  "%s"\n' "$n" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv4 addresses for each NIC (use '-' for none). Include prefix like /24"
        echo "# Example: (\"192.0.2.10/24\" \"198.51.100.10/24\")"
        echo "NIC_IPV4_ADDRS=(" >> "$TMPFILE"
        for v in "${NIC_IPV4_ADDRS[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv4 prefixes (separate value) kept for compatibility; use /24 style or '-'"
        echo "NIC_IPV4_PREFIXES=(" >> "$TMPFILE"
        for v in "${NIC_IPV4_PREFIXES[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv4 gateways for each NIC (use '-' for none)"
        echo "NIC_IPV4_GWS=(" >> "$TMPFILE"
        for v in "${NIC_IPV4_GWS[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# Additional IPv4 static routes to add to the NIC's table (use '-' for none)"
        echo "NIC_IPV4_ADDROUTE=(" >> "$TMPFILE"
        for v in "${NIC_IPV4_ADDROUTE[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv6 addresses for each NIC (use '-' for none). Include prefix like /64"
        echo "NIC_IPV6_ADDRS=(" >> "$TMPFILE"
        for v in "${NIC_IPV6_ADDRS[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv6 prefixes (separate value) kept for compatibility; use /64 style or '-'"
        echo "NIC_IPV6_PREFIXES=(" >> "$TMPFILE"
        for v in "${NIC_IPV6_PREFIXES[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# IPv6 gateways for each NIC (use '-' for none)"
        echo "NIC_IPV6_GWS=(" >> "$TMPFILE"
        for v in "${NIC_IPV6_GWS[@]}"; do
            printf '  "%s"\n' "$v" >> "$TMPFILE"
        done
        printf ")\n\n" >> "$TMPFILE"

        echo "# Specify the NIC that will hold the default route for this host"
        printf 'DEFAULT_ROUTE_NIC="%s"\n' "$DEFAULT_ROUTE_NIC_DETECTED" >> "$TMPFILE"
    }

    # Move into place (or print preview when in dry-run/debug).
    if [ "${GENERATE_CONFIG_DEBUG:-false}" = "true" ] || [ "$DRY_RUN" = true ]; then
        log "Generator debug/dry-run: temp file created at $TMPFILE (not moving into place)"
        if [ -f "$TMPFILE" ]; then
            log "----- Begin generated config preview -----"
            sed -n '1,200p' "$TMPFILE" | sed -n '1,200p' | tee -a "$LOG_FILE"
            log "----- End generated config preview -----"
        fi
    else
        run_cmd mv "$TMPFILE" "$CONFIG_FILE" || handle_error "Failed to write generated config to $CONFIG_FILE"
    fi
    run_cmd chmod 0644 "$CONFIG_FILE" || true
    run_cmd chown root:root "$CONFIG_FILE" || true
    echo "Generated configuration at $CONFIG_FILE (auto-detected). Edit if needed and rerun the script." >&2
    exit 0
}

# -------- Configuration validation helpers --------
# Lightweight IP checks used only for config validation. These functions are
# intentionally permissive/fallback-friendly: the goal is to catch obvious
# configuration mistakes before attempting network changes, not to replace
# a full IP validation library. Where available, Python's `ipaddress` module
# is used for robust IPv6 validation.
is_ipv4() {
    local ip=$1
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r a b c d <<<"$ip"
    for oct in $a $b $c $d; do
        if ((oct < 0 || oct > 255)); then
            return 1
        fi
    done
    return 0
}

is_ipv6() {
    local ip=$1
    # Prefer using Python's ipaddress module for robust validation if available
    if command -v python3 >/dev/null 2>&1; then
        # shellcheck disable=SC2317
        python3 -c "import sys,ipaddress
try:
    ipaddress.ip_address(sys.argv[1])
except Exception:
    sys.exit(1)
sys.exit(0)" "$ip" >/dev/null 2>&1
        return $?
    fi

    # Fallback: a permissive check that ensures at least one colon and only
    # valid hex and colon characters. This accepts compressed forms like '::'.
    [[ "$ip" == *:* && "$ip" =~ ^[0-9a-fA-F:]+$ ]]
}

# shellcheck disable=SC2317
is_ip() {
    local ip=$1
    [ "$ip" = "-" ] && return 0
    is_ipv4 "$ip" && return 0
    is_ipv6 "$ip" && return 0
    return 1
}

validate_prefix() {
    local p=$1
    local max=$2
    if [ "$p" = "-" ]; then
        return 0
    fi
    if [[ "$p" =~ ^/([0-9]{1,3})$ ]]; then
        local num=${BASH_REMATCH[1]}
        if ((num >= 0 && num <= max)); then
            return 0
        fi
    fi
    return 1
}

# validate_config: sanity-check the arrays loaded from the config file.
# Behavior:
#  - Ensures array lengths match NIC_NAMES
#  - Ensures DEFAULT_ROUTE_NIC is set and present in NIC_NAMES
#  - Validates per-NIC addresses, prefixes, and gateways. On any fatal
#    validation error the script will exit with a non-zero status.
validate_config() {
    local errs=()
    local n=${#NIC_NAMES[@]}
    if (( n == 0 )); then
        errs+=("NIC_NAMES is empty or not defined")
    fi

    # Arrays that should match NIC_NAMES length. Use a nameref to avoid eval
    # and to make static analysis (shellcheck) happier.
    local arrs=(NIC_IPV4_ADDRS NIC_IPV4_PREFIXES NIC_IPV4_GWS NIC_IPV4_ADDROUTE NIC_IPV6_ADDRS NIC_IPV6_PREFIXES NIC_IPV6_GWS)
    for name in "${arrs[@]}"; do
        # Create a local nameref to the array named in $name. If the array is
        # unset, the nameref will refer to an empty value and length will be 0.
        local -n arr_ref="${name}"
    local count=${#arr_ref[@]}
        if (( count != n )); then
            errs+=("Array $name has length $count but NIC_NAMES length is $n")
        fi
        unset -n arr_ref || true
    done

    # DEFAULT_ROUTE_NIC must be set and present in NIC_NAMES
    if [ -z "${DEFAULT_ROUTE_NIC:-}" ]; then
        errs+=("DEFAULT_ROUTE_NIC is not set")
    else
        local found=false
        for nm in "${NIC_NAMES[@]}"; do
            if [[ "$nm" == "$DEFAULT_ROUTE_NIC" ]]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            errs+=("DEFAULT_ROUTE_NIC ($DEFAULT_ROUTE_NIC) is not in NIC_NAMES")
        fi
    fi

    # Per-NIC checks without eval: use safe parameter expansion to handle
    # potentially unset arrays while running under 'set -u'. Defaults use '-'.
    for ((i=0; i<n; i++)); do
        local nic=${NIC_NAMES[$i]:-}
        local ipv4=${NIC_IPV4_ADDRS[$i]:-"-"}
        local p4=${NIC_IPV4_PREFIXES[$i]:-"-"}
    local gw4=${NIC_IPV4_GWS[$i]:-"-"}
        local ipv6=${NIC_IPV6_ADDRS[$i]:-"-"}
        local p6=${NIC_IPV6_PREFIXES[$i]:-"-"}
        local gw6=${NIC_IPV6_GWS[$i]:-"-"}

        # Basic nic name check
        if [ -z "$nic" ]; then
            errs+=("NIC at index $i has empty name")
            # Skip further checks for this index since nic is essential
            continue
        fi

    # IPv4 consistency
        if [ "$ipv4" = "-" ]; then
            if [ "$p4" != "-" ]; then
                errs+=("$nic: IPv4 address is '-' but prefix is '$p4'; make both '-' or provide an address and prefix")
            fi
            if [ "$gw4" != "-" ]; then
                errs+=("$nic: IPv4 gateway should be '-' when IPv4 address is '-' but is '$gw4'")
            fi
        else
            if ! is_ipv4 "$ipv4"; then
                errs+=("$nic: invalid IPv4 address: $ipv4")
            fi
            if ! validate_prefix "$p4" 32; then
                errs+=("$nic: invalid IPv4 prefix: $p4")
            fi
            if [ "$gw4" = "-" ] || ! is_ipv4 "$gw4"; then
                errs+=("$nic: invalid or missing IPv4 gateway: $gw4")
            fi
        fi

        # IPv6 consistency
        if [ "$ipv6" = "-" ]; then
            if [ "$p6" != "-" ]; then
                errs+=("$nic: IPv6 address is '-' but prefix is '$p6'; make both '-' or provide an address and prefix")
            fi
            if [ "$gw6" != "-" ]; then
                errs+=("$nic: IPv6 gateway should be '-' when IPv6 address is '-' but is '$gw6'")
            fi
        else
            if ! is_ipv6 "$ipv6"; then
                errs+=("$nic: invalid IPv6 address: $ipv6")
            fi
            if ! validate_prefix "$p6" 128; then
                errs+=("$nic: invalid IPv6 prefix: $p6")
            fi
            if [ "$gw6" = "-" ] || ! is_ipv6 "$gw6"; then
                errs+=("$nic: invalid or missing IPv6 gateway: $gw6")
            fi
        fi
    done

    if (( ${#errs[@]} > 0 )); then
        log "Configuration validation failed with ${#errs[@]} error(s):"
        for e in "${errs[@]}"; do
            log "  - $e"
            echo "ERROR: $e" >&2
        done
        exit 1
    fi
}

# -------- Config sanitization (defined before main) --------
# sanitize_config: remove stray CR (\r) and NUL characters from arrays and
# scalars that are commonly introduced when editing files on Windows or by
# broken editors. Sanitization is performed in-memory after sourcing the
# config; the function does not overwrite the file on disk so operations are
# non-destructive until changes are explicitly written.
sanitize_config() {
    local changed=false
    local arr_names=(NIC_NAMES NIC_IPV4_ADDRS NIC_IPV4_PREFIXES NIC_IPV4_GWS NIC_IPV4_ADDROUTE NIC_IPV6_ADDRS NIC_IPV6_PREFIXES NIC_IPV6_GWS)
    for name in "${arr_names[@]}"; do
        # Use nameref to iterate array elements safely under set -u
        if ! declare -p "$name" >/dev/null 2>&1; then
            continue
        fi
        local -n aref="$name"
        for i in "${!aref[@]}"; do
            local before=${aref[i]}
            # strip carriage returns and other C0 control except tab
            local after=${before//$'\r'/}
            after=${after//$'\000'/}
            if [ "$before" != "$after" ]; then
                aref[i]="$after"
                changed=true
            fi
        done
        unset -n aref || true
    done

    # Scalars
    if declare -p DEFAULT_ROUTE_NIC >/dev/null 2>&1; then
        local before_scalar=$DEFAULT_ROUTE_NIC
        DEFAULT_ROUTE_NIC=${DEFAULT_ROUTE_NIC//$'\r'/}
        DEFAULT_ROUTE_NIC=${DEFAULT_ROUTE_NIC//$'\000'/}
        if [ "$before_scalar" != "$DEFAULT_ROUTE_NIC" ]; then
            changed=true
        fi
    fi

    if [ "$changed" = true ]; then
        log "Sanitized config values (removed trailing CR/NUL characters)."
    fi
}

# Prompt for any missing gateways in the loaded config (post-load), updating in-memory arrays.
# Skips prompting when running non-interactively or when AUTO_YES=true.
prompt_missing_gateways_from_config() {
    if ! is_interactive || [ "${AUTO_YES:-false}" = true ]; then
        return 0
    fi
    local updated=false
    local n=${#NIC_NAMES[@]}
    for ((i=0; i<n; i++)); do
        local dev=${NIC_NAMES[$i]:-}
        local ipv4=${NIC_IPV4_ADDRS[$i]:-"-"}
        local p4=${NIC_IPV4_PREFIXES[$i]:-"-"}
        local gw4=${NIC_IPV4_GWS[$i]:-"-"}
        local ipv6=${NIC_IPV6_ADDRS[$i]:-"-"}
        local p6=${NIC_IPV6_PREFIXES[$i]:-"-"}
        local gw6=${NIC_IPV6_GWS[$i]:-"-"}

        if [ "$ipv4" != "-" ] && { [ -z "$gw4" ] || [ "$gw4" = "-" ]; }; then
            echo "Gateway missing for $dev IPv4 ($ipv4$p4). Enter IPv4 gateway or '-' to skip:" >&2
            read -r ans4
            if [ -n "$ans4" ] && [ "$ans4" != "-" ]; then
                if is_ipv4 "$ans4"; then
                    NIC_IPV4_GWS[$i]="$ans4"; updated=true
                else
                    echo "Input '$ans4' is not a valid IPv4 address; keeping '-'" >&2
                fi
            fi
        fi

        if [ "$ipv6" != "-" ] && { [ -z "$gw6" ] || [ "$gw6" = "-" ]; }; then
            echo "Gateway missing for $dev IPv6 ($ipv6$p6). Enter IPv6 gateway or '-' to skip:" >&2
            read -r ans6
            if [ -n "$ans6" ] && [ "$ans6" != "-" ]; then
                if is_ipv6 "$ans6"; then
                    NIC_IPV6_GWS[$i]="$ans6"; updated=true
                else
                    echo "Input '$ans6' is not a valid IPv6 address; keeping '-'" >&2
                fi
            fi
        fi
    done

    if [ "$updated" = true ]; then
        log "Gateways provided interactively; persisting updates to $CONFIG_FILE."
        save_config_to_file "$CONFIG_FILE"
    fi
}

# NOTE: CLI parsing, shellcheck, and config loading are performed in the
# main execution section at the end of this file to guarantee every helper
# function is defined before any function is invoked. This ordering avoids
# runtime errors when flags cause functions to be executed early.

# -------- Validation --------
# -------- Validation helpers --------
validate_nic() {
    # Ensure interface exists
    local nic=$1
    if ! ip link show "$nic" > /dev/null 2>&1; then
        handle_error "NIC $nic does not exist on this system."
    fi
}

validate_ip() {
    # Basic check for IPv4 or IPv6 address; '-' is treated as empty/unused
    local ip=$1
    if [ "$ip" = "-" ]; then
        return 0
    fi
    if is_ipv4 "$ip" || is_ipv6 "$ip"; then
        return 0
    fi
    handle_error "Invalid IP address: $ip"
}

# -------- Backup existing NetworkManager configurations --------
# backup_existing_configs: create a timestamped backup of /etc/NetworkManager/system-connections
# Uses rsync for safer copying (avoids globbing pitfalls) and records BACKUP_DIR for rollback.
backup_existing_configs() {
    BACKUP_DIR="/etc/NetworkManager/system-connections-backup-$(date +%Y%m%d%H%M%S)"
    log "Backing up existing configurations to $BACKUP_DIR..."
    run_cmd mkdir -p "$BACKUP_DIR"
    # Use rsync to copy contents safely (avoids shell globbing issues with /*)
    run_cmd rsync -a -- /etc/NetworkManager/system-connections/ "$BACKUP_DIR" || log "No existing connections to backup or copy failed"
    log "Removing original configuration files from /etc/NetworkManager/system-connections/"
    run_cmd rm -rf /etc/NetworkManager/system-connections/*
}

# -------- Routing table management --------
# add_routing_table: ensure an iproute2 table mapping (number -> name) exists.
# Strategy:
#  - Prefer distro drop-in files under `/etc/iproute2/rt_tables.d/` (one file
#    per mapping) when available. This tends to work better with modern
#    packaging and SELinux tools.
#  - As a fallback append to `/etc/iproute2/rt_tables` after removing any
#    stale entries for the same table name.
#  - Before adding a mapping, remove any existing entries for the same table
#    name to avoid duplicates and ensure the mapping is updated atomically.
add_routing_table() {
    # Add a routing table mapping if missing. Prefer the distro drop-in
    # directory (/etc/iproute2/rt_tables.d/) when present; otherwise fall
    # back to appending the legacy /etc/iproute2/rt_tables file.
    local table_num=$1
    local table_name=$2
    local dropin_dir=/etc/iproute2/rt_tables.d
    local dropin_file="${dropin_dir}/${table_num}-${table_name}.conf"

    if [ -d "$dropin_dir" ]; then
    # Remove any existing mapping for this table name from drop-in files
    # to avoid duplicate or stale entries. We filter lines where the
    # second field equals the table name (typical format: "<num> <name>").
        for f in "$dropin_dir"/*; do
            [ -f "$f" ] || continue
            if awk -v name="$table_name" '$2 == name {exit 0} END{exit 1}' "$f" 2>/dev/null; then
                log "Removing existing routing table entry for $table_name from $f"
                # Use sed -i to remove matching lines in-place (safer and avoids complex shell -c quoting)
                # Match the table-name at end-of-line and delete the line.
                run_cmd sed -i -E "/^[[:space:]]*[0-9]+[[:space:]]+${table_name}[[:space:]]*$/d" "$f" || log "Failed to clean $f"
            fi
        done

    # If any drop-in still contains the desired mapping number/name pair,
    # consider it present and skip creation. This is conservative.
        if grep -Eq "^[[:space:]]*${table_num}[[:space:]]+${table_name}[[:space:]]*$" "$dropin_dir"/* 2>/dev/null; then
            log "Routing table ${table_name} already present in drop-ins"
            return 0
        fi

        log "Creating drop-in $dropin_file"
        run_cmd mkdir -p "$dropin_dir"
    # Create the drop-in file (atomic creation) and set perms using printf via sh -c
    # shellcheck disable=SC2016
    # Intentionally single-quoted: $1/$2/$3 should be expanded by the
    # invoked shell (sh -c) using the provided positional args.
    run_cmd sh -c 'printf "%s\t%s\n" "$1" "$2" > "$3"' -- "$table_num" "$table_name" "$dropin_file"
        run_cmd chmod 0644 "$dropin_file"
        run_cmd chown root:root "$dropin_file"
        # Restore SELinux context if possible
        if command -v restorecon >/dev/null 2>&1; then
            run_cmd restorecon -v "$dropin_file" || true
        fi
        log "Added routing table ${table_name} as number ${table_num} via drop-in"
        return 0
    fi

    # Fallback: ensure there are no existing entries for this table name in
    # the legacy /etc/iproute2/rt_tables, remove them if present, then append
    # the desired mapping.
    if grep -wq "${table_name}" /etc/iproute2/rt_tables 2>/dev/null; then
        log "Removing existing entry for ${table_name} from /etc/iproute2/rt_tables"
    run_cmd sed -i -E "/^[[:space:]]*[0-9]+[[:space:]]+${table_name}[[:space:]]*$/d" /etc/iproute2/rt_tables || log "Failed to clean /etc/iproute2/rt_tables"
    fi

    # shellcheck disable=SC2016
    # Intentionally single-quoted: $1/$2 should be expanded by the invoked
    # shell (sh -c) using the provided positional args when appending.
    run_cmd sh -c 'printf "%s\t%s\n" "$1" "$2" >> /etc/iproute2/rt_tables' -- "$table_num" "$table_name" || handle_error "Failed to add routing table ${table_name}"
    log "Added routing table ${table_name} as number ${table_num} to /etc/iproute2/rt_tables"
}

##
# Resolve or create a NetworkManager connection for a given device name.
# Many systems have connection "names" that do not equal the device name
# (for example "Wired connection 1"). This helper finds the connection
# associated with a device or creates a new dedicated connection named
# "perfsonar-<dev>" if none exists. It prints the connection name to stdout.
get_conn_for_device() {
    local dev=$1
    local conn=""

    # Try to read the active connection associated with the device.
    if command -v nmcli >/dev/null 2>&1; then
        # nmcli device show prints a GENERAL.CONNECTION field when a
        # connection is active. Use -t to make parsing predictable.
        conn=$(nmcli -t -f GENERAL.CONNECTION device show "$dev" 2>/dev/null | awk -F: '{print $2}' || true)
    fi

    # Fallback: find any connection that references this device
    if [ -z "$conn" ] || [ "$conn" = "--" ]; then
        conn=$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | awk -F: -v d="$dev" '$2==d{print $1; exit}' || true)
    fi

    # If still empty, create a new connection named perfsonar-<dev>
    if [ -z "$conn" ]; then
        conn="perfsonar-$dev"
        log "No existing NM connection for device $dev; creating connection $conn"
        # Create a minimal ethernet connection bound to the interface
        run_cmd nmcli connection add type ethernet ifname "$dev" con-name "$conn" autoconnect yes || handle_error "Failed to create connection $conn for device $dev"
    fi

    printf '%s' "$conn"
}

# -------- Per-NIC NetworkManager configuration --------
# configure_nic: perform all NetworkManager modifications for a single NIC
# Side effects: creates/edits nmcli connection settings, may create routing
# table entries, and brings the connection up. Relies on the arrays loaded
# from the config file and validated by validate_config().
configure_nic() {
    # Configure a single NIC's NetworkManager connection and routing rules
    local idx=$1

    local nic=${NIC_NAMES[$idx]}
    local ipv4_addr=${NIC_IPV4_ADDRS[$idx]}
    local ipv4_prefix=${NIC_IPV4_PREFIXES[$idx]}
    local ipv4_gw=${NIC_IPV4_GWS[$idx]}
    local ipv4_addroute=${NIC_IPV4_ADDROUTE[$idx]}
    local ipv6_addr=${NIC_IPV6_ADDRS[$idx]}
    local ipv6_prefix=${NIC_IPV6_PREFIXES[$idx]}
    local ipv6_gw=${NIC_IPV6_GWS[$idx]}
    local table_id=$((idx + 300))
    local rt_table_name="${nic}_source_route"
    local priority=$((idx + 200))

    # Validate NIC and IPs
    validate_nic "$nic"
    validate_ip "$ipv4_addr"
    validate_ip "$ipv6_addr"

    # Resolve or create NetworkManager connection associated with this device
    local conn
    conn=$(get_conn_for_device "$nic")

    # Ensure routing table exists for non-default NICs
    if [[ "$nic" != "$DEFAULT_ROUTE_NIC" ]]; then
        log "\n${GREEN}Configuring NIC $nic ($ipv4_addr$ipv4_prefix) with table $rt_table_name ($table_id)${NC}"
        add_routing_table "$table_id" "$rt_table_name"
    else
        log "\n${GREEN}Configuring NIC $nic ($ipv4_addr$ipv4_prefix) for DEFAULT route${NC}"
    fi

    # Ensure the NIC's NetworkManager connection exists and is set to autoconnect
    run_cmd nmcli con mod "$conn" connection.autoconnect yes || handle_error "Failed to enable autoconnect for $nic (conn: $conn)"

    # Use manual IPv4 addressing
    run_cmd nmcli con mod "$conn" ipv4.method manual || handle_error "Failed to set IPv4 method for $nic (conn: $conn)"

    # Configure static IPv4 address + gateway (use canonical nmcli keys)
    log "  - Setting IPv4 address and gateway"
    run_cmd nmcli con mod "$conn" ipv4.addresses "$ipv4_addr$ipv4_prefix" ipv4.gateway "$ipv4_gw" || handle_error "Failed to set IPv4 address for $nic (conn: $conn)"

    # Configure static IPv6 if present
    if [[ "$ipv6_addr" != "-" ]]; then
        run_cmd nmcli con mod "$conn" ipv6.method manual || handle_error "Failed to set IPv6 method for $nic (conn: $conn)"
        log "  - Setting IPv6 address and gateway"
        run_cmd nmcli con mod "$conn" ipv6.addresses "$ipv6_addr$ipv6_prefix" ipv6.gateway "$ipv6_gw" || handle_error "Failed to set IPv6 address for $nic (conn: $conn)"
    fi

    # Default route logic controlled by DEFAULT_ROUTE_NIC
    if [[ "$nic" == "$DEFAULT_ROUTE_NIC" ]]; then
        echo "  - ${nic} is the default route NIC" | tee -a "$LOG_FILE"
        if ! run_cmd nmcli con mod "$conn" +ipv4.routes "0.0.0.0/0 $ipv4_gw"; then
            log "nmcli failed to set default IPv4 route for $conn; falling back to ip route"
            run_cmd ip route replace default via "$ipv4_gw" dev "$nic" || handle_error "Failed to set fallback IPv4 default route for $nic"
        fi
        if [[ "$ipv6_addr" != "-" ]]; then
            if ! run_cmd nmcli con mod "$conn" +ipv6.routes "::/0 $ipv6_gw"; then
                log "nmcli failed to set default IPv6 route for $conn; falling back to ip -6 route"
                run_cmd ip -6 route replace default via "$ipv6_gw" dev "$nic" || handle_error "Failed to set fallback IPv6 default route for $nic"
            fi
        fi
    else
        echo "  - Non-default NIC: static IPv4 route with source-based routing rules on table $table_id for $nic" | tee -a "$LOG_FILE"
        if ! run_cmd nmcli con mod "$conn" +ipv4.routes "0.0.0.0/0 $ipv4_gw table=$table_id"; then
            log "nmcli failed to set IPv4 route for $conn; falling back to ip route"
            run_cmd ip route replace default via "$ipv4_gw" dev "$nic" table "$table_id" || handle_error "Failed to set fallback IPv4 route for $nic"
        fi

        if [[ "$ipv4_addroute" != "-" ]]; then
            echo "  - ${nic} adding static route to table $table_id for $ipv4_addroute" | tee -a "$LOG_FILE"
            if ! run_cmd nmcli con mod "$conn" +ipv4.routes "$ipv4_addroute table=$table_id"; then
                log "nmcli failed to add custom IPv4 route for $conn; falling back to ip route"
                run_cmd ip route add $ipv4_addroute table "$table_id" || log "Fallback: failed to add custom IPv4 route for $nic (may need manual intervention)"
            fi
        fi

        if [[ "$ipv6_addr" != "-" ]]; then
            echo "  - Non-default NIC: static IPv6 route with source-based routing rules on table $table_id for $nic" | tee -a "$LOG_FILE"
            if ! run_cmd nmcli con mod "$conn" +ipv6.routes "::/0 $ipv6_gw table=$table_id"; then
                log "nmcli failed to set IPv6 route for $conn; falling back to ip -6 route"
                run_cmd ip -6 route replace default via "$ipv6_gw" dev "$nic" table "$table_id" || handle_error "Failed to set fallback IPv6 route for $nic"
            fi
        fi

        # Add policy routing rules for this NIC
        echo "  - Applying IPv4 routing rules for $nic and table $table_id..." | tee -a "$LOG_FILE"
        if ! run_cmd nmcli con mod "$conn" ipv4.routing-rules "priority $priority iif $nic table $table_id"; then
            log "nmcli cannot set ipv4.routing-rules; adding ip rule fallback"
            run_cmd ip rule add iif "$nic" table "$table_id" priority "$priority" || log "ip rule add iif failed or already present"
        fi
        if ! run_cmd nmcli con mod "$conn" +ipv4.routing-rules "priority $priority from $ipv4_addr table $table_id"; then
            log "nmcli cannot set ipv4.from rule; adding ip rule fallback"
            run_cmd ip rule add from "$ipv4_addr/32" table "$table_id" priority "$priority" || log "ip rule add from failed or already present"
        fi

        if [[ "$ipv6_addr" != "-" ]]; then
            echo "  - Applying IPv6 routing rules for $nic and table $table_id..." | tee -a "$LOG_FILE"
            if ! run_cmd nmcli con mod "$conn" ipv6.routing-rules "priority $priority iif $nic table $table_id"; then
                log "nmcli cannot set ipv6.routing-rules; adding ip -6 rule fallback"
                run_cmd ip -6 rule add iif "$nic" table "$table_id" priority "$priority" || log "ip -6 rule add iif failed or already present"
            fi
            if ! run_cmd nmcli con mod "$conn" +ipv6.routing-rules "priority $priority from $ipv6_addr table $table_id"; then
                log "nmcli cannot set ipv6.from rule; adding ip -6 rule fallback"
                run_cmd ip -6 rule add from "$ipv6_addr/128" table "$table_id" priority "$priority" || log "ip -6 rule add from failed or already present"
            fi
        fi

        # Prevent this connection from installing default routes
        echo "  - Marking as private: prevent default gateway" | tee -a "$LOG_FILE"
        run_cmd nmcli con mod "$conn" ipv4.never-default yes || handle_error "Failed to mark $nic as private (conn: $conn)"
        if [[ "$ipv6_addr" != "-" ]]; then
            run_cmd nmcli con mod "$conn" ipv6.never-default yes || handle_error "Failed to mark $nic as private (conn: $conn)"
        fi
    fi

    # Bring up the connection and reapply device config
    run_cmd nmcli conn up "$conn" || handle_error "Failed to bring up $nic (conn: $conn)"
    sleep 1
    run_cmd nmcli device reapply "$nic" || handle_error "Failed to reapply device config for $nic"
}

# ---- MAIN SCRIPT ----

# -------------------- Runtime: parse CLI, lint, and load config --------------------
# Parse CLI options (performed only in the main execution path). This ensures
# all helper functions above are available when flags trigger function calls
# such as generate_config_from_system.
while [[ ${#} -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            AUTO_YES=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --generate-config-auto)
            GENERATE_CONFIG_AUTO=true
            shift
            ;;
        --generate-config-debug)
            # Run the auto-generator in debug/dry-run mode and print internals
            GENERATE_CONFIG_DEBUG=true
            shift
            ;;
        --shellcheck)
            RUN_SHELLCHECK=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -* )
            echo "Unknown option: $1"
            usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

# Run shellcheck now that CLI flags are known (user can disable via --no-shellcheck)
run_shellcheck

# Ensure required tools and privileges
# Enforce running as root to avoid unexpected sudo prompts and to make
# behavior deterministic. Also verify `nmcli` is present since the script
# relies heavily on NetworkManager.
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo or as root." >&2
    exit 1
fi

if ! command -v nmcli >/dev/null 2>&1; then
    handle_error "nmcli (NetworkManager CLI) is required but not installed. Install NetworkManager and retry."
fi

# Configuration file handling: ensure config exists, auto-generate if missing,
# then source the configuration and validate it.
# Honor explicit request to auto-generate config even if a config exists.
if [ "${GENERATE_CONFIG_AUTO:-false}" = true ]; then
    log "User requested auto-generate of configuration via --generate-config-auto."
    generate_config_from_system
fi

if [ ! -f "$CONFIG_FILE" ]; then
    log "Configuration file $CONFIG_FILE not found. Attempting to auto-generate."
    generate_config_from_system
fi

# shellcheck source=/etc/perfSONAR-multi-nic-config.conf
source "$CONFIG_FILE"

# Sanitize config after sourcing and then validate its contents
sanitize_config
prompt_missing_gateways_from_config
validate_config

# -------- Warning Prompt --------
log "${RED}WARNING: This script will REMOVE ALL existing NetworkManager connections and apply new configurations.${NC}"
log "${RED}  - You may wish to run this via a directly connected console since the network will drop briefly${NC}"
if [ "$AUTO_YES" != true ]; then
    echo "Do you want to proceed? (yes/no)"
    read -r response
    if [[ "$response" != "yes" ]]; then
        log "Operation aborted by the user. Exiting."
        exit 0
    fi
else
    log "Auto-confirm enabled; continuing without prompt."
fi

# Validate configuration arrays are consistent in length
# Use arithmetic comparisons with named temporaries to avoid shellcheck
# warnings about always-true boolean expressions (SC2055).
_n_names=${#NIC_NAMES[@]}
_n_v4=${#NIC_IPV4_ADDRS[@]}
_n_p4=${#NIC_IPV4_PREFIXES[@]}
if (( _n_names != _n_v4 || _n_names != _n_p4 )); then
    handle_error "Configuration arrays have inconsistent lengths."
fi

log "Starting policy based routing configuration for perfSONAR at $(date)"

# Backup existing configurations
backup_existing_configs

# Flush existing routes (use sudo with tee via bash -c to avoid redirection issues)
log "Flushing all existing routes..."
run_cmd bash -c 'echo 1 > /proc/sys/net/ipv4/route/flush' || handle_error "Failed to flush IPv4 routes"
run_cmd bash -c 'echo 1 > /proc/sys/net/ipv6/route/flush' || handle_error "Failed to flush IPv6 routes"
run_cmd ip rule flush || handle_error "Failed to flush IP rules"

# Remove previous NetworkManager configurations
log "Removing ALL existing network configurations..."
# Execute removal via run_cmd and log failure explicitly; using an if/then
# prevents shellcheck complaining that the '||' may be misinterpreted.
if ! run_cmd rm -rf /etc/NetworkManager/system-connections/*; then
    log "No existing configurations removed or rm failed"
fi

# Configure each NIC from arrays defined in the config file
count=${#NIC_NAMES[@]}
for ((i = 0; i < count; i++)); do
    configure_nic "$i"
done

printf "\n%sAll NICs configured. Done at %s.%s\n\n" "$GREEN" "$(date)" "$NC" | tee -a "$LOG_FILE"
exit 0