#!/usr/bin/env bash
set -euo pipefail
# Version: 1.0.1
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

# perfSONAR-toolkit-install.sh
# Guided installer for the perfSONAR Toolkit RPM bundle on EL9 (RHEL, Alma, Rocky).
# Counterpart to perfSONAR-orchestrator.sh which installs the container-based testpoint.
#
# Steps performed:
#   1. Enable CRB + EPEL; configure perfSONAR software repo
#   2. Install the chosen perfSONAR RPM bundle (default: perfsonar-toolkit)
#   3. Bootstrap OSG helper scripts to /opt/perfsonar-tp
#   4. Generate multi-NIC routing config and apply PBR (policy-based routing)
#   5. Run DNS forward/reverse checks
#   6. Apply nftables / SELinux / Fail2Ban security rules
#   7. (Optional) Obtain and configure a Let's Encrypt TLS certificate
#   8. Install and configure flowd-go (SciTags flow marking)
#   9. Enroll pSConfig feeds automatically
#  10. Validate installed services
#
# Usage:
#   Run as root on the target host. The script will prompt before each step.
#
# Flags:
#   --bundle NAME          RPM bundle to install: toolkit (default), testpoint, core, tools
#   --fqdn NAME            FQDN for Let's Encrypt certificate (optional)
#   --email ADDRESS        Email for Let's Encrypt registration (required with --fqdn)
#   --non-interactive      Run without pauses (no prompts)
#   --yes                  Auto-confirm internal script prompts
#   --dry-run              Print steps but do not execute destructive operations
#   --no-flowd-go          Skip flowd-go (SciTags) installation (installed by default)
#   --experiment-id N      SciTags experiment ID for flowd-go (1-14; interactive prompt if omitted)
#   --no-firefly-receiver  Disable fireflyp plugin in flowd-go config (use with flowd-go 2.4.x RPM)
#                          Requires flowd-go >= 2.5.0; omit with current 2.4.2 RPM to avoid errors
#
# Log:
#   /var/log/perfsonar-toolkit-install.log

LOG_FILE="/var/log/perfsonar-toolkit-install.log"
DRY_RUN=false
AUTO_YES=false
NON_INTERACTIVE=false
INSTALL_FLOWD_GO=true
FLOWD_GO_EXPERIMENT_ID=""
NO_FIREFLY_RECEIVER=false
BUNDLE="toolkit"
LE_FQDN=""
LE_EMAIL=""

# Repo + package constants
PERFSONA_REPO_URL="http://software.internet2.edu/rpms/el9/x86_64/latest/packages/perfsonar-repo-0.11-1.noarch.rpm"
EPEL_REPO_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
HELPER_INSTALL_URL="https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh"
HELPER_DIR="/opt/perfsonar-tp"

log() {
  local ts; ts="$(date +'%Y-%m-%d %H:%M:%S')"
  echo "$ts $*" | tee -a "$LOG_FILE"
}

confirm() {
  local msg="$1"; shift || true
  if [ "$NON_INTERACTIVE" = true ]; then return 0; fi
  echo
  read -r -p "$msg [Enter=continue / s=skip / q=quit]: " ans
  case "${ans:-}" in
    q|Q) log "User quit."; exit 0;;
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
      --dry-run)        DRY_RUN=true; shift;;
      --yes)            AUTO_YES=true; shift;;
      --non-interactive) NON_INTERACTIVE=true; AUTO_YES=true; shift;;
      --bundle)         BUNDLE="${2:-toolkit}"; shift 2;;
      --fqdn)           LE_FQDN="${2:-}"; shift 2;;
      --email)          LE_EMAIL="${2:-}"; shift 2;;
      --no-flowd-go)         INSTALL_FLOWD_GO=false; shift;;
      --experiment-id)       FLOWD_GO_EXPERIMENT_ID="${2:-}"; shift 2;;
      --no-firefly-receiver) NO_FIREFLY_RECEIVER=true; shift;;
      --help|-h)        sed -n '1,80p' "$0"; exit 0;;
      *) echo "Unknown argument: $1" >&2; exit 2;;
    esac
  done
}

