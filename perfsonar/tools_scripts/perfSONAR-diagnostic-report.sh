#!/usr/bin/env bash
set -euo pipefail

# perfSONAR-diagnostic-report.sh
# --------------------------------
# Collects comprehensive diagnostic information from a perfSONAR deployment
# (container testpoint or RPM toolkit) and writes a single, self-contained
# report file that can be shared with support staff for remote troubleshooting.
#
# The script is read-only — it never modifies any system state, configuration,
# or running services.  It can be run safely at any time.
#
# Supported deployment types:
#   container  — perfSONAR testpoint running via podman-compose / docker-compose
#   toolkit    — perfSONAR toolkit installed from RPM packages (dnf)
#
# Version: 1.0.0 - 2026-02-26
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Usage:
#   perfSONAR-diagnostic-report.sh [OPTIONS]
#
# Options:
#   --base DIR      Base directory (default: auto-detect)
#   --type TYPE     Deployment type: container or toolkit (default: auto-detect)
#   --output FILE   Output report file path (default: /tmp/perfsonar-diag-<hostname>-<date>.txt)
#   --no-color      Disable coloured terminal output
#   --brief         Skip verbose sections (container logs, full journal)
#   --version       Show script version
#   --help, -h      Show this help message
#
# Exit codes:
#   0  Report generated successfully
#   1  Fatal error (missing dependencies, not root, etc.)
#   2  Invalid arguments

VERSION="1.0.0"
PROG_NAME="$(basename "$0")"

# --- Defaults --------------------------------------------------------------
BASE_DIR=""
DEPLOY_TYPE=""
OUTPUT_FILE=""
BRIEF=false
USE_COLOR=true

# --- Colours (disabled when piped or --no-color) ---------------------------
setup_colors() {
    if [[ "$USE_COLOR" == true ]] && [[ -t 1 ]]; then
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_RED='\033[0;31m'
        C_CYAN='\033[1;36m'
        C_RESET='\033[0m'
    else
        C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_RESET=''
    fi
}

# --- Helpers ---------------------------------------------------------------
info()  { printf "${C_GREEN}[INFO]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }
error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
ok()    { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$*"; }

# Section header (terminal + report)
section() {
    local title="$1"
    {
        echo ""
        echo "========================================================================"
        echo "  $title"
        echo "========================================================================"
        echo ""
    } >> "$OUTPUT_FILE"
    printf "${C_CYAN}[SECTION]${C_RESET} %s\n" "$title"
}

# Run a command, capture output to report.  Shows pass/fail on terminal.
# Usage: collect "label" command [args...]
collect() {
    local label="$1"; shift
    {
        echo "--- $label ---"
        echo "  Command: $*"
        echo ""
    } >> "$OUTPUT_FILE"

    local rc=0
    # shellcheck disable=SC2068
    $@ >> "$OUTPUT_FILE" 2>&1 || rc=$?

    {
        echo ""
        echo "  Exit code: $rc"
        echo ""
    } >> "$OUTPUT_FILE"

    if [[ $rc -eq 0 ]]; then
        printf "  ${C_GREEN}✓${C_RESET} %s\n" "$label"
    else
        printf "  ${C_YELLOW}✗${C_RESET} %s (exit %d)\n" "$label" "$rc"
    fi
    return 0  # never fail the overall script
}

# Write arbitrary text to the report
emit() {
    echo "$*" >> "$OUTPUT_FILE"
}

# --- CLI -------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage: perfSONAR-diagnostic-report.sh [OPTIONS]

Collect diagnostic information from a perfSONAR deployment and write a
self-contained report file for remote troubleshooting support.

This script is READ-ONLY — it never modifies system state.

Options:
  --base DIR      Base directory (default: auto-detect)
  --type TYPE     Deployment type: container or toolkit (default: auto-detect)
  --output FILE   Output file (default: /tmp/perfsonar-diag-<hostname>-<date>.txt)
  --no-color      Disable coloured terminal output
  --brief         Skip verbose sections (container logs, full journal)
  --version       Show script version
  --help, -h      Show this help message
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)       shift; BASE_DIR="${1:?--base requires a directory}"; shift ;;
            --type)       shift; DEPLOY_TYPE="${1:?--type requires container or toolkit}"; shift ;;
            --output)     shift; OUTPUT_FILE="${1:?--output requires a file path}"; shift ;;
            --no-color)   USE_COLOR=false; shift ;;
            --brief)      BRIEF=true; shift ;;
            --version)    echo "$PROG_NAME version $VERSION"; exit 0 ;;
            -h|--help)    usage; exit 0 ;;
            *)            error "Unknown argument: $1"; usage; exit 2 ;;
        esac
    done

    if [[ -n "$DEPLOY_TYPE" ]] && [[ "$DEPLOY_TYPE" != "container" && "$DEPLOY_TYPE" != "toolkit" ]]; then
        error "--type must be 'container' or 'toolkit' (got: $DEPLOY_TYPE)"
        exit 2
    fi
}

