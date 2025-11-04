#!/bin/bash
# perfSONAR nftables installer and helper
# --------------------------------------
# Purpose:
#   Install and configure nftables for a perfSONAR testpoint host. Optionally
#   deploy a minimal fail2ban configuration and enable SELinux (with warnings).
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
  --fail2ban           Install and enable a minimal fail2ban config
  --selinux            Attempt to enable SELinux (may require reboot)
  --ports=CSV          Comma-separated list of TCP ports to allow (default: 22,80,443)
  --debug              Print commands (set -x) for troubleshooting
  --backup-dir=DIR     Where to store backups (default: auto under /var/backups)

Example:
  sudo ./perfSONAR-install-nftables.sh --fail2ban --ports=22,80,443,8085

Notes:
  - Run in a VM or console first. Use --dry-run to preview changes.
  - SELinux enablement is a potentially disruptive operation; read the
    script comments and test before enabling on production hosts.
EOF
}

log() {
    local ts
    ts=$(date +'%Y-%m-%d %H:%M:%S')
    printf '%s %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
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

detect_pkg_manager() {
    if command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v yum >/dev/null 2>&1; then
        echo yum
    elif command -v apt-get >/dev/null 2>&1; then
        echo apt
    elif command -v zypper >/dev/null 2>&1; then
        echo zypper
    else
        echo unknown
    fi
}

install_packages() {
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)
    case "$pkg_mgr" in
        dnf|yum)
            run_cmd "$pkg_mgr" -y install nftables
            if [ "$INSTALL_FAIL2BAN" = true ]; then
                run_cmd "$pkg_mgr" -y install fail2ban
            fi
            ;;
        apt)
            run_cmd apt-get update
            run_cmd apt-get -y install nftables
            if [ "$INSTALL_FAIL2BAN" = true ]; then
                run_cmd apt-get -y install fail2ban
            fi
            ;;
        zypper)
            run_cmd zypper --non-interactive install nftables
            if [ "$INSTALL_FAIL2BAN" = true ]; then
                run_cmd zypper --non-interactive install fail2ban
            fi
            ;;
        *)
            log "Unsupported package manager: $pkg_mgr. Install nftables and fail2ban manually."
            ;;
    esac
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
    local tmpfile
    tmpfile=$(mktemp)
    # Write a richer perfSONAR nftables ruleset inspired by the example provided.
    cat > "$tmpfile" <<'EOF'
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

    # ssh access sets: elements filled below by the installer
    set ssh_access_ip4_subnets {
        type ipv4_addr
        flags interval
        elements = { }
    }

    set ssh_access_ip6_subnets {
        type ipv6_addr
        flags interval
        elements = { }
    }

    set ssh_access_ip4_hosts {
        type ipv4_addr
        elements = { }
    }

    set ssh_access_ip6_hosts {
        type ipv6_addr
        elements = { }
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

        # ssh rules (will be limited to configured subnets/hosts)
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

}
EOF

    # Now append elements for the ssh access sets derived from SUBNETS/HOSTS
    # We build a small temporary file with the 'add element' commands and then
    # concat it into the main nft file so we don't need to regenerate the whole
    # structure stringly.
    local tmp_add
    tmp_add=$(mktemp)

    # Populate ssh_access_ip4_subnets and ssh_access_ip6_subnets
    for s in "${SUBNETS[@]:-}"; do
        [ -z "$s" ] && continue
        if [[ "$s" == *":"* ]]; then
            printf 'add element inet nftables_svc ssh_access_ip6_subnets { %s }\n' "$s" >> "$tmp_add"
        else
            printf 'add element inet nftables_svc ssh_access_ip4_subnets { %s }\n' "$s" >> "$tmp_add"
        fi
    done

    # Populate hosts
    for h in "${HOSTS[@]:-}"; do
        [ -z "$h" ] && continue
        if [[ "$h" == *":"* ]]; then
            printf 'add element inet nftables_svc ssh_access_ip6_hosts { %s }\n' "$h" >> "$tmp_add"
        else
            printf 'add element inet nftables_svc ssh_access_ip4_hosts { %s }\n' "$h" >> "$tmp_add"
        fi
    done

    # If any values were added, append them to the rules file
    if [ -s "$tmp_add" ]; then
        cat "$tmp_add" >> "$tmpfile"
    fi
    rm -f "$tmp_add"

    cat >> "$tmpfile" <<'EOF'

        # allow ssh rate-limited at service level (use fail2ban for stronger policies)
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    # Backup existing nft file and atomically move in place
    backup_file "$NFT_RULE_FILE"
    run_cmd mkdir -p "$(dirname "$NFT_RULE_FILE")"
    run_cmd cp -a -- "$tmpfile" "$NFT_RULE_FILE"
    run_cmd chmod 0644 "$NFT_RULE_FILE"
    rm -f "$tmpfile"
    log "Wrote nftables rules to $NFT_RULE_FILE"
}

