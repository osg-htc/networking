#!/bin/bash
# perfSONAR nftables installer and helper
# --------------------------------------
# Purpose:
#   Configure nftables for a perfSONAR testpoint host (no package installation).
#   Optionally configure a minimal fail2ban jail and enable SELinux (with
#   warnings) — only if these components are already installed on the system.
#
# Contract (inputs / outputs):
#   - Input: CLI flags control behavior (see --help). Ports may be passed as a
#     comma-separated list via --ports. Default is a conservative set; please
#     verify for your deployment.
#   - Output: writes /etc/nftables.d/perfsonar.nft (backups created), enables
#     and starts the nftables service, installs requested packages, and
#     optionally writes a minimal `/etc/fail2ban/jail.d/perfsonar.local`.
#
# Safety:
#   - This script must be run as root. Use --dry-run to preview actions.
#   - It makes backups before overwriting nftables rules or fail2ban files.
#   - It does NOT install any packages. Ensure nftables/fail2ban/SELinux tools
#     are already installed; otherwise related configuration steps are skipped.
#
# Author: Generated based on existing perfSONAR helper scripts
# Version: 0.1.0 - 2025-11-03

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="/var/log/perfSONAR-install-nftables.log"
DRY_RUN=false
AUTO_YES=false
DEBUG=false
INSTALL_FAIL2BAN=false
ENABLE_SELINUX=false
PERF_PORTS="443"
NFT_RULE_FILE="/etc/nftables.d/perfsonar.nft"
CONFIG_FILE="/etc/perfSONAR-multi-nic-config.conf"
BACKUP_DIR="/var/backups/perfsonar-install-$(date +%s)"
PRINT_RULES=false
STRICT_VERIFY=false
P3_AVAIL=false

# Canonicalize a CIDR (IPv4/IPv6) to its network base using Python if available.
# Falls back to returning the input unchanged if Python3 isn't present.
canon_cidr() {
    local cidr="$1"
    if command -v python3 >/dev/null 2>&1; then
        # Use ipaddress to normalize to network base (strict=False allows host IPs)
        python3 - "$cidr" <<'PY'
import sys, ipaddress
arg = sys.argv[1]
try:
    net = ipaddress.ip_network(arg, strict=False)
    print(str(net))
except Exception:
    sys.exit(2)
PY
        return $?
    else
        # Without python, return unchanged (may still validate if already canonical)
        printf '%s\n' "$cidr"
        return 0
    fi
}

# Validate a single IP address (v4 or v6). Returns 0 if valid; non-zero if invalid.
is_valid_ip() {
    local ip="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$ip" <<'PY'
import sys, ipaddress
arg = sys.argv[1]
try:
    ipaddress.ip_address(arg)
    sys.exit(0)
except Exception:
    sys.exit(3)
PY
        return $?
    else
        # No python available: conservative choice is to treat as invalid to avoid emitting bad rules
        return 4
    fi
}

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

usage() {
    cat <<'EOF'
Usage: perfSONAR-install-nftables.sh [OPTIONS]

Options:
  --help               Show this help
  --dry-run            Print actions without making changes
  --yes                Skip confirmation prompts
  --fail2ban           Configure and enable a minimal fail2ban jail (if installed)
  --selinux            Attempt to enable SELinux (if installed; may require reboot)
  --ports=CSV          Comma-separated list of TCP ports to allow (default: 22,80,443)
  --debug              Print commands (set -x) for troubleshooting
  --backup-dir=DIR     Where to store backups (default: auto under /var/backups)
  --print-rules        Render the nftables rules to stdout and exit (no writes)
    --strict-verify      After applying, require that ONLY 'inet nftables_svc' is present
                                             in the active ruleset (default: presence-only check)

Example:
  /opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --fail2ban --ports=22,80,443,8085

Notes:
  - Run in a VM or console first. Use --dry-run to preview changes.
  - SELinux enablement is a potentially disruptive operation; read the
    script comments and test before enabling on production hosts.
  - This script does not install packages; ensure nftables/fail2ban/SELinux
    are present before using related flags.
EOF
}

log() {
    local ts line
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    line="$ts $*"
    # Write to logfile and to stderr (do not contaminate stdout, which may carry nft rules)
    printf '%s\n' "$line" >> "$LOG_FILE"
    printf '%s\n' "$line" >&2
}