# --- Detection (mirrors update-perfsonar-deployment.sh) --------------------
detect_deploy_type() {
    if [[ -n "$BASE_DIR" && -f "$BASE_DIR/docker-compose.yml" ]]; then
        echo "container"; return
    fi
    for d in /opt/perfsonar-tp /opt/perfsonar; do
        if [[ -f "$d/docker-compose.yml" ]]; then echo "container"; return; fi
    done
    if rpm -q perfsonar-toolkit &>/dev/null || rpm -q perfsonar-testpoint &>/dev/null; then
        echo "toolkit"; return
    fi
    if systemctl list-unit-files pscheduler-scheduler.service &>/dev/null 2>&1; then
        echo "toolkit"; return
    fi
    echo "unknown"
}

detect_base_dir() {
    local dtype="$1"
    if [[ "$dtype" == "container" ]]; then
        for d in /opt/perfsonar-tp /opt/perfsonar; do
            [[ -f "$d/docker-compose.yml" ]] && { echo "$d"; return; }
        done
        echo "/opt/perfsonar-tp"
    else
        for d in /opt/perfsonar-toolkit /opt/perfsonar-tp /opt/perfsonar; do
            [[ -d "$d/tools_scripts" ]] && { echo "$d"; return; }
        done
        echo "/opt/perfsonar-toolkit"
    fi
}

# --- Preflight -------------------------------------------------------------
preflight() {
    info "perfSONAR Diagnostic Report v${VERSION}"
    echo

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (or with sudo)."
        exit 1
    fi

    # Auto-detect deployment type
    if [[ -z "$DEPLOY_TYPE" ]]; then
        DEPLOY_TYPE=$(detect_deploy_type)
        if [[ "$DEPLOY_TYPE" == "unknown" ]]; then
            error "Could not auto-detect deployment type."
            error "Use --type container or --type toolkit to specify."
            exit 1
        fi
        info "Auto-detected deployment type: $DEPLOY_TYPE"
    fi

    # Auto-detect base directory
    if [[ -z "$BASE_DIR" ]]; then
        BASE_DIR=$(detect_base_dir "$DEPLOY_TYPE")
    fi
    TOOLS_DIR="$BASE_DIR/tools_scripts"
    CONF_DIR="$BASE_DIR/conf"

    # Container runtime detection
    RUNTIME=""
    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        if command -v podman >/dev/null 2>&1; then
            RUNTIME="podman"
        elif command -v docker >/dev/null 2>&1; then
            RUNTIME="docker"
        fi
    fi

    # Default output file
    if [[ -z "$OUTPUT_FILE" ]]; then
        local hostname_short
        hostname_short=$(hostname -s 2>/dev/null || echo "unknown")
        OUTPUT_FILE="/tmp/perfsonar-diag-${hostname_short}-$(date -u +%Y%m%dT%H%M%SZ).txt"
    fi

    # Initialise the report file
    : > "$OUTPUT_FILE"
    emit "perfSONAR Diagnostic Report"
    emit "Generated: $(date -Iseconds)"
    emit "Script version: $VERSION"
    emit "Hostname: $(hostname -f 2>/dev/null || hostname)"
    emit "Deployment type: $DEPLOY_TYPE"
    emit "Base directory: $BASE_DIR"
    [[ -n "$RUNTIME" ]] && emit "Container runtime: $RUNTIME"
    emit ""

    info "Deployment type:   $DEPLOY_TYPE"
    info "Base directory:    $BASE_DIR"
    info "Output file:       $OUTPUT_FILE"
    echo
}

# ═══════════════════════════════════════════════════════════════════════════
#  DIAGNOSTIC SECTIONS
# ═══════════════════════════════════════════════════════════════════════════

# --- 1. Host environment ---------------------------------------------------
collect_host_environment() {
    section "Host Environment"

    collect "OS release" cat /etc/os-release
    collect "Kernel" uname -r
    collect "Architecture" uname -m
    collect "Uptime" uptime
    collect "Date/time/timezone" timedatectl status
    collect "Memory" free -h
    collect "Disk space" df -h /opt /var /tmp /etc 2>/dev/null
    collect "CPU info (summary)" lscpu
}

