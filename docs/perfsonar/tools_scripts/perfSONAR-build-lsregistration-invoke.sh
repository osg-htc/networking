#!/usr/bin/env bash
# Generate a perfSONAR-update-lsregistration.sh invocation from an existing
# lsregistrationdaemon.conf configuration file.
#
# This helper parses key fields from an lsregistrationdaemon.conf and prints a
# ready-to-run command line with the equivalent flags. It does not modify any
# files.
#
# Default conf path: /etc/perfsonar/lsregistrationdaemon.conf
#
# Example:
#   ./perfSONAR-build-lsregistration-invoke.sh \
#     --conf /etc/perfsonar/lsregistrationdaemon.conf \
#     --script ./perfSONAR-update-lsregistration.sh \
#     --container perfsonar-testpoint
#
# Output:
#   sudo ./perfSONAR-update-lsregistration.sh --container perfsonar-testpoint \
#     --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
#     --city Berkeley --region CA --country US --zip 94720 \
#     --latitude 37.5 --longitude -121.7469 \
#     --ls-instance https://ls.example.org/lookup/records \
#     --ls-lease-duration 7200 --check-interval 3600 --allow-internal 0 \
#     --admin-name "pS Admin" --admin-email admin@example.org
#
set -euo pipefail
IFS=$'\n\t'

CONF_PATH="/etc/perfsonar/lsregistrationdaemon.conf"
SCRIPT_PATH="./perfSONAR-update-lsregistration.sh"
INCLUDE_SUDO=true
CONTAINER_NAME=""
ENGINE=""
FLAGS_ONLY=false

usage() {
  cat <<'EOF'
Usage: perfSONAR-build-lsregistration-invoke.sh [OPTIONS]

Options:
  --conf PATH           Path to lsregistrationdaemon.conf (default: /etc/perfsonar/lsregistrationdaemon.conf)
  --script PATH         Path to perfSONAR-update-lsregistration.sh (default: ./perfSONAR-update-lsregistration.sh)
  --container NAME      Include --container NAME in the generated command
  --engine auto|docker|podman  Include --engine in the generated command
  --no-sudo             Do not prefix the command with 'sudo'
  --flags-only          Print only the flags (omit the script path and sudo)
  -h, --help            Show this help

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

# quote-safe print of a command array
print_cmd() {
  local -a arr=("$@")
  local out=""
  for el in "${arr[@]}"; do
    # shell-escape like printf %q (portable in bash)
    printf -v q '%q' "$el"
    out+="$q "
  done
  # trim trailing space
  out=${out%% } 
  printf '%s\n' "$out"
}

# Parse CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --conf) CONF_PATH="$2"; shift 2;;
    --script) SCRIPT_PATH="$2"; shift 2;;
    --container) CONTAINER_NAME="$2"; shift 2;;
    --engine) ENGINE="$2"; shift 2;;
    --no-sudo) INCLUDE_SUDO=false; shift;;
    --flags-only) FLAGS_ONLY=true; shift;;
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

# Build arguments
args=()
if [[ -n "$CONTAINER_NAME" ]]; then args+=(--container "$CONTAINER_NAME"); fi
if [[ -n "$ENGINE" ]]; then args+=(--engine "$ENGINE"); fi
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

if [[ "$FLAGS_ONLY" == true ]]; then
  print_cmd "${args[@]}"
  exit 0
fi

cmd_arr=()
if [[ "$INCLUDE_SUDO" == true ]]; then cmd_arr+=(sudo); fi
cmd_arr+=("$SCRIPT_PATH")
cmd_arr+=("${args[@]}")
print_cmd "${cmd_arr[@]}"
