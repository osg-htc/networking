#!/usr/bin/env bash
# Build a self-contained restore script to re-apply lsregistrationdaemon.conf
# settings after an upgrade or rebuild.
#
# This tool parses an existing lsregistrationdaemon.conf and writes a
# temporary script that invokes perfSONAR-update-lsregistration.sh with the
# equivalent flags to restore configuration either inside the container or on
# the host (local mode).
#
# Defaults:
#   - Source conf: /etc/perfsonar/lsregistrationdaemon.conf
#   - Output: /tmp/perfSONAR-restore-lsregistration-YYYYmmddTHHMMSSZ.sh
#   - Restore target: container 'perfsonar-testpoint' (override with --local
#     to restore directly on host, or --container to choose a different name)
#
set -euo pipefail
IFS=$'\n\t'

CONF_PATH="/etc/perfsonar/lsregistrationdaemon.conf"   # source to read
SCRIPT_PATH="./perfSONAR-update-lsregistration.sh"     # updater to call in generated script
INCLUDE_SUDO=true
ENGINE=""                 # optional engine to include in generated script
CONTAINER_NAME="perfsonar-testpoint"
LOCAL_MODE=false            # if true, generated script uses --local --conf
TARGET_CONF="/etc/perfsonar/lsregistrationdaemon.conf" # where to write in restore
OUT_PATH=""               # output file path; auto if empty

usage() {
  cat <<'EOF'
Usage: perfSONAR-build-lsregistration-invoke.sh [OPTIONS]

Build a restore script that re-applies lsregistration settings using
perfSONAR-update-lsregistration.sh.

Options:
  --conf PATH             Source lsregistrationdaemon.conf to parse
                          (default: /etc/perfsonar/lsregistrationdaemon.conf)
  --script PATH           Path to perfSONAR-update-lsregistration.sh used by
                          the generated script (default: ./perfSONAR-update-lsregistration.sh)
  --local                 Generate script to restore on host (non-container)
  --target-conf PATH      Target conf path for local restore (default: /etc/perfsonar/lsregistrationdaemon.conf)
  --container NAME        Generate script to restore in container NAME (default: perfsonar-testpoint)
  --engine auto|docker|podman  Include engine flag in generated script
  --out PATH              Output script path (default: /tmp/perfSONAR-restore-lsregistration-<timestamp>.sh)
  --no-sudo               Do not prefix restore command with 'sudo'
  -h, --help              Show this help

Notes:
  - Only uncommented keys are considered; last occurrence wins.
  - Administrator block (<administrator>) is parsed for name and email.
  - site_project may appear multiple times; all are included.
EOF
}

err() { echo "Error: $*" >&2; }

# read_kv KEY -> prints value or nothing
read_kv() {
  local key=$1
  # 1) exclude commented lines; 2) keep last occurrence; 3) strip key and leading spaces; 4) drop inline comments
  awk -v k="$key" '
    $0 !~ /^[[:space:]]*#/ && $0 ~ "^[[:space:]]*" k "[[:space:]]" { last=$0 }
    END {
      if (last != "") {
        sub(/^\s*[^\t\r\n ]+\s+/, "", last)
        sub(/\s+#.*/, "", last)
        gsub(/\s+$/, "", last)
        print last
      }
    }
  ' "$CONF_PATH"
}

# read_all_projects -> prints each site_project value on its own line (unique)
read_all_projects() {
  awk '
    $0 !~ /^[[:space:]]*#/ && $0 ~ /^\s*site_project[[:space:]]/ {
      line=$0
      sub(/^\s*site_project[[:space:]]+/, "", line)
      sub(/\s+#.*/, "", line)
      gsub(/\s+$/, "", line)
      if (line != "") { seen[line]++ }
    }
    END { for (p in seen) print p }
  ' "$CONF_PATH" | sort
}

# read_admin -> prints name<TAB>email (or nothing)
read_admin() {
  awk '
    $0 ~ /^[[:space:]]*#/ { next }
    BEGIN{inblk=0; name=""; email=""}
    /^\s*<administrator>/ { inblk=1; next }
    /^\s*<\/administrator>/ { inblk=0; next }
    inblk==1 {
      if ($0 ~ /\bname\b/) {
        line=$0
        sub(/^\s*name\s+/, "", line)
        sub(/\s+#.*/, "", line)
        gsub(/\s+$/, "", line)
        name=line
      } else if ($0 ~ /\bemail\b/) {
        line=$0
        sub(/^\s*email\s+/, "", line)
        sub(/\s+#.*/, "", line)
        gsub(/\s+$/, "", line)
        email=line
      }
    }
    END {
      if (name != "" && email != "") {
        print name "\t" email
      }
    }
  ' "$CONF_PATH"
}

quote_join() {
  # Print a space-joined, shell-escaped version of all args
  local out="" q
  for el in "$@"; do
    printf -v q '%q' "$el"
    out+="$q "
  done
  printf '%s\n' "${out%% }"
}

# Parse CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --conf) CONF_PATH="$2"; shift 2;;
    --script) SCRIPT_PATH="$2"; shift 2;;
    --local) LOCAL_MODE=true; shift;;
    --target-conf) TARGET_CONF="$2"; shift 2;;
    --container) CONTAINER_NAME="$2"; LOCAL_MODE=false; shift 2;;
    --engine) ENGINE="$2"; shift 2;;
    --out) OUT_PATH="$2"; shift 2;;
    --no-sudo) INCLUDE_SUDO=false; shift;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