# --- 2. Network configuration ---------------------------------------------
collect_network() {
    section "Network Configuration"

    collect "IP addresses" ip -br addr
    collect "Default routes" ip route show default
    collect "IPv6 default routes" ip -6 route show default
    collect "Routing rules (policy routing)" ip rule show
    collect "DNS resolver" cat /etc/resolv.conf
    collect "Listening ports (tcp)" ss -tlnp
    collect "Listening ports (udp)" ss -ulnp

    # NetworkManager connections (if present)
    if command -v nmcli &>/dev/null; then
        collect "NetworkManager connections" nmcli connection show
        collect "NetworkManager device status" nmcli device status
    fi

    # Firewall
    if command -v nft &>/dev/null; then
        collect "nftables ruleset" nft list ruleset
    fi
    if command -v iptables &>/dev/null; then
        collect "iptables rules" iptables -L -n -v
    fi


    # Forward & reverse DNS
    local fqdn
    fqdn=$(hostname -f 2>/dev/null || hostname)
    if command -v dig &>/dev/null; then
        collect "DNS A record ($fqdn)" dig +short A "$fqdn"
        collect "DNS AAAA record ($fqdn)" dig +short AAAA "$fqdn"
        # Reverse lookups for each non-loopback IPv4
        local ip
        while read -r ip; do
            [[ -n "$ip" ]] && collect "DNS PTR ($ip)" dig +short -x "$ip"
        done < <(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1)
    elif command -v host &>/dev/null; then
        collect "DNS lookup ($fqdn)" host "$fqdn"
    fi

    # perfSONAR multi-NIC config
    if [[ -f /etc/perfSONAR-multi-nic-config.conf ]]; then
        collect "Multi-NIC config" cat /etc/perfSONAR-multi-nic-config.conf
    fi

    # Check DNS consistency script if available
    if [[ -x "$TOOLS_DIR/check-perfsonar-dns.sh" ]]; then
        collect "DNS consistency check" bash "$TOOLS_DIR/check-perfsonar-dns.sh"
    fi
}

# --- 3. SELinux & security ------------------------------------------------
collect_selinux() {
    section "SELinux & Security"

    if command -v getenforce &>/dev/null; then
        collect "SELinux mode" getenforce
        collect "SELinux booleans (container)" getsebool -a 2>/dev/null
    else
        emit "SELinux: not available (getenforce not found)"
    fi

    # Check SELinux labels on critical shared directories
    for dir in /etc/letsencrypt /var/www/html /etc/apache2; do
        [[ -d "$dir" ]] && collect "SELinux label: $dir" ls -dZ "$dir"
    done

    # Check for MCS label issues (known bug from :Z mounts)
    if command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
        emit ""
        emit "--- MCS label check (known :Z volume mount issue) ---"
        local bad_mcs=false
        for dir in /etc/letsencrypt /var/www/html; do
            if [[ -d "$dir" ]]; then
                local ctx
                ctx=$(ls -dZ "$dir" 2>/dev/null | awk '{print $1}')
                if echo "$ctx" | grep -qE ':s0:c[0-9]'; then
                    emit "  WARNING: $dir has private MCS category: $ctx"
                    emit "           This will block container access. Fix with:"
                    emit "           chcon -R -t container_file_t -l s0 $dir"
                    bad_mcs=true
                else
                    emit "  OK: $dir label is $ctx (no private MCS)"
                fi
            fi
        done
        [[ "$bad_mcs" == true ]] && printf "  ${C_RED}✗${C_RESET} Private MCS labels detected — see report for details\n"
        [[ "$bad_mcs" == false ]] && printf "  ${C_GREEN}✓${C_RESET} SELinux MCS labels OK\n"
    fi
}

