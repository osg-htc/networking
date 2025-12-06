#!/usr/bin/env bash
# Combined lsregistration helper
# Version: 1.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# Supports: save, restore, create, update, extract
# Works against a container (docker|podman) or local filesystem.

set -euo pipefail
IFS=$'\n\t'

PROG_NAME=$(basename "$0")

DEFAULT_CONTAINER="perfsonar-testpoint"
DEFAULT_CONF_PATH="/etc/perfsonar/lsregistrationdaemon.conf"

# Global defaults
CONTAINER="$DEFAULT_CONTAINER"
ENGINE="auto"   # auto|docker|podman
CONF_PATH="$DEFAULT_CONF_PATH"
DRY_RUN=false
NO_RESTART=false
LOCAL_MODE=false

# Common fields
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
	cat <<EOF
Usage: $PROG_NAME <command> [OPTIONS]

Commands:
	save    --output FILE       Save current lsregistrationdaemon.conf to FILE
	restore --input FILE        Restore FILE into target (container or local)
	create  --input FILE|--build Build a fresh conf from options and install
	update  [options]           Update existing conf in-place (fields below)
	extract --output FILE       Produce a self-contained restore script (host-targeted)

Global options:
	--container NAME            Container name (default: $DEFAULT_CONTAINER)
	--engine [auto|docker|podman]
	--conf PATH                 Path to lsregistrationdaemon.conf (default: $DEFAULT_CONF_PATH)
	--local                     Operate on local filesystem instead of container
	--dry-run                   Show actions but do not write back
	--no-restart                Do not attempt to restart lsregistration daemon after write

Fields (used by create/update):
	--site-name STR
	--domain STR
	--project STR               (may be repeated)
	--city STR
	--region STR
	--country STR
	--zip STR
	--latitude NUM
	--longitude NUM
	--ls-instance URL
	--ls-lease-duration SEC
	--check-interval SEC
	--allow-internal 0|1
	--admin-name STR
	--admin-email STR

Examples:
	# Update fields in container
	$PROG_NAME update --site-name "Acme" --domain example.org --project OSG

	# Save conf to local file
	$PROG_NAME save --output ./lsreg.conf

	# Create a fresh conf from fields and install into container
	$PROG_NAME create --site-name "Acme" --domain example.org --project OSG

	# Produce a self-contained restore script for host use
	$PROG_NAME extract --output restore-lsreg.sh

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

make_workdir() {
	mktemp -d
}

append_header_once() {
	local file=$1
	local hdr='# --- Updated by perfSONAR lsregistration helper ---'
	if ! grep -Fq "$hdr" "$file"; then
		printf '\n%s\n' "$hdr" >> "$file"
	fi
}

upsert_kv() {
	local file=$1 key=$2 val=$3
	[[ -z "$val" ]] && return 0
	sed -i -E "/^\s*${key}\b/d" "$file"
	append_header_once "$file"
	printf '%s %s\n' "$key" "$val" >> "$file"
}