if [[ ! -f "$CONF_PATH" ]]; then
  err "Conf file not found: $CONF_PATH"; exit 2
fi

# Gather values
SITE_NAME=$(read_kv site_name || true)
DOMAIN=$(read_kv domain || true)
CITY=$(read_kv city || true)
REGION=$(read_kv region || true)
COUNTRY=$(read_kv country || true)
ZIP=$(read_kv zip_code || true)
LATITUDE=$(read_kv latitude || true)
LONGITUDE=$(read_kv longitude || true)
LS_INSTANCE=$(read_kv ls_instance || true)
LS_LEASE_DURATION=$(read_kv ls_lease_duration || true)
CHECK_INTERVAL=$(read_kv check_interval || true)
ALLOW_INTERNAL=$(read_kv allow_internal_addresses || true)
PROJECTS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && PROJECTS+=("$p")
done < <(read_all_projects)

ADMIN_NAME=""; ADMIN_EMAIL=""
if admin_line=$(read_admin); then
  if [[ -n "$admin_line" ]]; then
    ADMIN_NAME=${admin_line%%$'\t'*}
    ADMIN_EMAIL=${admin_line#*$'\t'}
  fi
fi

# Build argument array for the updater
args=()
if [[ "$LOCAL_MODE" == true ]]; then
  args+=(--local --conf "$TARGET_CONF")
else
  args+=(--container "$CONTAINER_NAME")
  if [[ -n "$ENGINE" ]]; then args+=(--engine "$ENGINE"); fi
fi
if [[ -n "$SITE_NAME" ]]; then args+=(--site-name "$SITE_NAME"); fi
if [[ -n "$DOMAIN" ]]; then args+=(--domain "$DOMAIN"); fi
for p in "${PROJECTS[@]:-}"; do args+=(--project "$p"); done
if [[ -n "$CITY" ]]; then args+=(--city "$CITY"); fi
if [[ -n "$REGION" ]]; then args+=(--region "$REGION"); fi
if [[ -n "$COUNTRY" ]]; then args+=(--country "$COUNTRY"); fi
if [[ -n "$ZIP" ]]; then args+=(--zip "$ZIP"); fi
if [[ -n "$LATITUDE" ]]; then args+=(--latitude "$LATITUDE"); fi
if [[ -n "$LONGITUDE" ]]; then args+=(--longitude "$LONGITUDE"); fi
if [[ -n "$LS_INSTANCE" ]]; then args+=(--ls-instance "$LS_INSTANCE"); fi
if [[ -n "$LS_LEASE_DURATION" ]]; then args+=(--ls-lease-duration "$LS_LEASE_DURATION"); fi
if [[ -n "$CHECK_INTERVAL" ]]; then args+=(--check-interval "$CHECK_INTERVAL"); fi
if [[ -n "$ALLOW_INTERNAL" ]]; then args+=(--allow-internal "$ALLOW_INTERNAL"); fi
if [[ -n "$ADMIN_NAME" && -n "$ADMIN_EMAIL" ]]; then
  args+=(--admin-name "$ADMIN_NAME" --admin-email "$ADMIN_EMAIL")
fi

# Determine output path
if [[ -z "$OUT_PATH" ]]; then
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  OUT_PATH="/tmp/perfSONAR-restore-lsregistration-${ts}.sh"
fi

# Compose the command line as a single escaped string for embedding
cmd_line=""
tmp_arr=()
if [[ "$INCLUDE_SUDO" == true ]]; then tmp_arr+=(sudo); fi
tmp_arr+=("$SCRIPT_PATH")
tmp_arr+=("${args[@]}")
cmd_line=$(quote_join "${tmp_arr[@]}")

# Write the restore script
cat >"$OUT_PATH" <<EOF
#!/usr/bin/env bash
# Restore lsregistration configuration
# Source: $(printf '%q' "$CONF_PATH")
# Generated: $(date -u +%F' '%T'Z')
set -euo pipefail
echo "Applying perfSONAR lsregistration settings..."
$cmd_line
echo "Done."
EOF

chmod +x "$OUT_PATH"
echo "Restore script written to: $OUT_PATH"
exit 0
