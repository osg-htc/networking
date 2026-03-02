#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
LOG_FILE="/var/log/perfSONAR-configure-exporter-acls.log"
ACL_FILE="/etc/httpd/conf.d/apache-osg-exporter-restrictions.conf"
ALLOWLIST=""
DRY_RUN=false
AUTO_YES=false

log() {
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  echo "$ts $*" | tee -a "$LOG_FILE"
}

usage() {
  cat <<'EOF'
Usage: perfSONAR-configure-exporter-acls.sh --allowlist "CIDR1,CIDR2,..." [--yes] [--dry-run]

Restrict exporter endpoints exposed by Apache:
  - /node_exporter/metrics
  - /perfsonar_host_exporter/

Options:
  --allowlist CSV   Comma-separated CIDRs/IPs allowed to access exporter endpoints
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
  if [ "$(id -u)" -ne 0 ]; then
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
      --yes) AUTO_YES=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
  done
}

render_require_lines() {
  local csv="$1"
  local item
  IFS=',' read -r -a entries <<< "$csv"

  printf '    Require ip 127.0.0.1\n'
  printf '    Require ip ::1\n'

  for item in "${entries[@]}"; do
    item="${item// /}"
    [ -z "$item" ] && continue
    if ! is_valid_ip_or_cidr "$item"; then
      echo "Invalid IP/CIDR in --allowlist: $item" >&2
      exit 3
    fi
    printf '    Require ip %s\n' "$item"
  done
}

write_acl_file() {
  local tmp_file
  tmp_file="$(mktemp)"
  local require_lines
  require_lines="$(render_require_lines "$ALLOWLIST")"

  cat > "$tmp_file" <<EOF
# Managed by perfSONAR-configure-exporter-acls.sh v${VERSION}
# Restricts exporter endpoints to explicit allow-list entries.

<Location /node_exporter/metrics>
<RequireAny>
${require_lines}
</RequireAny>
</Location>

<Location /perfsonar_host_exporter/>
<RequireAny>
${require_lines}
</RequireAny>
</Location>
EOF

  run mkdir -p "$(dirname "$ACL_FILE")"
  if [ -f "$ACL_FILE" ]; then
    run cp -a "$ACL_FILE" "${ACL_FILE}.bak.$(date +%s)"
  fi
  run cp "$tmp_file" "$ACL_FILE"
  run chmod 0644 "$ACL_FILE"
  rm -f "$tmp_file"
}

verify_httpd_config() {
  if command -v apachectl >/dev/null 2>&1; then
    run apachectl configtest
  elif command -v httpd >/dev/null 2>&1; then
    run httpd -t
  else
    log "Apache config test command not found; skipping syntax validation."
  fi
}

reload_httpd() {
  if command -v systemctl >/dev/null 2>&1; then
    run systemctl reload httpd || run systemctl reload apache2 || true
  fi
}

main() {
  need_root
  parse_cli "$@"

  if [ -z "$ALLOWLIST" ]; then
    echo "--allowlist is required" >&2
    usage
    exit 2
  fi

  log "Starting exporter ACL configuration"
  log "Allow-list: $ALLOWLIST"

  confirm || exit 0
  write_acl_file
  verify_httpd_config
  reload_httpd

  log "Exporter ACL configuration complete."
  log "ACL file: $ACL_FILE"
}

main "$@"
