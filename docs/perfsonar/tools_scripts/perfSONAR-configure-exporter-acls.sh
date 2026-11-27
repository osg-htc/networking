#!/usr/bin/env bash
set -euo pipefail
# perfSONAR-configure-exporter-acls.sh
# ------------------------------------
# Restrict the Prometheus exporter endpoints that Apache exposes on a perfSONAR
# host (/node_exporter, /perfsonar_host_exporter) to an allowlist of IPs/CIDRs.
# Loopback is always allowed so local checks keep working.
#
# Two kinds of host:
#   toolkit    RPM perfSONAR toolkit: writes an httpd conf.d snippet and
#              reloads httpd.
#   container  OSG testpoint container (perfsonar-testpoint): writes the site
#              list to /opt/perfsonar-tp/conf/exporter-allow.conf, which
#              install-systemd-units.sh (1.8.0+) mounts over the image's
#              /etc/apache2/osg/exporter-allow.conf, and reloads Apache in the
#              container. Needs an OSG image with osg-exporter-acl.conf.
#
# Version: 0.2.0 - 2026-11-27
# Author: OSG perfSONAR deployment tools
#
# Version history:
#   0.2.0 - 2026-11-27: Container mode (auto-detected). Default allowlist when
#           --allowlist is omitted, the same list the OSG testpoint image ships
#           (AGLT2 IPv6 fixed from /50 to /48, which left out MSU). Toolkit
#           mode now restricts all of /node_exporter, not only /metrics.
#   0.1.1 - 2026-10-09: Add header with '# Version:' line (update-perfsonar-
#           deployment.sh reported this script as "v?").
#   0.1.0 - 2026-03-02: Initial version.
VERSION="0.2.0"
LOG_FILE="/var/log/perfSONAR-configure-exporter-acls.log"
ACL_FILE="/etc/httpd/conf.d/apache-osg-exporter-restrictions.conf"
CONTAINER_NAME="${PERFSONAR_CONTAINER:-perfsonar-testpoint}"
CONTAINER_ALLOW_FILE="${EXPORTER_ALLOW_FILE:-/opt/perfsonar-tp/conf/exporter-allow.conf}"
CONTAINER_ALLOW_TARGET="/etc/apache2/osg/exporter-allow.conf"
CONTAINER_ACL_CONF="/etc/apache2/conf-enabled/osg-exporter-acl.conf"

# OSG default: AGLT2 (OSG/WLCG central perfSONAR monitoring, psetf) and CERN.
# Keep in step with osg/exporter-allow.conf in osg-htc/perfsonar-testpoint-docker.
DEFAULT_ALLOWLIST="2001:48a8:68f7::/48,192.41.230.0/23,192.41.236.0/23,2001:1458:d00::/48,2001:1458:d03::/48,2001:1458:301::/48,2001:1458:302::/48,2001:1458:303::/48,188.184.0.0/17,188.185.0.0/17,188.185.128.0/18,128.142.0.0/16"

ALLOWLIST=""
MODE="auto"
DRY_RUN=false
AUTO_YES=false
RUNTIME=""

log() {
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  echo "$ts $*" | tee -a "$LOG_FILE"
}

usage() {
  cat <<'EOF'
Usage: perfSONAR-configure-exporter-acls.sh [--allowlist "CIDR1,CIDR2,..."] [--mode auto|toolkit|container] [--yes] [--dry-run]

Restrict exporter endpoints exposed by Apache:
  - /node_exporter (node_exporter metrics)
  - /perfsonar_host_exporter (perfSONAR host exporter)
Loopback (127.0.0.1, ::1) is always allowed.

Options:
  --allowlist CSV   Comma-separated CIDRs/IPs allowed to access the exporters.
                    Default: the OSG list (AGLT2 and CERN monitoring networks).
  --mode MODE       auto (default): container if a perfsonar-testpoint
                    container exists, otherwise toolkit.
  --yes             Skip confirmation prompt
  --dry-run         Print actions without writing files
  --help, -h        Show help
EOF
}

confirm() {
  if [ "$AUTO_YES" = true ]; then
    return 0
  fi
  read -r -p "Apply exporter ACL restrictions now? [y/N]: " ans
  case "${ans:-}" in
    y|Y|yes|YES) return 0 ;;
    *) log "Cancelled by user."; return 1 ;;
  esac
}

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
  fi
}

run() {
  log "CMD: $*"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

is_valid_ip_or_cidr() {
  python3 - "$1" <<'PY'
import ipaddress
import sys
value = sys.argv[1]
try:
    if '/' in value:
        ipaddress.ip_network(value, strict=False)
    else:
        ipaddress.ip_address(value)
except Exception:
    sys.exit(1)
sys.exit(0)
PY
}

parse_cli() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allowlist) ALLOWLIST="${2:-}"; shift 2 ;;
      --mode) MODE="${2:-}"; shift 2 ;;
      --yes) AUTO_YES=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  case "$MODE" in
    auto|toolkit|container) ;;
    *) echo "Invalid --mode: $MODE (auto, toolkit or container)" >&2; exit 2 ;;
  esac
}