set_projects_in_file() {
	local file=$1; shift
	local -a items=("$@")
	[[ ${#items[@]} -eq 0 ]] && return 0
	sed -i -E '/^\s*site_project\b/d' "$file"
	# de-dup and preserve order
	declare -A seen=()
	for p in "${items[@]}"; do
		[[ -n "${p// /}" ]] || continue
		if [[ -z "${seen[$p]:-}" ]]; then
			echo "site_project $p" >> "$file"
			seen[$p]=1
		fi
	done
}

set_admin_block_in_file() {
	local file=$1 name=$2 mail=$3
	[[ -z "$name" || -z "$mail" ]] && return 0
	awk 'BEGIN{skip=0} /^<administrator>/{skip=1; next} /^<\/administrator>/{skip=0; next} skip==0{print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
	append_header_once "$file"
	cat >> "$file" <<EOF
<administrator>
		name      $name
		email     $mail
</administrator>
EOF
}

do_save() {
	local outpath="${OUT_PATH:-}" workdir
	if [[ -z "$outpath" ]]; then echo "--output is required for save" >&2; exit 1; fi
	workdir=$(make_workdir)
	trap 'rm -rf "$workdir"' RETURN
	local tmp="$workdir/lsregistrationdaemon.conf"
	if [[ "$LOCAL_MODE" == true ]]; then
		cp -a "$CONF_PATH" "$tmp"
	else
		ENG=$(pick_engine)
		need_cmd "$ENG"
		if ! container_exists "$ENG" "$CONTAINER"; then echo "Container '$CONTAINER' not found" >&2; exit 1; fi
		copy_from_container "$ENG" "$CONTAINER" "$CONF_PATH" "$tmp"
	fi
	cp -a "$tmp" "$outpath"
	log "Saved conf to $outpath"
}

do_restore() {
	local inpath="${IN_PATH:-}" workdir
	if [[ -z "$inpath" ]]; then echo "--input is required for restore" >&2; exit 1; fi
	if [[ ! -f "$inpath" ]]; then echo "Input file not found: $inpath" >&2; exit 1; fi
	workdir=$(make_workdir)
	trap 'rm -rf "$workdir"' RETURN
	local tmp="$workdir/lsregistrationdaemon.conf"
	cp -a "$inpath" "$tmp"
	if [[ "$DRY_RUN" == true ]]; then log "Dry-run: would restore $inpath to target"; return 0; fi
	if [[ "$LOCAL_MODE" == true ]]; then
		log "Writing $inpath to $CONF_PATH"
		cp -a "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			log "Restarting lsregistrationdaemon on host (best-effort)"
			bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	else
		ENG=$(pick_engine)
		need_cmd "$ENG"
		if ! container_exists "$ENG" "$CONTAINER"; then echo "Container '$CONTAINER' not found" >&2; exit 1; fi
		copy_to_container "$ENG" "$CONTAINER" "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			log "Restarting lsregistrationdaemon inside container (best-effort)"
			exec_in_container "$ENG" "$CONTAINER" bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	fi
	log "Restore complete"
}

do_update() {
	# Copy out, mutate, copy back
		local workdir
		workdir=$(make_workdir)
		trap 'rm -rf "$workdir"' RETURN
	local tmp="$workdir/lsregistrationdaemon.conf"
	local orig="$workdir/lsregistrationdaemon.conf.orig"
	if [[ "$LOCAL_MODE" == true ]]; then
		cp -a "$CONF_PATH" "$tmp"
	else
		ENG=$(pick_engine)
		need_cmd "$ENG"
		if ! container_exists "$ENG" "$CONTAINER"; then echo "Container '$CONTAINER' not found" >&2; exit 1; fi
		copy_from_container "$ENG" "$CONTAINER" "$CONF_PATH" "$tmp"
	fi
	cp -a "$tmp" "$orig"

	upsert_kv "$tmp" site_name "$SITE_NAME"
	upsert_kv "$tmp" domain "$DOMAIN"
	set_projects_in_file "$tmp" "${PROJECTS[@]:-}"
	upsert_kv "$tmp" city "$CITY"
	upsert_kv "$tmp" region "$REGION"
	upsert_kv "$tmp" country "$COUNTRY"
	upsert_kv "$tmp" zip_code "$ZIP"
	upsert_kv "$tmp" latitude "$LATITUDE"
	upsert_kv "$tmp" longitude "$LONGITUDE"
	upsert_kv "$tmp" ls_instance "$LS_INSTANCE"
	upsert_kv "$tmp" ls_lease_duration "$LS_LEASE_DURATION"
	upsert_kv "$tmp" check_interval "$CHECK_INTERVAL"
	upsert_kv "$tmp" allow_internal_addresses "$ALLOW_INTERNAL"
	set_admin_block_in_file "$tmp" "$ADMIN_NAME" "$ADMIN_EMAIL"

	if command -v diff >/dev/null 2>&1; then
		if ! diff -u "$orig" "$tmp" >/dev/null 2>&1; then
			log "Changes to be applied:"
			diff -u "$orig" "$tmp" || true
		else
			log "No changes detected."
			return 0
		fi
	fi

	if [[ "$DRY_RUN" == true ]]; then
		log "Dry-run: not copying updated file back."
		return 0
	fi

	if [[ "$LOCAL_MODE" == true ]]; then
		log "Writing updated file to $CONF_PATH"
		cp -a "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			log "Restarting lsregistrationdaemon on host (best-effort)"
			bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	else
		log "Copying updated file back to container"
		copy_to_container "$ENG" "$CONTAINER" "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			log "Restarting lsregistrationdaemon inside container (best-effort)"
			exec_in_container "$ENG" "$CONTAINER" bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	fi
	log "Update complete"
}

do_create() {
	# Build a minimal conf from provided fields and install (similar to restore)
		local workdir
		workdir=$(make_workdir)
		trap 'rm -rf "$workdir"' RETURN
	local tmp="$workdir/lsregistrationdaemon.conf"
	# Start from empty or a small header
	cat > "$tmp" <<EOF
# perfSONAR lsregistrationdaemon.conf generated by $PROG_NAME on $(date)
EOF
	upsert_kv "$tmp" site_name "$SITE_NAME"
	upsert_kv "$tmp" domain "$DOMAIN"
	set_projects_in_file "$tmp" "${PROJECTS[@]:-}"
	upsert_kv "$tmp" city "$CITY"
	upsert_kv "$tmp" region "$REGION"
	upsert_kv "$tmp" country "$COUNTRY"
	upsert_kv "$tmp" zip_code "$ZIP"
	upsert_kv "$tmp" latitude "$LATITUDE"
	upsert_kv "$tmp" longitude "$LONGITUDE"
	upsert_kv "$tmp" ls_instance "$LS_INSTANCE"
	upsert_kv "$tmp" ls_lease_duration "$LS_LEASE_DURATION"
	upsert_kv "$tmp" check_interval "$CHECK_INTERVAL"
	upsert_kv "$tmp" allow_internal_addresses "$ALLOW_INTERNAL"
	set_admin_block_in_file "$tmp" "$ADMIN_NAME" "$ADMIN_EMAIL"

	if [[ "$DRY_RUN" == true ]]; then
		log "Dry-run: would write created conf:\n"; sed -n '1,200p' "$tmp"
		return 0
	fi

	if [[ "$LOCAL_MODE" == true ]]; then
		cp -a "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			log "Restarting lsregistrationdaemon on host (best-effort)"
			bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	else
		ENG=$(pick_engine)
		need_cmd "$ENG"
		if ! container_exists "$ENG" "$CONTAINER"; then echo "Container '$CONTAINER' not found" >&2; exit 1; fi
		copy_to_container "$ENG" "$CONTAINER" "$tmp" "$CONF_PATH"
		if [[ "$NO_RESTART" != true ]]; then
			exec_in_container "$ENG" "$CONTAINER" bash -lc 'systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || pkill -HUP -f lsregistrationdaemon || true'
		fi
	fi
	log "Create/install complete"
}

do_extract() {
	local out="${OUT_PATH:-}" workdir
	if [[ -z "$out" ]]; then echo "--output is required for extract" >&2; exit 1; fi
	workdir=$(make_workdir)
	trap 'rm -rf "$workdir"' RETURN
	local tmp="$workdir/lsregistrationdaemon.conf"
	if [[ "$LOCAL_MODE" == true ]]; then
		cp -a "$CONF_PATH" "$tmp"
	else
		ENG=$(pick_engine)
		need_cmd "$ENG"
		copy_from_container "$ENG" "$CONTAINER" "$CONF_PATH" "$tmp"
	fi
	# Emit a self-contained restore script that writes the conf to /etc/perfsonar/lsregistrationdaemon.conf
	cat > "$out" <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
CONF_PATH="/etc/perfsonar/lsregistrationdaemon.conf"
TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'CONF_CONTENT'
SCRIPT_EOF
	# append the conf, escaping EOF delimiting
	sed 's/^/ /' "$tmp" >> "$out"
	cat >> "$out" <<'SCRIPT_EOF'
CONF_CONTENT
$(cat "$tmp")
CONF_CONTENT
SCRIPT_EOF
	cat >> "$out" <<'SCRIPT_EOF'
cp "$TMPFILE" "$CONF_PATH"
rm -f "$TMPFILE"
if command -v systemctl >/dev/null 2>&1; then
	systemctl restart lsregistrationdaemon 2>/dev/null || systemctl try-restart lsregistrationdaemon 2>/dev/null || true
else
	pkill -HUP -f lsregistrationdaemon || true
fi
SCRIPT_EOF
	chmod a+x "$out"
	log "Wrote self-contained restore script to $out"
}

# CLI parsing: first arg is command
if [[ $# -lt 1 ]]; then usage; exit 1; fi
CMD="$1"; shift

OUT_PATH="" IN_PATH=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--help|-h) usage; exit 0;;
		--container) CONTAINER="$2"; shift 2;;
		--engine) ENGINE="$2"; shift 2;;
		--local) LOCAL_MODE=true; shift;;
		--conf) CONF_PATH="$2"; shift 2;;
		--dry-run) DRY_RUN=true; shift;;
		--no-restart) NO_RESTART=true; shift;;
		--output) OUT_PATH="$2"; shift 2;;
		--input) IN_PATH="$2"; shift 2;;
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

case "$CMD" in
	save)
		do_save
		;;
	restore)
		do_restore
		;;
	update)
		do_update
		;;
	create)
		do_create
		;;
	extract)
		do_extract
		;;
	*) echo "Unknown command: $CMD" >&2; usage; exit 1;;
esac

exit 0