# --- 4. Container-specific diagnostics ------------------------------------
collect_container() {
    [[ "$DEPLOY_TYPE" != "container" ]] && return
    [[ -z "$RUNTIME" ]] && { emit "Container runtime not found"; return; }

    section "Container Runtime"

    collect "$RUNTIME version" $RUNTIME --version
    if [[ "$RUNTIME" == "podman" ]]; then
        collect "podman system info" podman info
    fi
    collect "Container images" $RUNTIME images
    collect "All containers" $RUNTIME ps -a

    # Detailed container inspect
    if $RUNTIME ps -a --format '{{.Names}}' 2>/dev/null | grep -q perfsonar-testpoint; then
        collect "testpoint container inspect" $RUNTIME inspect perfsonar-testpoint

        # Container logs (last 100 lines or last 50 if --brief)
        local log_lines=100
        [[ "$BRIEF" == true ]] && log_lines=50
        collect "testpoint container logs (last $log_lines lines)" $RUNTIME logs --tail "$log_lines" perfsonar-testpoint

        # Can we exec into the container?
        if $RUNTIME exec perfsonar-testpoint true 2>/dev/null; then
            collect "Container systemd units (active)" \
                $RUNTIME exec perfsonar-testpoint systemctl list-units --type=service --state=active --no-pager --no-legend
            collect "Container systemd units (failed)" \
                $RUNTIME exec perfsonar-testpoint systemctl list-units --type=service --state=failed --no-pager --no-legend
            collect "Container: Apache status" \
                $RUNTIME exec perfsonar-testpoint systemctl status apache2 --no-pager
            collect "Container: pScheduler services" \
                $RUNTIME exec perfsonar-testpoint systemctl status 'pscheduler-*' --no-pager
            collect "Container: node_exporter status" \
                $RUNTIME exec perfsonar-testpoint systemctl status node_exporter --no-pager
            collect "Container: node_exporter defaults" \
                $RUNTIME exec perfsonar-testpoint cat /etc/default/node_exporter
            collect "Container: node_exporter direct test" \
                $RUNTIME exec perfsonar-testpoint curl -s -o /dev/null -w 'HTTP %{http_code}' http://127.0.0.1:9100/metrics
            collect "Container: pscheduler troubleshoot --quick" \
                $RUNTIME exec perfsonar-testpoint pscheduler troubleshoot --quick
            collect "Container: Apache error log (last 30 lines)" \
                $RUNTIME exec perfsonar-testpoint tail -30 /var/log/apache2/error.log
            collect "Container: Apache SSL config" \
                $RUNTIME exec perfsonar-testpoint grep -E 'SSLCertificate|Listen|ProxyPass' /etc/apache2/sites-available/default-ssl.conf
            collect "Container: PostgreSQL status" \
                $RUNTIME exec perfsonar-testpoint systemctl status postgresql --no-pager
            collect "Container: psconfig agent status" \
                $RUNTIME exec perfsonar-testpoint systemctl status psconfig-pscheduler-agent --no-pager
            collect "Container: owamp-server status" \
                $RUNTIME exec perfsonar-testpoint systemctl status owamp-server --no-pager
            collect "Container: listening ports" \
                $RUNTIME exec perfsonar-testpoint ss -tlnp
            collect "Container: disk usage" \
                $RUNTIME exec perfsonar-testpoint df -h
            collect "Container: journal errors (last 50)" \
                $RUNTIME exec perfsonar-testpoint journalctl -p err -n 50 --no-pager
        else
            emit ""
            emit "  WARNING: Cannot exec into perfsonar-testpoint container."
            emit "  Container state may be 'Initialized' or 'Exited'."
            warn "  Cannot exec into container — it may not be running"
        fi
    fi

    # Certbot container (if present)
    if $RUNTIME ps -a --format '{{.Names}}' 2>/dev/null | grep -q certbot; then
        collect "certbot container status" $RUNTIME inspect certbot
        collect "certbot logs (last 30 lines)" $RUNTIME logs --tail 30 certbot
    fi

    # Pods (podman)
    if [[ "$RUNTIME" == "podman" ]]; then
        collect "Podman pods" podman pod list
    fi
}