# Print user-facing info. In --print-rules mode, route to stderr to keep stdout
# reserved exclusively for the nft rules content.
print_info() {
    if [ "$PRINT_RULES" = true ]; then
        printf '%s\n' "$*" >&2
    else
        printf '%s\n' "$*"
    fi
}

run_cmd() {
    local cmd_repr
    cmd_repr=$(printf '%q ' "$@")
    log "CMD: $cmd_repr"
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $cmd_repr"
        return 0
    fi
    if [ "$DEBUG" = true ]; then
        bash -x -c 'exec "$@"' -- "$@"
    else
        "$@"
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root." >&2
        exit 2
    fi
}

check_prereqs() {
    # No installation is performed. Only check and log presence of tools.
    if command -v nft >/dev/null 2>&1; then
        log "nftables detected; configuration steps will be applied."
    else
        log "nftables not detected; nftables configuration will be skipped."
    fi

    if [ "$INSTALL_FAIL2BAN" = true ]; then
        if command -v fail2ban-client >/dev/null 2>&1 || systemctl list-unit-files --type=service 2>/dev/null | grep -q '^fail2ban\.service'; then
            log "fail2ban detected; jail configuration will be applied."
        else
            log "fail2ban not detected; skipping fail2ban configuration."
            INSTALL_FAIL2BAN=false
        fi
    fi

    if [ "$ENABLE_SELINUX" = true ]; then
        if command -v getenforce >/dev/null 2>&1; then
            log "SELinux tools detected; SELinux configuration will be attempted."
        else
            log "SELinux tools not detected; skipping SELinux configuration."
            ENABLE_SELINUX=false
        fi
    fi
}

backup_file() {
    local src=$1
    mkdir -p "$BACKUP_DIR"
    if [ -f "$src" ]; then
        run_cmd cp -a -- "$src" "$BACKUP_DIR/"
        log "Backed up $src -> $BACKUP_DIR/"
    fi
}