preflight() {
  log "=== perfSONAR Toolkit Installer started on $(hostname -f) ==="
  log "Kernel: $(uname -r)  Date: $(date -u)"
  log "Bundle: perfsonar-${BUNDLE}"
  [ -n "$LE_FQDN" ]  && log "LE FQDN:  $LE_FQDN"
  [ -n "$LE_EMAIL" ] && log "LE Email: $LE_EMAIL"
}

# ---------------------------------------------------------------------------
# Step 1 — Repositories
# ---------------------------------------------------------------------------
step_repos() {
  if ! confirm "Step 1: Enable CRB/EPEL and add the perfSONAR RPM repo?"; then
    log "Skipping repo setup."
    return
  fi

  # CodeReady Builder — required for several perfSONAR and EPEL deps.
  # RHEL (Satellite-managed) needs subscription-manager; Alma/Rocky use dnf config-manager.
  if grep -qsi 'Red Hat Enterprise Linux' /etc/os-release; then
    log "RHEL detected — enabling CodeReady Builder via subscription-manager"
    run subscription-manager repos \
      --enable "codeready-builder-for-rhel-9-$(uname -m)-rpms" || \
      log "WARNING: subscription-manager CRB enable failed (may already be enabled)"
  else
    log "Non-RHEL EL9 — enabling CRB via dnf config-manager"
    run dnf config-manager --set-enabled crb 2>/dev/null || \
      log "WARNING: 'crb' repo not found; continuing anyway"
  fi

  # EPEL
  if ! rpm -q epel-release &>/dev/null; then
    log "Installing EPEL release RPM"
    run dnf install -y "$EPEL_REPO_URL"
  else
    log "EPEL already installed"
  fi

  # perfSONAR software repo
  if ! rpm -q perfsonar-repo &>/dev/null; then
    log "Adding perfSONAR software repository"
    run dnf install -y "$PERFSONA_REPO_URL"
  else
    log "perfSONAR repo already configured"
  fi

  run dnf clean all
  run dnf makecache
}

# ---------------------------------------------------------------------------
# Step 2 — Install the RPM bundle
# ---------------------------------------------------------------------------
step_install_bundle() {
  if ! confirm "Step 2: Install perfsonar-${BUNDLE}?"; then
    log "Skipping bundle install."
    return
  fi
  run dnf install -y "perfsonar-${BUNDLE}"
  log "perfsonar-${BUNDLE} installed."
}

# ---------------------------------------------------------------------------
# Step 3 — Bootstrap OSG helper scripts
# ---------------------------------------------------------------------------
step_bootstrap_tools() {
  if ! confirm "Step 3: Bootstrap OSG helper scripts to ${HELPER_DIR}?"; then
    log "Skipping bootstrap."
    return
  fi
  run mkdir -p "$HELPER_DIR"
  run bash -c "curl -fsSL $HELPER_INSTALL_URL | bash -s -- $HELPER_DIR"
  run ls -l "$HELPER_DIR/tools_scripts"
}

# ---------------------------------------------------------------------------
# Step 4 — Multi-NIC routing config + PBR
# ---------------------------------------------------------------------------
step_multnic_pbr() {
  if ! confirm "Step 4: Detect multi-NIC config and apply policy-based routing?"; then
    log "Skipping multi-NIC / PBR."
    return
  fi

  local gen_cmd=("$HELPER_DIR/tools_scripts/perfSONAR-pbr-nm.sh" --generate-config-auto)
  [ "$AUTO_YES" = true ] && gen_cmd+=(--yes)
  run "${gen_cmd[@]}"

  echo "Edit /etc/perfSONAR-multi-nic-config.conf if needed, then press Enter."
  if [ "$NON_INTERACTIVE" != true ]; then
    ${EDITOR:-vi} /etc/perfSONAR-multi-nic-config.conf || true
  fi

  local pbr_cmd=("$HELPER_DIR/tools_scripts/perfSONAR-pbr-nm.sh" --yes)
  run "${pbr_cmd[@]}"
  run ip rule show
}

