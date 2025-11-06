#!/usr/bin/env bash
# Update lsregistrationdaemon.conf inside a perfSONAR testpoint container
#
# This script copies /etc/perfsonar/lsregistrationdaemon.conf out of the
# container, applies requested changes, and copies it back. Optionally restarts
# the lsregistration daemon inside the container. Works with either docker or
# podman.
#
# Usage examples:
#   sudo ./perfSONAR-update-lsregistration.sh \
#     --site-name "Acme Co." \
#     --domain example.org \
#     --project WLCG --project OSG \
#     --city Berkeley --region CA --country US --zip 94720 \
#     --latitude 37.5 --longitude -121.7469 \
#     --admin-name "pS Admin" --admin-email admin@example.org \
#     --ls-instance https://ls.example.org/lookup/records \
#     --ls-lease-duration 7200 --check-interval 3600 --allow-internal 0
#
#   # Use a non-default container name and skip restart
#   sudo ./perfSONAR-update-lsregistration.sh --container perfsonar-testpoint --no-restart --dry-run
#
set -euo pipefail
IFS=$'\n\t'

# Defaults
CONTAINER="perfsonar-testpoint"
ENGINE="auto"   # auto|docker|podman
CONF_PATH="/etc/perfsonar/lsregistrationdaemon.conf"
DRY_RUN=false
NO_RESTART=false
LOCAL_MODE=false   # when true, operate on local filesystem instead of container

# Values to set (all optional)
SITE_NAME=""
DOMAIN=""
PROJECTS=()
CITY=""
REGION=""
COUNTRY=""
ZIP=""
LATITUDE=""
LONGITUDE=""
LS_INSTANCE=""
LS_LEASE_DURATION=""
CHECK_INTERVAL=""
ALLOW_INTERNAL=""
ADMIN_NAME=""
ADMIN_EMAIL=""

usage() {
  cat <<'EOF'
Usage: perfSONAR-update-lsregistration.sh [OPTIONS]

Options:
  --container NAME           Container name (default: perfsonar-testpoint)
  --engine [auto|docker|podman]  Container engine selector (default: auto)
  --local                    Edit a local file instead of a container (see --conf)
  --conf PATH                Path to lsregistrationdaemon.conf (default: /etc/perfsonar/lsregistrationdaemon.conf)
  --dry-run                  Show diff but do not copy back or restart
  --no-restart               Do not restart lsregistrationdaemon inside container

  --site-name STR            Set site_name
  --domain STR               Set domain
  --project STR              Add a site_project (may be repeated)
  --city STR                 Set city
  --region STR               Set region (2-letter)
  --country STR              Set country (2-letter ISO)
  --zip STR                  Set zip_code
  --latitude NUM             Set latitude
  --longitude NUM            Set longitude

  --ls-instance URL          Set ls_instance
  --ls-lease-duration SEC    Set ls_lease_duration (seconds)
  --check-interval SEC       Set check_interval (seconds)
  --allow-internal 0|1       Set allow_internal_addresses

  --admin-name STR           Set administrator name (requires --admin-email)
  --admin-email STR          Set administrator email (requires --admin-name)

Examples:
  sudo ./perfSONAR-update-lsregistration.sh \
    --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
    --city Berkeley --region CA --country US --zip 94720 \
    --latitude 37.5 --longitude -121.7469 \
    --admin-name "pS Admin" --admin-email admin@example.org

  # Operate on host file (non-container use)
  sudo ./perfSONAR-update-lsregistration.sh --local \
    --conf /etc/perfsonar/lsregistrationdaemon.conf \
    --site-name "Acme Co." --domain example.org
EOF
}

log() { printf '%s %s\n' "$(date +'%F %T')" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 2; }; }

pick_engine() {
  if [[ "$ENGINE" == "docker" || "$ENGINE" == "podman" ]]; then
    echo "$ENGINE"; return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    echo docker; return 0
  fi
  if command -v podman >/dev/null 2>&1 && podman ps >/dev/null 2>&1; then
    echo podman; return 0
  fi
  echo "No container engine found (docker/podman)" >&2
  exit 2
}

container_exists() {
  local eng=$1 name=$2
  if [[ $eng == docker ]]; then
    docker ps -a --format '{{.Names}}' | grep -Fxq "$name"
  else
    podman ps -a --format '{{.Names}}' | grep -Fxq "$name"
  fi
}

copy_from_container() {
  local eng=$1 name=$2 src=$3 dst=$4
  if [[ $eng == docker ]]; then
    docker cp "$name:$src" "$dst"
  else
    podman cp "$name:$src" "$dst"
  fi
}

copy_to_container() {
  local eng=$1 name=$2 src=$3 dst=$4
  if [[ $eng == docker ]]; then
    docker cp "$src" "$name:$dst"
  else
    podman cp "$src" "$name:$dst"
  fi
}

exec_in_container() {
  local eng=$1 name=$2
  shift 2
  if [[ $eng == docker ]]; then
    docker exec "$name" "$@"
  else
    podman exec "$name" "$@"
  fi
}

# Parse CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --container) CONTAINER="$2"; shift 2;;
    --engine) ENGINE="$2"; shift 2;;
    --local) LOCAL_MODE=true; shift;;
    --conf) CONF_PATH="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    --no-restart) NO_RESTART=true; shift;;
    --site-name) SITE_NAME="$2"; shift 2;;
    --domain) DOMAIN="$2"; shift 2;;
    --project) PROJECTS+=("$2"); shift 2;;
    --city) CITY="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --country) COUNTRY="$2"; shift 2;;
    --zip) ZIP="$2"; shift 2;;
    --latitude) LATITUDE="$2"; shift 2;;
    --longitude) LONGITUDE="$2"; shift 2;;
    --ls-instance) LS_INSTANCE="$2"; shift 2;;
    --ls-lease-duration) LS_LEASE_DURATION="$2"; shift 2;;
    --check-interval) CHECK_INTERVAL="$2"; shift 2;;
    --allow-internal) ALLOW_INTERNAL="$2"; shift 2;;
    --admin-name) ADMIN_NAME="$2"; shift 2;;
    --admin-email) ADMIN_EMAIL="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# Basic validation