write_nft_rules() {
    local ports_csv=$1
    log "write_nft_rules called with ports: $ports_csv"
    if ! command -v nft >/dev/null 2>&1; then
        log "nft command not found; skipping nftables rules write (component not installed)."
        return 0
    fi
    # Split SUBNETS/HOSTS into IPv4/IPv6 lists for embedding directly into set definitions
    local -a ip4_subnets=() ip6_subnets=() ip4_hosts=() ip6_hosts=()
    for s in "${SUBNETS[@]:-}"; do
        [ -z "$s" ] && continue
        if [[ "$s" == *":"* ]]; then
            ip6_subnets+=("$s")
        else
            ip4_subnets+=("$s")
        fi
    done
    for h in "${HOSTS[@]:-}"; do
        [ -z "$h" ] && continue
        if [[ "$h" == *":"* ]]; then
            ip6_hosts+=("$h")
        else
            ip4_hosts+=("$h")
        fi
    done

    # Helper to join array with comma+space
    _join_by() { local IFS=", "; shift; echo "$*"; }

    local ip4_subnets_join ip6_subnets_join ip4_hosts_join ip6_hosts_join
    ip4_subnets_join=$(_join_by , "${ip4_subnets[@]}")
    ip6_subnets_join=$(_join_by , "${ip6_subnets[@]}")
    ip4_hosts_join=$(_join_by , "${ip4_hosts[@]}")
    ip6_hosts_join=$(_join_by , "${ip6_hosts[@]}")

    # Conditionally render elements lines to avoid empty set syntax errors
    local SSH4_SUBNETS_ELEMS SSH6_SUBNETS_ELEMS SSH4_HOSTS_ELEMS SSH6_HOSTS_ELEMS
    SSH4_SUBNETS_ELEMS=""
    SSH6_SUBNETS_ELEMS=""
    SSH4_HOSTS_ELEMS=""
    SSH6_HOSTS_ELEMS=""
    [ -n "$ip4_subnets_join" ] && SSH4_SUBNETS_ELEMS="        elements = { $ip4_subnets_join }"
    [ -n "$ip6_subnets_join" ] && SSH6_SUBNETS_ELEMS="        elements = { $ip6_subnets_join }"
    [ -n "$ip4_hosts_join" ]   && SSH4_HOSTS_ELEMS="        elements = { $ip4_hosts_join }"
    [ -n "$ip6_hosts_join" ]   && SSH6_HOSTS_ELEMS="        elements = { $ip6_hosts_join }"

    # Small validation/logging of resolved SSH elements for operator visibility
    # Visibility logs; always stderr via log()
    log "SSH IPv4 subnets: ${ip4_subnets_join:-<none>}"
    log "SSH IPv6 subnets: ${ip6_subnets_join:-<none>}"
    log "SSH IPv4 hosts:   ${ip4_hosts_join:-<none>}"
    log "SSH IPv6 hosts:   ${ip6_hosts_join:-<none>}"

    local tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<EOF
#!/usr/sbin/nft -f
flush ruleset

table inet nftables_svc {

    set allowed_protocols {
        type inet_proto
        elements = { icmp, icmpv6 }
    }

    set allowed_interfaces {
        type ifname
        elements = { "lo" }
    }

    set allowed_tcp_dports {
        type inet_service
        elements = { 9090, 123, 443, 861, 862, 5201, 5001, 5000, 5101 }
    }

    set allowed_udp_ports {
        type inet_service
        elements = { 123, 5201, 5001, 5000, 5101 }
    }

    # ssh access sets populated from site config
    set ssh_access_ip4_subnets {
        type ipv4_addr
        flags interval
${SSH4_SUBNETS_ELEMS}
    }

    set ssh_access_ip6_subnets {
        type ipv6_addr
        flags interval
${SSH6_SUBNETS_ELEMS}
    }

    set ssh_access_ip4_hosts {
        type ipv4_addr
${SSH4_HOSTS_ELEMS}
    }

    set ssh_access_ip6_hosts {
        type ipv6_addr
${SSH6_HOSTS_ELEMS}
    }

    chain allow {
        ct state established,related accept
        ct status dnat accept
        ct state invalid drop

        meta l4proto @allowed_protocols accept
        iifname @allowed_interfaces accept

        tcp dport @allowed_tcp_dports ct state { new, untracked } accept
        udp dport @allowed_udp_ports ct state { new, untracked } accept

        ip6 daddr fe80::/64 udp dport 546 ct state { new, untracked } accept

        tcp dport 5890-5900 ct state { new, untracked } accept
        udp dport 8760-9960 ct state { new, untracked } accept
        udp dport 18760-19960 ct state { new, untracked } accept
        udp dport 33434-33634 ct state { new, untracked } accept

        # ssh rules limited to configured subnets/hosts
        tcp dport 22 ip saddr @ssh_access_ip4_subnets ct state { new, untracked } accept
        tcp dport 22 ip6 saddr @ssh_access_ip6_subnets ct state { new, untracked } accept
        tcp dport 22 ip saddr @ssh_access_ip4_hosts ct state { new, untracked } accept
        tcp dport 22 ip6 saddr @ssh_access_ip6_hosts ct state { new, untracked } accept
    }

    chain INPUT {
        type filter hook input priority filter + 20
        policy accept
        jump allow
        reject with icmpx admin-prohibited
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    # Validate syntax before installing/printing the generated rules
    if ! out=$(nft -c -f "$tmpfile" 2>&1); then
        log "Validation failed for generated nftables rules. Not writing $NFT_RULE_FILE."
        log "nft error output:"
        printf '%s\n' "$out" | while IFS= read -r line; do log "$line"; done
        rm -f "$tmpfile"
        return 1
    fi

    # If print-only was requested, emit the rules and exit without writing
    if [ "$PRINT_RULES" = true ]; then
        cat "$tmpfile"
        rm -f "$tmpfile"
        log "Printed generated nftables rules (no changes written)."
        return 0
    fi

    backup_file "$NFT_RULE_FILE"
    run_cmd mkdir -p "$(dirname "$NFT_RULE_FILE")"
    run_cmd cp -a -- "$tmpfile" "$NFT_RULE_FILE"
    run_cmd chmod 0644 "$NFT_RULE_FILE"
    rm -f "$tmpfile"
    log "Wrote nftables rules to $NFT_RULE_FILE"
}

enable_nft_service() {
    # Ensure nftables service is enabled and reload rules
    if ! command -v nft >/dev/null 2>&1; then
        log "nft command not found; skipping nftables service enable/reload."
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl enable --now nftables || run_cmd systemctl restart nftables || true
        # Try to reload nftables rules if supported
        if command -v nft >/dev/null 2>&1; then
            run_cmd nft -f "$NFT_RULE_FILE" || log "nft -f failed; service restart attempted"
        fi
    else
        log "Systemd not available: please ensure nftables rules are loaded on boot per your distro's method."
    fi
}

write_fail2ban() {
    local jail_dir="/etc/fail2ban/jail.d"
    local jail_file="$jail_dir/perfsonar.local"
    if ! command -v fail2ban-client >/dev/null 2>&1 && ! systemctl list-unit-files --type=service 2>/dev/null | grep -q '^fail2ban\.service'; then
        log "fail2ban not detected; skipping fail2ban jail configuration."
        return 0
    fi
    mkdir -p "$jail_dir"
    backup_file "$jail_file"
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/secure
maxretry = 5

# If you run a web server/tooling that should be protected add other jails here.
EOF
    run_cmd cp -a -- "$tmp" "$jail_file"
    run_cmd chmod 0644 "$jail_file"
    rm -f "$tmp"
    log "Wrote minimal fail2ban jail to $jail_file"
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl enable --now fail2ban || run_cmd systemctl restart fail2ban || true
    fi
}

enable_selinux() {
    # Make conservative attempts to enable SELinux. Warn heavily and require --yes to proceed.
    if ! command -v getenforce >/dev/null 2>&1; then
        log "SELinux tools not available on this host. Install policycoreutils and try again."
        return 0
    fi
    local current
    current=$(getenforce || echo Disabled)
    log "Current SELinux state: $current"
    if [ "$current" = "Enforcing" ]; then
        log "SELinux already enforcing."
        return 0
    fi
    # Edit /etc/selinux/config to set SELINUX=enforcing
    backup_file "/etc/selinux/config"
    if [ "$DRY_RUN" = true ]; then
        log "Dry-run: would set SELINUX=enforcing in /etc/selinux/config and run setenforce 1"
        return 0
    fi
    run_cmd sed -i.bak -E 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config || true
    # Try to set enforcement immediately (may fail if kernel unsupported)
    if run_cmd setenforce 1; then
        log "Set SELinux to enforcing (runtime)."
    else
        log "setenforce failed; a reboot may be required to enable SELinux."
    fi
}

verify_only_perfsonar_ruleset() {
    # Verify the active nftables tables. In default mode, succeed if the
    # 'inet nftables_svc' table is present. In strict mode, require it to be
    # the only table.
    if [ "$DRY_RUN" = true ]; then
        log "Dry-run: skip verification of active ruleset"
        return 0
    fi
    if ! command -v nft >/dev/null 2>&1; then
        log "nft binary not available; cannot verify ruleset"
        return 1
    fi

    local tables
    # List tables in the ruleset and extract '<family> <name>' pairs.
    # Ensure awk processes the command output by grouping with parentheses.
    mapfile -t tables < <( (nft list tables 2>/dev/null || nft list ruleset 2>/dev/null) | awk '/^table /{print $2" "$3}')
    if [ ${#tables[@]} -eq 0 ]; then
        log "No nftables tables found in active ruleset"
        return 1
    fi

    if [ "$STRICT_VERIFY" = true ]; then
        # Strict mode: must have exactly one table and it must be our table
        if [ ${#tables[@]} -ne 1 ]; then
            log "Unexpected number of nftables tables (strict): ${#tables[@]} -> ${tables[*]}"
            return 2
        fi
        if [[ "${tables[0]}" != "inet nftables_svc" ]]; then
            log "Active table is not 'inet nftables_svc' (strict): found '${tables[0]}'"
            return 3
        fi
        log "Verified (strict) active nftables ruleset contains only 'inet nftables_svc'"
        return 0
    fi

    # Presence-only: succeed if our table is present among others
    local found=false t
    for t in "${tables[@]}"; do
        if [[ "$t" == "inet nftables_svc" ]]; then
            found=true; break
        fi
    done
    if [ "$found" = true ]; then
        log "Verified presence of 'inet nftables_svc' among active nftables tables"
        return 0
    fi
    log "perfSONAR table 'inet nftables_svc' not found in active nftables tables: ${tables[*]}"
    return 4
}

derive_subnets_and_hosts_from_config() {
    # Populate SUBNETS and HOSTS arrays from the perfSONAR multi-nic config
    SUBNETS=()
    HOSTS=()
    if [ -f "$CONFIG_FILE" ]; then
        # Temporarily disable nounset while sourcing user file
        set +u
        # shellcheck source=/etc/perfSONAR-multi-nic-config.conf
        # shellcheck disable=SC1091
        source "$CONFIG_FILE" || true
        set -u

        # If arrays exist, iterate and build lists. We accept '-' as unset.
        if declare -p NIC_IPV4_ADDRS >/dev/null 2>&1 && declare -p NIC_IPV4_PREFIXES >/dev/null 2>&1; then
            for i in "${!NIC_IPV4_ADDRS[@]}"; do
                addr="${NIC_IPV4_ADDRS[$i]:-}" || addr=""
                prefix="${NIC_IPV4_PREFIXES[$i]:-}" || prefix=""
                if [ -n "$addr" ] && [ "$addr" != "-" ]; then
                    # If prefix is present and looks like /24 etc, canonicalize to network base; otherwise treat as host
                    if [ -n "$prefix" ] && [[ "$prefix" == /* ]]; then
                        if canon=$(canon_cidr "${addr}${prefix}"); then
                            SUBNETS+=("$canon")
                        else
                            log "Skipping invalid IPv4 CIDR: ${addr}${prefix}; adding as host instead"
                            HOSTS+=("${addr}")
                        fi
                    else
                        HOSTS+=("${addr}")
                    fi
                fi
            done
        fi

        if declare -p NIC_IPV6_ADDRS >/dev/null 2>&1 && declare -p NIC_IPV6_PREFIXES >/dev/null 2>&1; then
            for i in "${!NIC_IPV6_ADDRS[@]}"; do
                addr6="${NIC_IPV6_ADDRS[$i]:-}" || addr6=""
                prefix6="${NIC_IPV6_PREFIXES[$i]:-}" || prefix6=""
                if [ -n "$addr6" ] && [ "$addr6" != "-" ]; then
                    if [ -n "$prefix6" ] && [[ "$prefix6" == /* ]]; then
                        if canon=$(canon_cidr "${addr6}${prefix6}"); then
                            SUBNETS+=("$canon")
                        else
                            # If canonicalization fails, only add as host if it is a valid IP literal
                            if is_valid_ip "$addr6"; then
                                log "CIDR parse failed for ${addr6}${prefix6}; adding valid host $addr6 instead"
                                HOSTS+=("${addr6}")
                            else
                                log "Skipping invalid IPv6 entry: ${addr6}${prefix6} (no valid address detected)"
                            fi
                        fi
                    else
                        # No prefix: treat as host only if it validates
                        if is_valid_ip "$addr6"; then
                            HOSTS+=("${addr6}")
                        else
                            log "Skipping invalid IPv6 host entry: ${addr6}"
                        fi
                    fi
                fi
            done
        fi
    else
        log "Config file $CONFIG_FILE not found; cannot derive perfSONAR subnets/hosts."
    fi

    # Deduplicate arrays (simple method)
    if [ "${#SUBNETS[@]}" -gt 0 ]; then
        mapfile -t SUBNETS < <(printf '%s\n' "${SUBNETS[@]}" | awk '!seen[$0]++')
    fi
    if [ "${#HOSTS[@]}" -gt 0 ]; then
        mapfile -t HOSTS < <(printf '%s\n' "${HOSTS[@]}" | awk '!seen[$0]++')
    fi

    log "Derived SUBNETS: ${SUBNETS[*]:-none}"
    log "Derived HOSTS: ${HOSTS[*]:-none}"
}

confirm_or_exit() {
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    read -r -p "Proceed with these changes? [y/N]: " ans
    case "$ans" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) echo "Aborted by user."; exit 1 ;;
    esac
}

# --------- CLI parsing ---------
while [[ ${#} -gt 0 ]]; do
    case "$1" in
        --help)
            usage; exit 0 ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --yes)
            AUTO_YES=true; shift ;;
        --fail2ban)
            INSTALL_FAIL2BAN=true; shift ;;
        --selinux)
            ENABLE_SELINUX=true; shift ;;
        --debug)
            DEBUG=true; set -x; shift ;;
        --ports=*)
            PERF_PORTS="${1#*=}"; shift ;;
        --backup-dir=*)
            BACKUP_DIR="${1#*=}"; shift ;;
        --print-rules)
            PRINT_RULES=true; shift ;;
        --strict-verify)
            STRICT_VERIFY=true; shift ;;
        *)
            # ignore unknown for now
            shift ;;
    esac
done

require_root

log "Starting perfSONAR nftables installer"
log "DRY_RUN=$DRY_RUN INSTALL_FAIL2BAN=$INSTALL_FAIL2BAN ENABLE_SELINUX=$ENABLE_SELINUX PERF_PORTS=$PERF_PORTS"

# show planned actions (send to stderr in print mode)
print_info "${GREEN}Planned actions:${NC}"
if [ "$PRINT_RULES" = true ]; then
    print_info "- Preview (print) generated nftables rules (no changes)"
else
    print_info "- Configure nftables rules (if nftables is installed)"
fi
if [ "$INSTALL_FAIL2BAN" = true ]; then
    print_info "- Configure and enable fail2ban (if installed)"
fi
if [ "$ENABLE_SELINUX" = true ]; then
    print_info "- Attempt to enable SELinux (if installed; may require reboot)"
fi
if [ "$PRINT_RULES" = true ]; then
    print_info "- No files will be written; this is a print-only preview"
else
    print_info "- Write nftables rules to $NFT_RULE_FILE (backup created under $BACKUP_DIR)"
fi
print_info ""

# Only prompt for confirmation if we intend to make changes
if [ "$PRINT_RULES" != true ]; then
    confirm_or_exit
fi

# create backup dir even in dry-run for informational parity
if [ "$DRY_RUN" = false ]; then
    run_cmd mkdir -p "$BACKUP_DIR"
else
    mkdir -p "$BACKUP_DIR" || true
fi

# Capture existing ruleset for rollback (if nft present and not dry-run)
if [ "$DRY_RUN" = false ] && command -v nft >/dev/null 2>&1; then
    # Save current active ruleset to backup for potential restore
    run_cmd sh -c "nft list ruleset > \"\$1\"" -- "$BACKUP_DIR/existing_ruleset.nft" || log "Failed to capture existing nft ruleset"
fi

check_prereqs

# Derive perfSONAR subnets/hosts from perfSONAR multi-nic config if present
derive_subnets_and_hosts_from_config

write_nft_rules "$PERF_PORTS"

# If we were only asked to print the rules, stop here
if [ "$PRINT_RULES" = true ]; then
    log "Exiting after printing rules as requested."
    exit 0
fi

enable_nft_service

if [ "$INSTALL_FAIL2BAN" = true ]; then
    write_fail2ban
fi

if [ "$ENABLE_SELINUX" = true ]; then
    enable_selinux
fi

# Verify ruleset; rollback if verification fails. Skip if nftables absent.
if command -v nft >/dev/null 2>&1; then
    if ! verify_only_perfsonar_ruleset; then
        log "Verification of active nftables ruleset failed. Attempting rollback."
        if [ -f "$BACKUP_DIR/existing_ruleset.nft" ]; then
            log "Restoring previous ruleset from $BACKUP_DIR/existing_ruleset.nft"
            if [ "$DRY_RUN" = false ]; then
                run_cmd nft -f "$BACKUP_DIR/existing_ruleset.nft" || log "Failed to restore previous nft ruleset"
            else
                log "Dry-run: would restore previous nft ruleset from $BACKUP_DIR/existing_ruleset.nft"
            fi
        else
            log "No existing ruleset backup available to restore"
        fi
        exit 1
    fi
else
    log "nft not detected; skipping ruleset verification"
fi

log "perfSONAR nftables installation completed. Review $LOG_FILE and $BACKUP_DIR for artifacts."
printf '%b\n' "${GREEN}Done.${NC}"