# ---------------------------------------------------------------------------
# Step 5 — DNS checks
# ---------------------------------------------------------------------------
step_dns_check() {
  if ! confirm "Step 5: Run DNS forward/reverse checks?"; then
    log "Skipping DNS check."
    return
  fi
  if [ -x "$HELPER_DIR/tools_scripts/check-perfsonar-dns.sh" ]; then
    run "$HELPER_DIR/tools_scripts/check-perfsonar-dns.sh" || true
  else
    log "DNS checker not present; skipping."
  fi
}

# ---------------------------------------------------------------------------
# Step 6 — nftables / SELinux / Fail2Ban
# ---------------------------------------------------------------------------
step_security() {
  if ! confirm "Step 6: Apply nftables / SELinux / Fail2Ban rules?"; then
    log "Skipping security step."
    return
  fi
  # Note: perfsonar-toolkit installs perfsonar-toolkit-security which configures
  # basic firewalld rules.  perfSONAR-install-nftables.sh replaces those with an
  # nftables ruleset tuned for multi-NIC and OSG port requirements.
  local sec_cmd=("$HELPER_DIR/tools_scripts/perfSONAR-install-nftables.sh"
                 --selinux --fail2ban --yes)
  # Port 80 is needed if Let's Encrypt is going to obtain a cert later
  if [ -n "$LE_FQDN" ]; then
    log "FQDN provided — adding port 80 to nftables for Let's Encrypt HTTP-01 challenge"
    sec_cmd+=(--perf-ports 80)
  fi
  run "${sec_cmd[@]}" || true
}

# ---------------------------------------------------------------------------
# Step 7 — Let's Encrypt (optional)
# ---------------------------------------------------------------------------
step_letsencrypt() {
  if [ -z "$LE_FQDN" ] || [ -z "$LE_EMAIL" ]; then
    log "Skipping Let's Encrypt (--fqdn / --email not provided; use configure-toolkit-letsencrypt.sh later)."
    return
  fi

  if ! confirm "Step 7: Obtain Let's Encrypt certificate for ${LE_FQDN}?"; then
    log "Skipping Let's Encrypt."
    return
  fi

  # Certbot RPM (certbot + python3-certbot-apache) is available via EPEL
  if ! command -v certbot &>/dev/null; then
    log "Installing certbot and python3-certbot-apache from EPEL"
    run dnf install -y certbot python3-certbot-apache
  fi

  log "Stopping httpd temporarily for standalone cert issuance"
  run systemctl stop httpd || true

  local certbot_cmd=(
    certbot certonly --standalone --agree-tos --non-interactive
    -m "$LE_EMAIL" -d "$LE_FQDN"
  )
  if ! run "${certbot_cmd[@]}"; then
    log "WARNING: certbot failed — check port 80 inbound access and DNS."
    log "You can retry later with:"
    log "  systemctl stop httpd"
    log "  certbot certonly --standalone -m $LE_EMAIL -d $LE_FQDN --agree-tos"
    log "  systemctl start httpd"
    log "  $HELPER_DIR/tools_scripts/configure-toolkit-letsencrypt.sh $LE_FQDN"
    run systemctl start httpd || true
    return
  fi

  log "Patching Apache SSL config to use Let's Encrypt certificate"
  if [ -x "$HELPER_DIR/tools_scripts/configure-toolkit-letsencrypt.sh" ]; then
    run "$HELPER_DIR/tools_scripts/configure-toolkit-letsencrypt.sh" "$LE_FQDN"
  else
    log "WARNING: configure-toolkit-letsencrypt.sh not in helper dir; running from system..."
    curl -fsSL "https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/configure-toolkit-letsencrypt.sh" \
      | run bash -s "$LE_FQDN" || true
  fi

  run systemctl start httpd || true
  run systemctl reload httpd || true

  # Enable automatic renewal via certbot's built-in systemd timer
  run systemctl enable --now certbot-renew.timer || true
  log "certbot renewal timer enabled."
}

