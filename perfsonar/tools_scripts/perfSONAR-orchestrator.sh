#!/usr/bin/env bash
set -euo pipefail
# Version: 1.0.1
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

# perfSONAR-orchestrator.sh
# Guided installer with interactive pauses for deploying a containerized perfSONAR Testpoint
# on RHEL 9 minimal systems. Defaults to non-disruptive PBR in-place mode.
#
# Usage:
#   Run as root on the target host. The script will prompt before each step.
#   Options can preselect compose mode and Let’s Encrypt details.
#
# Flags:
#   --option {A|B}         Select deployment option
#                          A = Testpoint only (default)
#                          B = Testpoint + Let's Encrypt (auto patching)
#   --fqdn NAME            Primary FQDN for certificates (Option B)
#   --email ADDRESS        Email for Let’s Encrypt (Option B)
#   --non-interactive      Run without pauses (assumes defaults and --yes for internal scripts)
#   --yes                  Auto-confirm internal script prompts
#  --auto-update           Install and enable auto-update timer for compose-managed containers
#   --dry-run              Print steps but do not execute destructive operations
#
# Log:
#   /var/log/perfsonar-orchestrator.log

LOG_FILE="/var/log/perfsonar-orchestrator.log"
DRY_RUN=false
AUTO_YES=false
NON_INTERACTIVE=false
# shellcheck disable=SC2034
AUTO_UPDATE=false
DEPLOY_OPTION="A"         # A or B
LE_FQDN=""
LE_EMAIL=""

# Recommended package set for minimal RHEL 9
RECOMMENDED_PACKAGES=(
  podman podman-docker podman-compose
  jq curl tar gzip rsync bind-utils
  nftables fail2ban policycoreutils-python-utils
  python3 iproute iputils procps-ng sed grep gawk
)

log() {
  local ts; ts="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "$ts $*" | tee -a "$LOG_FILE" # Ensure consistent use of LOG_FILE
}

confirm() {
  local msg="$1"; shift || true
  if [ "$NON_INTERACTIVE" = true ]; then
    return 0
  fi
  echo
  read -r -p "$msg [Enter=continue / s=skip / q=quit]: " ans
  case "${ans:-}" in
    q|Q) log "User requested quit."; exit 0;;
    s|S) return 1;;
    *) return 0;;
  esac
}

run() {
  log "CMD: $*"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (or with sudo)." >&2
    exit 1
  fi
}

parse_cli() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift;;
      --yes) AUTO_YES=true; shift;;
      --non-interactive) NON_INTERACTIVE=true; AUTO_YES=true; shift;;
      --option) DEPLOY_OPTION="${2:-A}"; shift 2;;
      --fqdn) LE_FQDN="${2:-}"; shift 2;;
      --email) LE_EMAIL="${2:-}"; shift 2;;
      --help|-h)
        sed -n '1,80p' "$0" | sed -n '1,80p'
        exit 0;;
      --auto-update) AUTO_UPDATE=true; shift;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
}

preflight() {
  log "=== perfSONAR Orchestrator started on $(hostname -f) ==="
  log "Kernel: $(uname -r)"; log "Date: $(date -u)"
  log "Selected option: $DEPLOY_OPTION (A=testpoint only, B=testpoint+LE)"
  if [ -n "$LE_FQDN" ]; then log "LE FQDN: $LE_FQDN"; fi
  if [ -n "$LE_EMAIL" ]; then log "LE Email: $LE_EMAIL"; fi
}

step_packages() {
  if ! confirm "Step 1: Install recommended base packages?"; then
    log "Skipping packages."
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    run dnf -y install "${RECOMMENDED_PACKAGES[@]}"
  else
    log "dnf not found; please install packages manually."
  fi
}

step_disable_conflicts() {
  if ! confirm "Step 2: Disable firewalld and NetworkManager-wait-online (safe to skip if already disabled in Step 1)?"; then
    log "Skipping disable services."
    return
  fi
  run systemctl disable --now firewalld NetworkManager-wait-online || true
}