if [[ ( -n "$ADMIN_NAME" && -z "$ADMIN_EMAIL" ) || ( -n "$ADMIN_EMAIL" && -z "$ADMIN_NAME" ) ]]; then
  echo "--admin-name and --admin-email must be set together" >&2
  exit 1
fi

if [[ "$LOCAL_MODE" == true ]]; then
  if [[ ! -f "$CONF_PATH" ]]; then
    echo "Local conf not found: $CONF_PATH" >&2
    exit 2
  fi
else
  ENG=$(pick_engine)
  need_cmd "$ENG"
  if ! container_exists "$ENG" "$CONTAINER"; then
    echo "Container '$CONTAINER' not found with $ENG" >&2
    exit 1
  fi
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
local_conf="$workdir/lsregistrationdaemon.conf"
orig_conf="$workdir/lsregistrationdaemon.conf.orig"

if [[ "$LOCAL_MODE" == true ]]; then
  log "Copying local $CONF_PATH"
  cp -a "$CONF_PATH" "$local_conf"
else
  log "Copying $CONF_PATH from container $CONTAINER"
  copy_from_container "$ENG" "$CONTAINER" "$CONF_PATH" "$local_conf"
fi
cp -a "$local_conf" "$orig_conf"

# Helpers to mutate the file
append_header_once() {
  local hdr='# --- Updated by perfSONAR-update-lsregistration.sh ---'
  if ! grep -Fq "$hdr" "$local_conf"; then
    printf '\n%s\n' "$hdr" >> "$local_conf"
  fi
}

upsert_kv() {
  local key="$1" val="$2"
  [[ -z "$val" ]] && return 0
  # Remove existing uncommented occurrences of the key (start of line)
  sed -i -E "/^\s*${key}\b/d" "$local_conf"
  append_header_once
  printf '%s %s\n' "$key" "$val" >> "$local_conf"
}

set_projects() {
  local -a items=("${PROJECTS[@]}")
  [[ ${#items[@]} -eq 0 ]] && return 0
  # Remove existing uncommented site_project lines, then add unique
  sed -i -E '/^\s*site_project\b/d' "$local_conf"
  # de-dup
  mapfile -t items < <(printf '%s\n' "${items[@]}" | awk 'NF{seen[$0]++} END{for (i in seen) print i}' | sort)
  append_header_once
  for p in "${items[@]}"; do
    printf 'site_project %s\n' "$p" >> "$local_conf"
  done
}

set_admin_block() {
  local name="$1" mail="$2"
  [[ -z "$name" || -z "$mail" ]] && return 0
  # Remove existing uncommented administrator block
  awk 'BEGIN{skip=0} 
       /^<administrator>/{skip=1; next}
       /^<\/administrator>/{skip=0; next}
       skip==0{print}' "$local_conf" > "$local_conf.tmp" && mv "$local_conf.tmp" "$local_conf"
  append_header_once
  cat >> "$local_conf" <<EOF
<administrator>
    name      $name
    email     $mail
</administrator>
EOF
}

# Apply requested changes
upsert_kv site_name "$SITE_NAME"
upsert_kv domain "$DOMAIN"
set_projects
upsert_kv city "$CITY"
upsert_kv region "$REGION"
upsert_kv country "$COUNTRY"
upsert_kv zip_code "$ZIP"
upsert_kv latitude "$LATITUDE"
upsert_kv longitude "$LONGITUDE"
upsert_kv ls_instance "$LS_INSTANCE"
upsert_kv ls_lease_duration "$LS_LEASE_DURATION"
upsert_kv check_interval "$CHECK_INTERVAL"
upsert_kv allow_internal_addresses "$ALLOW_INTERNAL"
set_admin_block "$ADMIN_NAME" "$ADMIN_EMAIL"

# Show diff if any
if command -v diff >/dev/null 2>&1; then
  if ! diff -u "$orig_conf" "$local_conf" >/dev/null; then
    log "Changes to be applied:"
    diff -u "$orig_conf" "$local_conf" || true
  else
    log "No changes detected."
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  log "Dry-run: not copying updated file back."
  exit 0
fi

if [[ "$LOCAL_MODE" == true ]]; then
  log "Writing updated file to $CONF_PATH"
  cp -a "$local_conf" "$CONF_PATH"
  if [[ "$NO_RESTART" == true ]]; then
    log "Skipping service restart as requested."
    exit 0
  fi
  log "Restarting lsregistrationdaemon on host (best-effort)"
  if ! bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'; then
    log "Warning: failed to restart lsregistrationdaemon on host"
  fi
else
  log "Copying updated file back to container"
  copy_to_container "$ENG" "$CONTAINER" "$local_conf" "$CONF_PATH"
  if [[ "$NO_RESTART" == true ]]; then
    log "Skipping service restart as requested."
    exit 0
  fi
  log "Restarting lsregistrationdaemon (best-effort)"
  if ! exec_in_container "$ENG" "$CONTAINER" bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'; then
    log "Warning: failed to restart lsregistrationdaemon"
  fi
fi

log "Done."