# --- 5. Compose & service file configuration ------------------------------
collect_config_files() {
    section "Configuration Files"

    # docker-compose.yml
    if [[ -f "$BASE_DIR/docker-compose.yml" ]]; then
        collect "docker-compose.yml" cat "$BASE_DIR/docker-compose.yml"
    fi

    # node_exporter defaults
    if [[ -f "$CONF_DIR/node_exporter.defaults" ]]; then
        collect "node_exporter.defaults (host)" cat "$CONF_DIR/node_exporter.defaults"
    else
        emit "  node_exporter.defaults not found at $CONF_DIR/node_exporter.defaults"
    fi

    # Systemd service files
    for svc_file in /etc/systemd/system/perfsonar-*.service /etc/systemd/system/perfsonar-*.timer; do
        [[ -f "$svc_file" ]] && collect "$(basename "$svc_file")" cat "$svc_file"
    done

    # Check for missing volume mounts in the service file (known v1.5.4 bug)
    local svc="/etc/systemd/system/perfsonar-testpoint.service"
    if [[ -f "$svc" ]]; then
        emit ""
        emit "--- Service file volume mount check ---"
        local missing=()
        grep -q '/run/dbus:/run/dbus' "$svc" || missing+=("/run/dbus:/run/dbus:ro")
        grep -q 'node_exporter.defaults' "$svc" || missing+=("node_exporter.defaults mount")
        if [[ ${#missing[@]} -eq 0 ]]; then
            emit "  OK: All required volume mounts present"
            printf "  ${C_GREEN}✓${C_RESET} Service file volume mounts OK\n"
        else
            emit "  MISSING volume mounts: ${missing[*]}"
            emit "  Fix: run update-perfsonar-deployment.sh --apply --restart --yes"
            printf "  ${C_RED}✗${C_RESET} Service file missing mounts: ${missing[*]}\n"
        fi
    fi

    # psconfig mesh configuration
    local psconfig_dir="$BASE_DIR/psconfig"
    if [[ -d "$psconfig_dir" ]]; then
        collect "psconfig directory listing" ls -la "$psconfig_dir"
        for f in "$psconfig_dir"/*.json "$psconfig_dir"/*.conf; do
            [[ -f "$f" ]] && collect "$(basename "$f")" cat "$f"
        done
    fi

    # Tools scripts versions
    if [[ -d "$TOOLS_DIR" ]]; then
        emit ""
        emit "--- Helper script versions ---"
        for f in "$TOOLS_DIR"/*.sh; do
            [[ -f "$f" ]] || continue
            local ver
            ver=$(grep -m1 '^# Version:' "$f" 2>/dev/null | sed 's/^# Version: *//' || echo "?")
            emit "  $(basename "$f"): $ver"
        done
    fi
}

# --- 6. Toolkit (RPM) specific diagnostics --------------------------------
collect_toolkit() {
    [[ "$DEPLOY_TYPE" != "toolkit" ]] && return

    section "Toolkit (RPM) Deployment"

    collect "Installed perfSONAR packages" rpm -qa 'perfsonar*' --queryformat '%{NAME}-%{VERSION}-%{RELEASE}\n'
    collect "pScheduler packages" rpm -qa 'pscheduler*' --queryformat '%{NAME}-%{VERSION}-%{RELEASE}\n'

    # Service status
    local toolkit_services=(
        httpd pscheduler-scheduler pscheduler-runner pscheduler-archiver pscheduler-ticker
        psconfig-pscheduler-agent owamp-server postgresql
    )
    for svc in "${toolkit_services[@]}"; do
        if systemctl list-unit-files "${svc}.service" &>/dev/null 2>&1; then
            collect "Service: $svc" systemctl status "$svc" --no-pager
        fi
    done

    collect "Failed systemd units" systemctl list-units --type=service --state=failed --no-pager
    collect "pscheduler troubleshoot" pscheduler troubleshoot --quick

    # Apache config
    if [[ -f /etc/httpd/conf.d/ssl.conf ]]; then
        collect "Apache SSL config (httpd)" grep -E 'SSLCertificate|Listen|ProxyPass' /etc/httpd/conf.d/ssl.conf
    fi
    if [[ -d /etc/httpd/conf.d ]]; then
        collect "Apache conf.d listing" ls -la /etc/httpd/conf.d/
    fi

    # Node exporter
    if systemctl list-unit-files node_exporter.service &>/dev/null 2>&1; then
        collect "node_exporter status" systemctl status node_exporter --no-pager
    fi
    if [[ -f /etc/default/node_exporter ]]; then
        collect "node_exporter defaults" cat /etc/default/node_exporter
    elif [[ -f /etc/sysconfig/node_exporter ]]; then
        collect "node_exporter sysconfig" cat /etc/sysconfig/node_exporter
    fi

    # PostgreSQL
    collect "PostgreSQL version" psql --version
    collect "pScheduler database check" sudo -u postgres psql -d pscheduler -c "SELECT COUNT(*) AS pending_runs FROM run WHERE state < 2;" 2>/dev/null

    # Apache access test
    collect "Apache HTTPS test (localhost)" curl -kSs -o /dev/null -w 'HTTP %{http_code}' https://localhost/

    # Journal errors
    if [[ "$BRIEF" != true ]]; then
        collect "System journal errors (last 50)" journalctl -p err -n 50 --no-pager
    fi
}

# --- 7. Endpoint connectivity tests ---------------------------------------
collect_endpoints() {
    section "Endpoint Connectivity Tests"

    local fqdn
    fqdn=$(hostname -f 2>/dev/null || hostname)

    # Test from localhost (bypasses firewall, tests service directly)
    emit "--- Tests from localhost (curl -kSs) ---"
    local endpoints=(
        "/"
        "/pscheduler/"
        "/node_exporter/metrics"
        "/perfsonar_host_exporter/"
    )
    for ep in "${endpoints[@]}"; do
        local url="https://localhost${ep}"
        local label="HTTPS $ep"
        collect "$label" curl -kSs -o /dev/null -w 'HTTP %{http_code}  time_total=%{time_total}s  size=%{size_download}B' --max-time 10 "$url"
    done

    # Test using FQDN (tests DNS + firewall + cert)
    if [[ "$fqdn" != "localhost" ]]; then
        emit ""
        emit "--- Tests via FQDN: $fqdn ---"
        for ep in "${endpoints[@]}"; do
            local url="https://${fqdn}${ep}"
            local label="FQDN HTTPS $ep"
            collect "$label" curl -kSs -o /dev/null -w 'HTTP %{http_code}  time_total=%{time_total}s  size=%{size_download}B' --max-time 10 "$url"
        done

        # SSL certificate check
        collect "SSL certificate details" bash -c "echo | openssl s_client -connect ${fqdn}:443 -servername ${fqdn} 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null"
    fi

    # Test OWAMP port
    collect "OWAMP port 861 (tcp)" bash -c "timeout 3 bash -c '</dev/tcp/localhost/861' 2>/dev/null && echo 'OPEN' || echo 'CLOSED/TIMEOUT'"

    # Test external connectivity for pScheduler
    collect "External HTTPS to pScheduler API" bash -c "curl -kSs -o /dev/null -w 'HTTP %{http_code}' --max-time 10 https://localhost/pscheduler/tests 2>/dev/null || echo 'FAILED'"
}

# --- 8. Let's Encrypt / TLS -----------------------------------------------
collect_tls() {
    section "TLS / Let's Encrypt Certificates"

    if [[ -d /etc/letsencrypt/live ]]; then
        collect "LE certificate directories" ls -la /etc/letsencrypt/live/
        for certdir in /etc/letsencrypt/live/*/; do
            [[ -d "$certdir" ]] || continue
            local domain
            domain=$(basename "$certdir")
            [[ "$domain" == "README" ]] && continue
            if [[ -f "${certdir}fullchain.pem" ]]; then
                collect "Certificate: $domain" openssl x509 -in "${certdir}fullchain.pem" -noout -subject -issuer -dates -ext subjectAltName
            fi
        done
        collect "LE renewal configs" ls -la /etc/letsencrypt/renewal/ 2>/dev/null
        for ren in /etc/letsencrypt/renewal/*.conf; do
            [[ -f "$ren" ]] && collect "$(basename "$ren")" cat "$ren"
        done
    else
        emit "  /etc/letsencrypt/live not found — no Let's Encrypt certificates"
    fi

    # certbot cron/timer
    if systemctl list-unit-files certbot.timer &>/dev/null 2>&1; then
        collect "certbot timer" systemctl status certbot.timer --no-pager
    fi
}

# --- 9. Systemd unit status -----------------------------------------------
collect_systemd() {
    section "Systemd Units & Timers"

    local units=(
        perfsonar-testpoint.service
        perfsonar-certbot.service
        perfsonar-auto-update.service
        perfsonar-auto-update.timer
        perfsonar-health-monitor.service
        perfsonar-health-monitor.timer
    )
    for unit in "${units[@]}"; do
        if systemctl list-unit-files "$unit" &>/dev/null 2>&1; then
            collect "$unit" systemctl status "$unit" --no-pager
        fi
    done

    # Auto-update and health monitor logs
    for logfile in /var/log/perfsonar-auto-update.log /var/log/perfsonar-health-monitor.log /var/log/perfsonar-orchestrator.log; do
        if [[ -f "$logfile" ]]; then
            local lines=30
            [[ "$BRIEF" == true ]] && lines=10
            collect "$(basename "$logfile") (last $lines lines)" tail -"$lines" "$logfile"
        fi
    done

    # Journal for perfsonar-testpoint service
    if systemctl list-unit-files perfsonar-testpoint.service &>/dev/null 2>&1; then
        local jlines=50
        [[ "$BRIEF" == true ]] && jlines=20
        collect "Journal: perfsonar-testpoint.service (last $jlines)" \
            journalctl -u perfsonar-testpoint.service -n "$jlines" --no-pager
    fi
}

# --- 10. Network tuning ---------------------------------------------------
collect_tuning() {
    section "Network Tuning & Kernel Parameters"

    # Key sysctl values that affect perfSONAR throughput
    local params=(
        net.core.rmem_max
        net.core.rmem_default
        net.core.wmem_max
        net.core.wmem_default
        net.ipv4.tcp_rmem
        net.ipv4.tcp_wmem
        net.ipv4.tcp_no_metrics_save
        net.ipv4.tcp_mtu_probing
        net.ipv4.tcp_congestion_control
        net.ipv4.tcp_available_congestion_control
        net.ipv4.tcp_allowed_congestion_control
        net.core.default_qdisc
        net.core.netdev_max_backlog
        net.ipv4.conf.all.arp_ignore
        net.ipv4.conf.all.arp_announce
    )
    {
        echo "--- Key sysctl parameters ---"
        for p in "${params[@]}"; do
            printf "  %-50s = %s\n" "$p" "$(sysctl -n "$p" 2>/dev/null || echo 'N/A')"
        done
    } >> "$OUTPUT_FILE"
    printf "  ${C_GREEN}✓${C_RESET} Sysctl parameters collected\n"

    # Network interface ring buffers and qdisc
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    if [[ -n "$iface" ]]; then
        collect "ethtool ring ($iface)" ethtool -g "$iface"
        collect "ethtool offloads ($iface)" ethtool -k "$iface"
        collect "tc qdisc" tc qdisc show dev "$iface"
    fi

    # MTU
    collect "Network device MTUs" ip -o link show

    # fasterdata tuning state
    if [[ -x "$TOOLS_DIR/fasterdata-tuning.sh" ]]; then
        collect "fasterdata-tuning.sh --mode audit" bash "$TOOLS_DIR/fasterdata-tuning.sh" --mode audit
    fi
}

# --- 11. Known-issue checks -----------------------------------------------
collect_known_issues() {
    section "Known Issue Checks"

    emit "Running targeted checks for previously-identified bugs..."
    emit ""

    # Check 1: cpufreq panic (procfs v0.10.0)
    emit "--- Check: node_exporter cpufreq panic workaround ---"
    if [[ "$DEPLOY_TYPE" == "container" && -f "$CONF_DIR/node_exporter.defaults" ]]; then
        if grep -q '\-\-no-collector.cpufreq' "$CONF_DIR/node_exporter.defaults" 2>/dev/null; then
            emit "  OK: --no-collector.cpufreq present in defaults file"
            printf "  ${C_GREEN}✓${C_RESET} cpufreq workaround present\n"
        else
            emit "  WARNING: --no-collector.cpufreq NOT found in $CONF_DIR/node_exporter.defaults"
            emit "  node_exporter may panic on first scrape if any CPU is offline"
            printf "  ${C_RED}✗${C_RESET} cpufreq workaround MISSING\n"
        fi
    elif [[ "$DEPLOY_TYPE" == "toolkit" ]]; then
        local ne_defaults="/etc/default/node_exporter"
        [[ -f /etc/sysconfig/node_exporter ]] && ne_defaults="/etc/sysconfig/node_exporter"
        if [[ -f "$ne_defaults" ]] && grep -q '\-\-no-collector.cpufreq' "$ne_defaults" 2>/dev/null; then
            emit "  OK: --no-collector.cpufreq present"
            printf "  ${C_GREEN}✓${C_RESET} cpufreq workaround present\n"
        else
            emit "  INFO: cpufreq workaround not present (may not be needed on toolkit)"
        fi
    fi
    emit ""

    # Check 2: certbot :Z volume mount issue
    if [[ "$DEPLOY_TYPE" == "container" && -f "$BASE_DIR/docker-compose.yml" ]]; then
        emit "--- Check: certbot :Z volume mount (SELinux MCS lockout) ---"
        if grep -E '/etc/letsencrypt.*:Z|/var/www/html.*:Z' "$BASE_DIR/docker-compose.yml" 2>/dev/null | grep -q certbot; then
            emit "  WARNING: docker-compose.yml still has :Z mounts for certbot shared directories"
            emit "  This causes SELinux MCS label lockout after certbot recreation"
            emit "  Fix: run update-perfsonar-deployment.sh --apply --restart --yes"
            printf "  ${C_RED}✗${C_RESET} certbot :Z mount detected\n"
        else
            emit "  OK: No dangerous :Z mounts on shared certbot directories"
            printf "  ${C_GREEN}✓${C_RESET} certbot volume labels OK\n"
        fi
        emit ""
    fi

    # Check 3: D-Bus SELinux boolean
    if command -v getsebool &>/dev/null; then
        emit "--- Check: container_use_dbusd SELinux boolean ---"
        local dbus_bool
        dbus_bool=$(getsebool container_use_dbusd 2>/dev/null | awk '{print $NF}' || echo "unknown")
        if [[ "$dbus_bool" == "on" ]]; then
            emit "  OK: container_use_dbusd = on"
            printf "  ${C_GREEN}✓${C_RESET} container_use_dbusd enabled\n"
        elif [[ "$dbus_bool" == "off" ]]; then
            emit "  WARNING: container_use_dbusd = off"
            emit "  node_exporter --collector.systemd may fail inside the container"
            emit "  Fix: setsebool -P container_use_dbusd 1"
            printf "  ${C_YELLOW}✗${C_RESET} container_use_dbusd is off\n"
        else
            emit "  INFO: container_use_dbusd boolean not available"
        fi
        emit ""
    fi

    # Check 4: Container stuck in 'Initialized' state
    if [[ "$DEPLOY_TYPE" == "container" && -n "$RUNTIME" ]]; then
        emit "--- Check: container startup state ---"
        local status
        status=$($RUNTIME ps -a --filter name=perfsonar-testpoint --format '{{.Status}}' 2>/dev/null || echo "")
        if echo "$status" | grep -qi "Initialized"; then
            emit "  WARNING: Container is stuck in 'Initialized (starting)' state"
            emit "  systemd inside the container failed to complete startup"
            emit "  Common cause: cgroup permission denied, stale pod, or missing capabilities"
            emit "  Try: systemctl stop perfsonar-testpoint.service"
            emit "       podman pod rm -f \$(podman pod list -q) 2>/dev/null"
            emit "       systemctl start perfsonar-testpoint.service"
            printf "  ${C_RED}✗${C_RESET} Container stuck in Initialized state\n"
        elif echo "$status" | grep -qi "Up"; then
            emit "  OK: Container is running"
            printf "  ${C_GREEN}✓${C_RESET} Container is running\n"
        elif echo "$status" | grep -qi "Exited"; then
            emit "  WARNING: Container has exited"
            emit "  Check logs: $RUNTIME logs perfsonar-testpoint"
            printf "  ${C_RED}✗${C_RESET} Container has exited\n"
        else
            emit "  INFO: Container status: ${status:-not found}"
        fi
        emit ""
    fi

    # Check 5: cgroup configuration
    if [[ "$DEPLOY_TYPE" == "container" ]]; then
        emit "--- Check: cgroup version and configuration ---"
        local cgroup_ver="v1"
        if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
            cgroup_ver="v2 (unified)"
        fi
        emit "  Host cgroup version: $cgroup_ver"
        if [[ -f "$BASE_DIR/docker-compose.yml" ]]; then
            if grep -q 'cgroup: host' "$BASE_DIR/docker-compose.yml" 2>/dev/null; then
                emit "  OK: compose has 'cgroup: host'"
            else
                emit "  INFO: compose does not set 'cgroup: host' — may use cgroupns private"
            fi
        fi
        printf "  ${C_GREEN}✓${C_RESET} cgroup: $cgroup_ver\n"
        emit ""
    fi
}

# --- 12. Summary / quick health check -------------------------------------
collect_summary() {
    section "Quick Health Summary"

    local issues=0

    # Container running?
    if [[ "$DEPLOY_TYPE" == "container" && -n "$RUNTIME" ]]; then
        local status
        status=$($RUNTIME ps -a --filter name=perfsonar-testpoint --format '{{.Status}}' 2>/dev/null || echo "")
        if echo "$status" | grep -qi "up"; then
            emit "  [PASS] Container: running"
        else
            emit "  [FAIL] Container: ${status:-not found}"
            issues=$((issues + 1))
        fi

        # Container health
        local health
        health=$($RUNTIME inspect perfsonar-testpoint \
            --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        if [[ "$health" == "healthy" ]]; then
            emit "  [PASS] Health check: healthy"
        else
            emit "  [WARN] Health check: $health"
            [[ "$health" == "unhealthy" ]] && issues=$((issues + 1))
        fi
    fi

    # Endpoints
    local fqdn
    fqdn=$(hostname -f 2>/dev/null || hostname)
    for ep in "/" "/pscheduler/" "/node_exporter/metrics" "/perfsonar_host_exporter/"; do
        local code
        code=$(curl -kSs -o /dev/null -w '%{http_code}' --max-time 5 "https://localhost${ep}" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
            emit "  [PASS] https://localhost${ep} → HTTP $code"
        elif [[ "$code" == "000" ]]; then
            emit "  [FAIL] https://localhost${ep} → connection refused"
            issues=$((issues + 1))
        else
            emit "  [WARN] https://localhost${ep} → HTTP $code"
            [[ "$code" =~ ^5 ]] && issues=$((issues + 1))
        fi
    done

    emit ""
    if [[ $issues -eq 0 ]]; then
        emit "  Overall: All checks passed"
    else
        emit "  Overall: $issues issue(s) detected — review report sections above"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"
    setup_colors
    preflight

    info "Collecting diagnostics (this may take 1-2 minutes)..."
    echo

    collect_host_environment
    collect_network
    collect_selinux
    collect_container
    collect_config_files
    collect_toolkit
    collect_endpoints
    collect_tls
    collect_systemd
    collect_tuning
    collect_known_issues
    collect_summary

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "Diagnostic report saved to: $OUTPUT_FILE"
    info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo
    info "To share this report, send the file to your support contact:"
    echo "  cat $OUTPUT_FILE"
    echo "  scp $OUTPUT_FILE user@support-host:/tmp/"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