step_bootstrap_tools() {
  if ! confirm "Step 3: Bootstrap helper scripts to /opt/perfsonar-tp?"; then
    log "Skipping bootstrap."
    return
  fi
  run mkdir -p /opt/perfsonar-tp
  run bash -c "curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh | bash -s -- /opt/perfsonar-tp"
  run ls -l /opt/perfsonar-tp/tools_scripts
}

step_generate_config() {
  if ! confirm "Step 4: Generate multi-NIC config (auto-detect) and review?"; then
    log "Skipping generate config."
    return
  fi
  local gen_cmd=(/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto)
  [ "$AUTO_YES" = true ] && gen_cmd+=(--yes)
  run "${gen_cmd[@]}"
  echo "Edit /etc/perfSONAR-multi-nic-config.conf if needed (gateways, DEFAULT_ROUTE_NIC)."
  echo "Note: The auto-generator will skip NICs that have neither an IPv4 nor an IPv6 gateway (management-only NICs) unless they are set as DEFAULT_ROUTE_NIC."
  if [ "$NON_INTERACTIVE" != true ]; then
    ${EDITOR:-vi} /etc/perfSONAR-multi-nic-config.conf || true
  fi
}

step_apply_pbr() {
  if ! confirm "Step 5: Apply PBR (in-place mode, low disruption)?"; then
    log "Skipping PBR apply."
    return
  fi
  local pbr_cmd=(/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes)
  [ "$AUTO_YES" = true ] && pbr_cmd=(/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes)
  run "${pbr_cmd[@]}"
  run nmcli connection show
  run ip rule show
  run bash -c 'grep -E "_[sS]ource_route" /etc/iproute2/rt_tables 2>/dev/null | awk "{print \$1}" | while read -r t; do echo "=== TABLE $t ==="; ip route show table "$t"; done'
}

step_dns_check() {
  if ! confirm "Step 6: Run DNS forward/reverse checks?"; then
    log "Skipping DNS check."
    return
  fi
  if [ -x /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh ]; then
    run /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh || true
  else
    log "DNS checker not present; skipping."
  fi
}

step_security() {
  if ! confirm "Step 7: Apply nftables/SELinux/Fail2Ban (if installed)?"; then
    log "Skipping security step."
    return
  fi
  local sec_cmd=(/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes)
  run "${sec_cmd[@]}" || true
  # Optional: setup auto-update timer for compose-managed containers (Step 7.4)
  if command -v podman-compose >/dev/null 2>&1; then
    if confirm "Step 7.4: Install auto-update timer for compose-managed containers (daily pull + restart if updated)?"; then
      step_auto_update_compose
    else
      log "Skipping auto-update setup."
    fi
  else
    log "podman-compose not present; skipping auto-update setup."
  fi
}