detect_runtime() {
  local r
  for r in podman docker; do
    if command -v "$r" >/dev/null 2>&1 && "$r" container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
      RUNTIME="$r"
      return 0
    fi
  done
  return 1
}

resolve_mode() {
  if [ "$MODE" = auto ]; then
    if detect_runtime; then MODE=container; else MODE=toolkit; fi
  elif [ "$MODE" = container ]; then
    detect_runtime || { echo "No $CONTAINER_NAME container found (podman or docker)." >&2; exit 4; }
  fi
}

# Print one "Require ip X" line per allowlist entry, with the given indent.
render_allow_lines() {
  local csv="$1" indent="$2" item
  IFS=',' read -r -a entries <<< "$csv"
  for item in "${entries[@]}"; do
    item="${item// /}"
    [ -z "$item" ] && continue
    if ! is_valid_ip_or_cidr "$item"; then
      echo "Invalid IP/CIDR in --allowlist: $item" >&2
      exit 3
    fi
    printf '%sRequire ip %s\n' "$indent" "$item"
  done
}

# Write content to a file in place (keeps the inode, so single-file bind
# mounts keep working), with a timestamped backup of the old content.
install_content() {
  local src="$1" dst="$2"
  run mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    run cp -a "$dst" "${dst}.bak.$(date +%s)"
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] write $dst:"; cat "$src"
  else
    log "Writing $dst"
    cat "$src" > "$dst"
    chmod 0644 "$dst"
  fi
}

# --- toolkit (RPM, httpd) ---------------------------------------------------

apply_toolkit() {
  local tmp_file require_lines
  tmp_file="$(mktemp)"
  require_lines="$(printf '    Require local\n'; render_allow_lines "$ALLOWLIST" '    ')"

  cat > "$tmp_file" <<EOF
# Managed by perfSONAR-configure-exporter-acls.sh v${VERSION}
# Restricts exporter endpoints to explicit allow-list entries.

<Location /node_exporter>
<RequireAny>
${require_lines}
</RequireAny>
</Location>

<Location /perfsonar_host_exporter>
<RequireAny>
${require_lines}
</RequireAny>
</Location>
EOF
  install_content "$tmp_file" "$ACL_FILE"
  rm -f "$tmp_file"

  if command -v apachectl >/dev/null 2>&1; then
    run apachectl configtest
  elif command -v httpd >/dev/null 2>&1; then
    run httpd -t
  else
    log "Apache config test command not found; skipping syntax validation."
  fi
  if command -v systemctl >/dev/null 2>&1; then
    run systemctl reload httpd || run systemctl reload apache2 || true
  fi
  log "ACL file: $ACL_FILE"
}

# --- container (OSG testpoint image) ----------------------------------------

apply_container() {
  local tmp_file mounted=false
  if ! "$RUNTIME" exec "$CONTAINER_NAME" test -f "$CONTAINER_ACL_CONF"; then
    log "ERROR: the running image has no $CONTAINER_ACL_CONF."
    log "       Update to an OSG testpoint image with exporter ACL support, then rerun."
    exit 5
  fi

  tmp_file="$(mktemp)"
  {
    echo "# Managed by perfSONAR-configure-exporter-acls.sh v${VERSION}"
    echo "# Site allow-list for the exporter endpoints; loopback is always allowed by the image."
    echo "# Mounted over ${CONTAINER_ALLOW_TARGET} by the perfsonar-testpoint unit."
    render_allow_lines "$ALLOWLIST" ''
  } > "$tmp_file"
  install_content "$tmp_file" "$CONTAINER_ALLOW_FILE"

  if "$RUNTIME" container inspect "$CONTAINER_NAME" \
       --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' | grep -qx "$CONTAINER_ALLOW_TARGET"; then
    mounted=true
  fi

  if [ "$mounted" = false ]; then
    # Takes effect now; lost when the container is recreated until the unit mounts the file.
    run "$RUNTIME" cp "$tmp_file" "${CONTAINER_NAME}:${CONTAINER_ALLOW_TARGET}"
    log "NOTE: $CONTAINER_ALLOW_FILE is not mounted into the container yet."
    log "      Rerun install-systemd-units.sh (1.8.0+) so the unit mounts it; until then the list"
    log "      was copied into the running container and is lost when the container is recreated."
  fi
  rm -f "$tmp_file"

  run "$RUNTIME" exec "$CONTAINER_NAME" apache2ctl -t
  run "$RUNTIME" exec "$CONTAINER_NAME" apache2ctl graceful
  log "Site list: $CONTAINER_ALLOW_FILE (mounted: $mounted)"
}

main() {
  need_root
  parse_cli "$@"

  if [ -z "$ALLOWLIST" ]; then
    ALLOWLIST="$DEFAULT_ALLOWLIST"
    log "No --allowlist given; using the OSG default list."
  fi
  resolve_mode

  log "Starting exporter ACL configuration (v${VERSION}, mode: ${MODE})"
  log "Allow-list: $ALLOWLIST"

  confirm || exit 0
  case "$MODE" in
    toolkit) apply_toolkit ;;
    container) apply_container ;;
  esac
  log "Exporter ACL configuration complete."
}

main "$@"