enable_nft_service() {
    # Ensure nftables service is enabled and reload rules
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
    # Verify that the active nftables ruleset contains only the perfSONAR table
    # (table inet nftables_svc) and no other tables. Returns 0 on success.
    if [ "$DRY_RUN" = true ]; then
        log "Dry-run: skip verification of active ruleset"
        return 0
    fi
    if ! command -v nft >/dev/null 2>&1; then
        log "nft binary not available; cannot verify ruleset"
        return 1
    fi

    local tables
    # list tables in the ruleset; output lines starting with 'table'
    # format: table <family> <name> {
    mapfile -t tables < <(nft list tables 2>/dev/null || nft list ruleset 2>/dev/null | awk '/^table /{print $2" "$3}')
    if [ ${#tables[@]} -eq 0 ]; then
        log "No nftables tables found in active ruleset"
        return 1
    fi

    # Expect exactly one table named 'inet nftables_svc'
    if [ ${#tables[@]} -ne 1 ]; then
        log "Unexpected number of nftables tables: ${#tables[@]} -> ${tables[*]}"
        return 2
    fi

    if [[ "${tables[0]}" != "inet nftables_svc" ]]; then
        log "Active table is not 'inet nftables_svc': found '${tables[0]}'"
        return 3
    fi

    log "Verified active nftables ruleset contains only 'inet nftables_svc'"
    return 0
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
                    # If prefix is present and looks like /24 etc, combine; otherwise use /32
                    if [ -n "$prefix" ] && [[ "$prefix" == /* ]]; then
                        SUBNETS+=("${addr}${prefix}")
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
                        SUBNETS+=("${addr6}${prefix6}")
                    else
                        HOSTS+=("${addr6}")
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
        *)
            # ignore unknown for now
            shift ;;
    esac
done

require_root

log "Starting perfSONAR nftables installer"
log "DRY_RUN=$DRY_RUN INSTALL_FAIL2BAN=$INSTALL_FAIL2BAN ENABLE_SELINUX=$ENABLE_SELINUX PERF_PORTS=$PERF_PORTS"

# show planned actions
printf '%b\n' "${GREEN}Planned actions:${NC}"
echo "- Install nftables (if missing)"
if [ "$INSTALL_FAIL2BAN" = true ]; then
    echo "- Install and enable fail2ban"
fi
if [ "$ENABLE_SELINUX" = true ]; then
    echo "- Attempt to enable SELinux (may require reboot)"
fi
echo "- Write nftables rules to $NFT_RULE_FILE (backup created under $BACKUP_DIR)"
echo

confirm_or_exit

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

install_packages

# Derive perfSONAR subnets/hosts from perfSONAR multi-nic config if present
derive_subnets_and_hosts_from_config

write_nft_rules "$PERF_PORTS"

enable_nft_service

if [ "$INSTALL_FAIL2BAN" = true ]; then
    write_fail2ban
fi

if [ "$ENABLE_SELINUX" = true ]; then
    enable_selinux
fi

# Verify that only our perfSONAR ruleset is active; rollback if verification fails
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

log "perfSONAR nftables installation completed. Review $LOG_FILE and $BACKUP_DIR for artifacts."
printf '%b\n' "${GREEN}Done.${NC}"