# shellcheck disable=SC2120
step_auto_update_compose() {
  # Create update script, systemd service and timer to run daily
  if ! confirm "Create /usr/local/bin/perfsonar-auto-update.sh and enable systemd timer?"; then
    log "User skipped creating auto-update artifacts."
    return
  fi

    # shellcheck disable=SC2153
  run bash -c "cat > /usr/local/bin/perfsonar-auto-update.sh <<'EOF'
#!/bin/bash
set -e
COMPOSE_DIR=/opt/perfsonar-tp
LOGFILE=/var/log/perfsonar-auto-update.log
log() { echo \"\$(date -Iseconds) \$*\" | tee -a \"\$LOGFILE\"; }
cd \"\$COMPOSE_DIR\"
log \"Checking for image updates...\"
# Pull latest images and detect if any were actually updated
if podman-compose pull 2>&1 | tee -a \"\$LOGFILE\" | grep -q -E 'Downloaded newer image|Pulling from'; then
  log \"New images found - recreating containers...\"
  podman-compose up -d 2>&1 | tee -a \"\$LOGFILE\"
  log \"Containers updated successfully\"
else
  log \"No updates available\"
fi
EOF"

  run chmod 0755 /usr/local/bin/perfsonar-auto-update.sh

  run bash -c "cat > /etc/systemd/system/perfsonar-auto-update.service <<'EOF'
[Unit]
Description=perfSONAR Container Auto-Update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/perfsonar-auto-update.sh

[Install]
WantedBy=multi-user.target
EOF"

  run bash -c "cat > /etc/systemd/system/perfsonar-auto-update.timer <<'EOF'
[Unit]
Description=perfSONAR Container Auto-Update Timer

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF"

  run systemctl daemon-reload
  run systemctl enable --now perfsonar-auto-update.timer
  log "Installed and enabled perfsonar-auto-update.timer"
}

step_deploy_option_a() {
  run mkdir -p /opt/perfsonar-tp/psconfig
  run bash -c "curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint.yml -o /opt/perfsonar-tp/docker-compose.yml"
  run bash -c "cd /opt/perfsonar-tp && podman-compose up -d"
  run podman ps
}

step_deploy_option_b() {
  run /opt/perfsonar-tp/tools_scripts/seed_testpoint_host_dirs.sh
  run bash -c "curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint-le-auto.yml -o /opt/perfsonar-tp/docker-compose.yml"
  run bash -c "cd /opt/perfsonar-tp && podman-compose up -d"
  run podman ps
  
  # Auto-detect FQDNs from reverse DNS of all configured IPs
  local fqdns=()
  log "Auto-detecting FQDNs from reverse DNS of configured IPs..."
  if [ -f /etc/perfSONAR-multi-nic-config.conf ]; then
    # Source the config to get IP arrays
    # shellcheck disable=SC1091
    source /etc/perfSONAR-multi-nic-config.conf || true
    for ip in "${NIC_IPV4_ADDRS[@]}" "${NIC_IPV6_ADDRS[@]}"; do
      [ "$ip" = "-" ] && continue
      
      # Skip private/non-routable IPs:
      # RFC1918: 10.x, 172.16-31.x, 192.168.x
      # IPv6: fc00::/7 (ULA), fe80::/10 (link-local), ::1 (loopback)
      # Other: 127.x (IPv4 loopback), 169.254.x (link-local)
      if [[ "$ip" =~ ^10\. ]] || \
         [[ "$ip" =~ ^192\.168\. ]] || \
         [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
         [[ "$ip" =~ ^127\. ]] || \
         [[ "$ip" =~ ^169\.254\. ]] || \
         [[ "$ip" =~ ^(fc|fd)[0-9a-f]{2}: ]] || \
         [[ "$ip" =~ ^fe[89ab][0-9a-f]: ]] || \
         [[ "$ip" =~ ^::1$ ]]; then
        log "  $ip -> (skipped: private/non-routable IP)"
        continue
      fi
      
      local fqdn
      fqdn=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' || true)
      if [ -n "$fqdn" ]; then
        log "  $ip -> $fqdn"
        fqdns+=("$fqdn")
      else
        log "  $ip -> (no PTR record)"
      fi
    done
  fi
  
  # Add user-provided FQDN if specified (in addition to auto-detected)
  if [ -n "$LE_FQDN" ]; then
    log "Adding user-provided FQDN: $LE_FQDN"
    fqdns+=("$LE_FQDN")
  fi
  
  # Deduplicate FQDNs and filter out invalid entries
  if [ ${#fqdns[@]} -gt 0 ]; then
    mapfile -t fqdns < <(printf '%s\n' "${fqdns[@]}" | grep -v '^$' | sort -u)
    log "Final FQDNs for certificate (${#fqdns[@]} total): ${fqdns[*]}"
  fi
  
  if [ ${#fqdns[@]} -gt 0 ] && [ -n "$LE_EMAIL" ]; then
    log "Attempting one-time certificate issuance with certbot (standalone on port 80)"
    log "NOTE: Ensure port 80 is open inbound for Let's Encrypt validation"
    log "Checking if port 80 is available..."
    
    # Check if port 80 is already in use
    if ss -tnlp | grep -q ':80 '; then
      log "WARNING: Port 80 appears to be in use. Certbot standalone mode requires exclusive access."
      ss -tnlp | grep ':80 ' | tee -a "$LOG_FILE" || true
    fi
    
    run podman stop certbot || true
    
    # Build certbot command with all FQDNs as SANs
    local certbot_cmd=(
      podman run --rm --net=host
      -v /etc/letsencrypt:/etc/letsencrypt:Z
      -v /var/www/html:/var/www/html:Z
      docker.io/certbot/certbot:latest certonly
      --standalone --agree-tos --non-interactive
      -m "$LE_EMAIL"
    )
    for fqdn in "${fqdns[@]}"; do
      certbot_cmd+=(-d "$fqdn")
    done
    
    if ! run "${certbot_cmd[@]}"; then
      log "ERROR: Certificate issuance failed. Common issues:"
      log "  1. Port 80 blocked by firewall/nftables (check nft list ruleset)"
      log "  2. Network ACLs blocking inbound HTTP from Let's Encrypt CAs"
      log "  3. DNS not properly configured (verify: dig +short <fqdn>)"
      log "You can retry manually or skip and configure certificates later."
      return 1
    fi
    
    run podman restart perfsonar-testpoint || true
    run podman start certbot || true
    run podman exec certbot certbot renew --dry-run || true
  else
    log "Skipping certificate issuance (missing --fqdn/--email or no FQDNs detected). You can do this later."
  fi
}

step_deploy() {
  if ! confirm "Step 8: Deploy containers (Option $DEPLOY_OPTION)?"; then
    log "Skipping deploy."
    return
  fi
  case "$DEPLOY_OPTION" in
    A|a) step_deploy_option_a ;;
    B|b) step_deploy_option_b ;;
    *) log "Unknown option $DEPLOY_OPTION; defaulting to A"; step_deploy_option_a ;;
  esac
}

step_psconfig() {
  if ! confirm "Step 9: Enroll pSConfig feeds automatically?"; then
    log "Skipping pSConfig."
    return
  fi
  if [ -x /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh ]; then
    run /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -y -v || true
    run podman exec perfsonar-testpoint psconfig remote list || true
  else
    log "Auto-enroll script not present; skipping."
  fi
}

step_validate() {
  if ! confirm "Step 10: Run quick validation checks?"; then
    log "Skipping validation."
    return
  fi
  run podman ps
  run ss -tnlp | grep -E ':443|:80' || true
  run ip rule show
  run bash -c 'grep -E "_[sS]ource_route" /etc/iproute2/rt_tables 2>/dev/null | awk "{print \$1}" | while read -r t; do echo "=== TABLE $t ==="; ip route show table "$t"; done'
  if [ -n "$LE_FQDN" ]; then
    run bash -c "openssl s_client -connect $LE_FQDN:443 -servername $LE_FQDN -showcerts </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates" || true
  fi

  # Recommend installing the systemd service for reboot persistence
  log "Tip: Enable auto-restart on reboot by installing the systemd service:"
  log "  /opt/perfsonar-tp/tools_scripts/install-systemd-service.sh /opt/perfsonar-tp"
  log "  systemctl enable --now perfsonar-testpoint.service"
}

main() {
  need_root
  parse_cli "$@"
  preflight
  if [ "$AUTO_UPDATE" = true ]; then
    log "AUTO_UPDATE flag detected: enabling auto-update setup."
    AUTO_YES=true
    step_auto_update_compose
  fi
  step_packages
  step_disable_conflicts
  step_bootstrap_tools
  step_generate_config
  step_apply_pbr
  step_dns_check
  step_security
  step_deploy
  step_psconfig
  step_validate
  log "=== Orchestrator complete ==="
}

main "$@"