# ---------------------------------------------------------------------------
# Step 8 — flowd-go (SciTags)
# ---------------------------------------------------------------------------
step_flowd_go() {
  if [ "$INSTALL_FLOWD_GO" != true ]; then
    log "Skipping flowd-go installation (--no-flowd-go specified)."
    return
  fi
  if ! confirm "Step 8: Install and configure flowd-go (SciTags flow marking)?"; then
    log "Skipping flowd-go."
    return
  fi

  local flowd_cmd=("$HELPER_DIR/tools_scripts/perfSONAR-install-flowd-go.sh")
  [ "$AUTO_YES" = true ]             && flowd_cmd+=(--yes)
  [ -n "$FLOWD_GO_EXPERIMENT_ID" ]   && flowd_cmd+=(--experiment-id "$FLOWD_GO_EXPERIMENT_ID")
  [ "$NO_FIREFLY_RECEIVER" = true ]  && flowd_cmd+=(--no-firefly-receiver)

  if [ -x "$HELPER_DIR/tools_scripts/perfSONAR-install-flowd-go.sh" ]; then
    run "${flowd_cmd[@]}" || true
  else
    log "WARNING: perfSONAR-install-flowd-go.sh not found; run bootstrap (step 3) first."
  fi
}

# ---------------------------------------------------------------------------
# Step 9 — pSConfig enrollment
# ---------------------------------------------------------------------------
step_psconfig() {
  if ! confirm "Step 9: Enroll pSConfig feeds automatically?"; then
    log "Skipping pSConfig enrollment."
    return
  fi

  if [ -x "$HELPER_DIR/tools_scripts/perfSONAR-auto-enroll-psconfig.sh" ]; then
    # --local mode: runs psconfig commands directly on the host (RPM toolkit)
    # instead of via podman exec (container mode)
    local enroll_cmd=("$HELPER_DIR/tools_scripts/perfSONAR-auto-enroll-psconfig.sh"
                      --local -v)
    [ "$AUTO_YES" = true ] && enroll_cmd+=(-y)
    run "${enroll_cmd[@]}" || true

    # Restart the pSConfig agent to pick up new remotes
    run systemctl restart psconfig-pscheduler-agent || true
    run psconfig remote list || true
  else
    log "Auto-enroll script not present; skipping."
  fi
}

# ---------------------------------------------------------------------------
# Step 10 — Validate
# ---------------------------------------------------------------------------
step_validate() {
  if ! confirm "Step 10: Validate installed services?"; then
    log "Skipping validation."
    return
  fi

  log "--- pScheduler services ---"
  for svc in pscheduler-scheduler pscheduler-runner pscheduler-archiver \
             pscheduler-ticker psconfig-pscheduler-agent owamp-server \
             perfsonar-lsregistrationdaemon; do
    if systemctl is-active "$svc" &>/dev/null; then
      log "  ✓ $svc"
    else
      log "  ✗ $svc (not active)"
    fi
  done

  log "--- Listening ports ---"
  ss -tnlp | grep -E ':443|:861|:8760|:4823' || true

  log "--- flowd-go ---"
  if systemctl is-active flowd-go &>/dev/null; then
    log "  ✓ flowd-go"
  else
    log "  ✗ flowd-go"
  fi

  if [ -n "$LE_FQDN" ]; then
    log "--- TLS certificate ---"
    openssl s_client -connect "${LE_FQDN}:443" -servername "$LE_FQDN" \
      -showcerts </dev/null 2>/dev/null \
      | openssl x509 -noout -issuer -subject -dates 2>/dev/null || true
  fi

  log "--- pSConfig remotes ---"
  psconfig remote list 2>/dev/null || true

  log "--- Routing ---"
  run ip rule show
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  need_root
  parse_cli "$@"
  preflight
  step_repos
  step_install_bundle
  step_bootstrap_tools
  step_multnic_pbr
  step_dns_check
  step_security
  step_letsencrypt
  step_flowd_go
  step_psconfig
  step_validate
  log "=== perfSONAR Toolkit installation complete ==="
}

main "$@"
