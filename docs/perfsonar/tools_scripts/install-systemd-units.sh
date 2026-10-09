#!/bin/bash
# install-systemd-units.sh
# ------------------------
# Purpose:
#   Install and enable systemd units to manage perfSONAR testpoint and certbot
#   containers with direct podman run (with --systemd=always flag for proper
#   systemd-in-container support). This ensures containers restart automatically
#   after a host reboot and handle systemd properly.
#
# Usage:
#   sudo bash install-systemd-units.sh [OPTIONS]
#
# Options:
#   --install-dir PATH    Installation directory (default: /opt/perfsonar-tp)
#   --with-certbot        Let's Encrypt deployment (Option B): install the certbot
#                         service and add the LE bind mounts (/var/www/html,
#                         /etc/letsencrypt and the single Apache default-ssl.conf
#                         file) to the testpoint unit. Without this flag the
#                         testpoint unit mounts only what Option A needs.
#                         If perfsonar-certbot.service already exists, LE mode
#                         is kept automatically unless --no-certbot is given.
#   --no-certbot          Force Option A (testpoint-only) mounts even if a
#                         certbot unit from a previous install is present.
#   --convert-from-compose
#                         Allow replacing an existing compose-wrapper unit
#                         (podman-compose up) with a direct 'podman run' unit.
#   --force               Rewrite the service units even when only
#                         --auto-update was requested and a unit already exists
#                         (used by update-perfsonar-deployment.sh to repair
#                         stale units).
#   --auto-update        Install perfsonar-auto-update.sh and a daily systemd
#                         timer that pulls new images and restarts services only
#                         when an image digest has changed (Podman-compatible;
#                         does not rely on Docker-specific output strings)
#   --health-monitor      Install perfSONAR-health-monitor.sh and a systemd
#                         timer that runs every 5 minutes to detect an
#                         'unhealthy' container and restart it automatically
#   --help                Show this help message
#
# Requirements:
#   - Root privileges (sudo)
#   - podman installed
#   - perfSONAR testpoint scripts in installation directory
#
# Author: OSG perfSONAR deployment tools
# Version: 1.5.2
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Version history:
#   1.5.2 - Run the testpoint with --shm-size=512m: PostgreSQL inside the
#           container (pScheduler) runs out of shared memory with the 64 MB
#           default. Matches shm_size: 512m in the compose files.
#   1.5.1 - Refuse to overwrite an existing compose-wrapper unit
#           (ExecStart=podman-compose ..., from install-systemd-service.sh)
#           unless --convert-from-compose is given: on such hosts
#           docker-compose.yml defines the containers (often including
#           certbot) and silently replacing the unit drops them. When
#           converting, Let's Encrypt mode is enabled if the compose file has
#           a certbot service.
#   1.5.0 - Add a container health check to the testpoint unit (podman
#           --health-cmd "pscheduler troubleshoot --quick", 60s interval, 30s
#           timeout, 3 retries, 120s start period — same as the compose files).
#           Without it the health-monitor timer saw "no healthcheck defined"
#           and never restarted a broken container.
#         - Refresh an installed /usr/local/bin/perfsonar-health-monitor.sh
#           from tools_scripts on every run.
#         - Stop bind-mounting the host's /run/dbus into the container. The
#           read-only mount occupied /run/dbus inside the container, so the
#           container's own dbus.socket failed. The units node_exporter's
#           systemd collector watches (pscheduler-*, psconfig-*, owamp,
#           httpd, ...) run inside the container, so it needs the container's
#           own D-Bus, not the host's.
#   1.4.0 - Fix fresh-host start failure ("statfs /var/www/html: no such file
#           or directory", podman exit 125). The unit previously bind-mounted
#           /var/www/html, the whole /etc/apache2 and /etc/letsencrypt for
#           every deployment, but seed_testpoint_host_dirs.sh v2 (Option A)
#           no longer creates them. Mounts now match the compose files:
#             Option A: psconfig, tools_scripts, cgroup, node_exporter
#             Option B: + /var/www/html, /etc/letsencrypt and only
#                       /etc/apache2/sites-available/default-ssl.conf
#           Mounting the whole host /etc/apache2 hid the container's Apache
#           config, so it is no longer done in either mode.
#         - Pre-flight: create/seed every host path the unit mounts and refuse
#           to write a unit whose bind-mount sources are missing.
#         - Certbot unit uses :z (shared) instead of :Z (private MCS) on
#           /var/www/html and /etc/letsencrypt to avoid the SELinux lockout
#           of the testpoint container on EL9/EL10 hosts.
#         - Add --no-certbot and --force options; auto-detect existing LE mode.
#   1.3.0 - Add /run/dbus and node_exporter.defaults volume mounts to the
#           generated service unit; create conf/ dir and seed defaults file.
#   1.2.0 - Add --health-monitor flag for perfSONAR health watchdog.

set -e

# Default values
INSTALL_DIR="/opt/perfsonar-tp"
WITH_CERTBOT=false
NO_CERTBOT=false
FORCE=false
CONVERT_FROM_COMPOSE=false
AUTO_UPDATE=false
HEALTH_MONITOR=false
TP_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production"
LE_SSL_CONF="/etc/apache2/sites-available/default-ssl.conf"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --with-certbot)
            WITH_CERTBOT=true
            shift
            ;;
        --no-certbot)
            NO_CERTBOT=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --convert-from-compose)
            CONVERT_FROM_COMPOSE=true
            shift
            ;;
        --auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        --health-monitor)
            HEALTH_MONITOR=true
            shift
            ;;
        --help)
            sed -n '2,/^# Requirements:/p' "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

TESTPOINT_SERVICE="/etc/systemd/system/perfsonar-testpoint.service"
CERTBOT_SERVICE="/etc/systemd/system/perfsonar-certbot.service"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    echo "ERROR: podman is not installed"
    echo "Install it with: dnf install -y podman"
    exit 1
fi

# Check if installation directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: Installation directory does not exist: $INSTALL_DIR"
    exit 1
fi

# Check if tools_scripts directory exists
if [[ ! -d "$INSTALL_DIR/tools_scripts" ]]; then
    echo "ERROR: tools_scripts directory not found in $INSTALL_DIR"
    echo "Run the bootstrap script first to install helper scripts"
    exit 1
fi

echo "==> Installing systemd units for perfSONAR testpoint"
echo "    Installation directory: $INSTALL_DIR"

# Ensure conf directory exists and seed node_exporter defaults if not already present
mkdir -p "$INSTALL_DIR/conf"
if [[ ! -f "$INSTALL_DIR/conf/node_exporter.defaults" && -f "$INSTALL_DIR/tools_scripts/node_exporter.defaults" ]]; then
    cp "$INSTALL_DIR/tools_scripts/node_exporter.defaults" "$INSTALL_DIR/conf/node_exporter.defaults"
    echo "==> ✓ Seeded $INSTALL_DIR/conf/node_exporter.defaults"
fi

# Never silently replace a compose-wrapper unit: there docker-compose.yml
# defines the containers (often including certbot).
if [[ -f "$TESTPOINT_SERVICE" ]] && grep -q 'podman-compose\|docker compose\|docker-compose' "$TESTPOINT_SERVICE" \
   && ! grep -q 'podman run' "$TESTPOINT_SERVICE"; then
    if [[ "$CONVERT_FROM_COMPOSE" != "true" ]]; then
        echo "ERROR: $TESTPOINT_SERVICE runs podman-compose; docker-compose.yml defines this host's containers." >&2
        echo "       Not replacing it. Keep using update-perfsonar-deployment.sh for this host, or re-run with" >&2
        echo "       --convert-from-compose to switch to a direct 'podman run' unit deliberately." >&2
        exit 1
    fi
    echo "==> Converting compose-wrapper unit to a direct podman run unit (--convert-from-compose)"
    if [[ "$WITH_CERTBOT" != "true" && "$NO_CERTBOT" != "true" ]] && \
       grep -qE '^[[:space:]]*certbot:' "$INSTALL_DIR/docker-compose.yml" 2>/dev/null; then
        echo "==> docker-compose.yml has a certbot service — enabling Let's Encrypt (Option B) mounts"
        WITH_CERTBOT=true
    fi
fi

# Keep Let's Encrypt mode on re-runs: if a certbot unit from a previous LE
# install exists and the caller did not say otherwise, keep the LE mounts so a
# plain re-run (e.g. from update-perfsonar-deployment.sh) does not silently
# drop them.
if [[ "$WITH_CERTBOT" != "true" && "$NO_CERTBOT" != "true" && -f "$CERTBOT_SERVICE" ]]; then
    echo "==> Existing $CERTBOT_SERVICE detected — keeping Let's Encrypt (Option B) mounts"
    echo "    (pass --no-certbot to switch this host to testpoint-only mounts)"
    WITH_CERTBOT=true
fi
if [[ "$NO_CERTBOT" == "true" ]]; then
    WITH_CERTBOT=false
    if [[ -f "$CERTBOT_SERVICE" ]]; then
        echo "==> NOTE: $CERTBOT_SERVICE still exists; disable it if no longer needed:"
        echo "      systemctl disable --now perfsonar-certbot.service"
    fi
fi

# When --auto-update is the only goal (service already exists), skip rewriting
# the testpoint/certbot service units to avoid disrupting a running deployment.
SKIP_SERVICE_UNITS=false
if [[ "$AUTO_UPDATE" == "true" && -f "$TESTPOINT_SERVICE" && "$FORCE" != "true" ]]; then
    echo "==> Existing $TESTPOINT_SERVICE detected — skipping service unit rewrite (use --force or omit --auto-update to reinstall)"
    SKIP_SERVICE_UNITS=true
fi

# Copy a single file out of the testpoint image (used when the seed script is
# unavailable). Returns non-zero if the copy fails.
copy_file_from_image() {
    local src="$1" dst="$2" cname
    cname="perfsonar-unit-seed-$$"
    podman image exists "$TP_IMAGE" 2>/dev/null || podman pull -q "$TP_IMAGE" >/dev/null || return 1
    podman create --name "$cname" "$TP_IMAGE" >/dev/null 2>&1 || return 1
    if podman cp "$cname:$src" "$dst" >/dev/null 2>&1; then
        podman rm -f "$cname" >/dev/null 2>&1 || true
        return 0
    fi
    podman rm -f "$cname" >/dev/null 2>&1 || true
    return 1
}

# Reset private SELinux MCS categories (left behind by earlier :Z mounts, e.g.
# from an old certbot unit) so that both containers can share the directory.
fix_shared_selinux_label() {
    local dir="$1" ctx
    command -v getenforce >/dev/null 2>&1 || return 0
    [[ "$(getenforce 2>/dev/null)" == "Disabled" ]] && return 0
    ctx=$(ls -dZ "$dir" 2>/dev/null | awk '{print $1}')
    if echo "$ctx" | grep -qE ':s0:c[0-9]'; then
        echo "    Resetting private SELinux MCS label on $dir ($ctx)"
        chcon -R -t container_file_t -l s0 "$dir" || \
            echo "    WARNING: chcon failed on $dir — check SELinux policy"
    fi
}

# Pre-flight: make sure every host path the unit will bind-mount exists.
# podman refuses to start a container whose bind-mount source is missing
# ("Error: statfs <path>: no such file or directory", exit 125), and systemd
# would then restart it forever. We build the mount list from what actually
# exists so that the generated unit can always start.
prepare_host_mounts() {
    local seed="$INSTALL_DIR/tools_scripts/seed_testpoint_host_dirs.sh"
    local seed_args=()
    [[ "$WITH_CERTBOT" == "true" ]] && seed_args+=(--with-le)

    echo "==> Pre-flight: checking host paths for bind mounts"

    # psconfig must be populated, otherwise an empty host dir would hide the
    # container's own /etc/perfsonar/psconfig. Only run the seed script on an
    # empty psconfig: it copies image defaults over existing files, which would
    # clobber a configured host. LE paths are handled separately below.
    if [[ ! -d "$INSTALL_DIR/psconfig" || -z "$(ls -A "$INSTALL_DIR/psconfig" 2>/dev/null)" ]]; then
        if [[ -f "$seed" ]]; then
            echo "    Seeding host directories with $(basename "$seed") ${seed_args[*]}"
            bash "$seed" --runtime podman --base "$INSTALL_DIR" "${seed_args[@]}" 2>&1 | grep -E '✓|✗|WARNING|ERROR' | sed 's/^ */    /'
        else
            echo "    WARNING: $seed not found; creating directories only"
        fi
    fi
    mkdir -p "$INSTALL_DIR/psconfig"

    if [[ "$WITH_CERTBOT" == "true" ]]; then
        mkdir -p /var/www/html /etc/letsencrypt "$(dirname "$LE_SSL_CONF")"
        if [[ ! -f "$LE_SSL_CONF" ]]; then
            echo "    Copying $LE_SSL_CONF from $TP_IMAGE"
            copy_file_from_image "$LE_SSL_CONF" "$LE_SSL_CONF" || true
        fi
        if [[ ! -f "$LE_SSL_CONF" ]]; then
            echo "ERROR: $LE_SSL_CONF is missing and could not be seeded from the image." >&2
            echo "       Run: sudo $seed --with-le   and re-run this script." >&2
            exit 1
        fi
        fix_shared_selinux_label /var/www/html
        fix_shared_selinux_label /etc/letsencrypt
    fi

    if [[ ! -x "$INSTALL_DIR/tools_scripts/testpoint-entrypoint-wrapper.sh" ]]; then
        if [[ -f "$INSTALL_DIR/tools_scripts/testpoint-entrypoint-wrapper.sh" ]]; then
            chmod 0755 "$INSTALL_DIR/tools_scripts/testpoint-entrypoint-wrapper.sh"
        else
            echo "ERROR: $INSTALL_DIR/tools_scripts/testpoint-entrypoint-wrapper.sh not found." >&2
            echo "       Run install_tools_scripts.sh first." >&2
            exit 1
        fi
    fi
}

# Assemble the -v options for the testpoint unit. Only paths that exist on
# the host are included; required paths abort the install if missing.
build_testpoint_mounts() {
    TP_MOUNTS=()
    TP_MOUNTS+=("-v $INSTALL_DIR/psconfig:/etc/perfsonar/psconfig:Z")
    TP_MOUNTS+=("-v /sys/fs/cgroup:/sys/fs/cgroup:ro")
    TP_MOUNTS+=("-v $INSTALL_DIR/tools_scripts:$INSTALL_DIR/tools_scripts:ro")

    # No host /run/dbus mount: the container runs its own systemd + D-Bus,
    # and node_exporter's systemd collector must talk to that bus to see the
    # perfSONAR services (they run inside the container). Mounting the host's
    # /run/dbus read-only made the container's dbus.socket fail.

    if [[ -f "$INSTALL_DIR/conf/node_exporter.defaults" ]]; then
        TP_MOUNTS+=("-v $INSTALL_DIR/conf/node_exporter.defaults:/etc/default/node_exporter:z")
    else
        echo "    NOTE: $INSTALL_DIR/conf/node_exporter.defaults not present; using container defaults"
    fi

    if [[ "$WITH_CERTBOT" == "true" ]]; then
        # Option B: webroot for HTTP-01 challenges, certificates, and ONLY the
        # SSL vhost file the entrypoint wrapper patches. The rest of Apache's
        # configuration stays inside the container image.
        TP_MOUNTS+=("-v /var/www/html:/var/www/html:z")
        TP_MOUNTS+=("-v /etc/letsencrypt:/etc/letsencrypt:z")
        TP_MOUNTS+=("-v $LE_SSL_CONF:$LE_SSL_CONF:z")
    fi

    # Final safety net: every bind-mount source must exist.
    local m src missing=0
    for m in "${TP_MOUNTS[@]}"; do
        src="${m#-v }"; src="${src%%:*}"
        if [[ ! -e "$src" ]]; then
            echo "ERROR: bind-mount source missing on host: $src" >&2
            missing=1
        fi
    done
    if [[ $missing -ne 0 ]]; then
        echo "ERROR: refusing to write a unit that cannot start (podman exit 125)." >&2
        exit 1
    fi
}

# Create perfsonar-testpoint service (skip if already present and only --auto-update was requested)
if [[ "$SKIP_SERVICE_UNITS" == "false" ]]; then
prepare_host_mounts
build_testpoint_mounts

if [[ "$WITH_CERTBOT" == "true" ]]; then
    echo "==> Mode: Let's Encrypt (Option B) — testpoint + certbot"
else
    echo "==> Mode: testpoint only (Option A)"
fi

MOUNT_LINES=""
for m in "${TP_MOUNTS[@]}"; do
    MOUNT_LINES+="  $m \\"$'\n'
done

cat > "$TESTPOINT_SERVICE" << EOF
[Unit]
Description=perfSONAR Testpoint Container
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/podman rm -f perfsonar-testpoint
ExecStart=/usr/bin/podman run --name perfsonar-testpoint \\
  --replace \\
  --systemd=always \\
  --network host \\
  --privileged \\
  --cgroupns host \\
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \\
  --shm-size=512m \\
${MOUNT_LINES}  --cap-add=NET_RAW --cap-add=SYS_ADMIN --cap-add=SYS_PTRACE \\
  --label=io.containers.autoupdate=registry \\
  --health-cmd "pscheduler troubleshoot --quick" \\
  --health-interval 60s --health-timeout 30s \\
  --health-retries 3 --health-start-period 120s \\
  $TP_IMAGE \\
  $INSTALL_DIR/tools_scripts/testpoint-entrypoint-wrapper.sh
ExecStop=/usr/bin/podman stop -t 10 perfsonar-testpoint
ExecStopPost=/usr/bin/podman rm -f perfsonar-testpoint

[Install]
WantedBy=multi-user.target
EOF

echo "==> ✓ Created $TESTPOINT_SERVICE"

# Create certbot service if requested
if [[ "$WITH_CERTBOT" == "true" ]]; then
    cat > "$CERTBOT_SERVICE" << EOF
[Unit]
Description=perfSONAR Certbot Renewal Container
After=perfsonar-testpoint.service
Requires=perfsonar-testpoint.service

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/podman rm -f certbot
ExecStart=/usr/bin/podman run --name certbot \\
  --replace \\
  --systemd=always \\
  --network host \\
  --entrypoint=/bin/sh \\
  -v /run/podman/podman.sock:/run/podman/podman.sock:ro \\
  -v /var/www/html:/var/www/html:z \\
  -v /etc/letsencrypt:/etc/letsencrypt:z \\
  -v $INSTALL_DIR/tools_scripts/certbot-deploy-hook.sh:/etc/letsencrypt/renewal-hooks/deploy/certbot-deploy-hook.sh:ro \\
  --label=io.containers.autoupdate=registry \\
  docker.io/certbot/certbot:latest \\
  -c "trap 'exit 0' TERM; while :; do certbot renew; sleep 12h & wait \$\$!; done"
ExecStop=/usr/bin/podman stop -t 10 certbot
ExecStopPost=/usr/bin/podman rm -f certbot

[Install]
WantedBy=multi-user.target
EOF

    echo "==> ✓ Created $CERTBOT_SERVICE"
fi

fi  # end SKIP_SERVICE_UNITS guard

# Reload systemd
echo "==> Reloading systemd daemon"
systemctl daemon-reload

# Enable services (only if service units were written)
if [[ "$SKIP_SERVICE_UNITS" == "false" ]]; then
    echo "==> Enabling perfsonar-testpoint service"
    systemctl enable perfsonar-testpoint.service

    if [[ "$WITH_CERTBOT" == "true" ]]; then
        echo "==> Enabling perfsonar-certbot service"
        systemctl enable perfsonar-certbot.service
    fi

    echo ""
    echo "==> ✓ Systemd units installed and enabled successfully"
    echo ""
    echo "Useful commands:"
    echo "  Start services:   systemctl start perfsonar-testpoint.service"
    if [[ "$WITH_CERTBOT" == "true" ]]; then
        echo "                    systemctl start perfsonar-certbot.service"
    fi
    echo "  Stop services:    systemctl stop perfsonar-testpoint.service"
    if [[ "$WITH_CERTBOT" == "true" ]]; then
        echo "                    systemctl stop perfsonar-certbot.service"
    fi
    echo "  Check status:     systemctl status perfsonar-testpoint.service"
    if [[ "$WITH_CERTBOT" == "true" ]]; then
        echo "                    systemctl status perfsonar-certbot.service"
    fi
    echo "  View logs:        journalctl -u perfsonar-testpoint.service -f"
    if [[ "$WITH_CERTBOT" == "true" ]]; then
        echo "                    journalctl -u perfsonar-certbot.service -f"
    fi
    echo "  Check containers: podman ps"
    echo ""
    echo "The services will automatically start containers on boot."
    echo ""
    echo "Note: These units use 'podman run --systemd=always' for proper systemd"
    echo "      support inside the container. This is required for the testpoint"
    echo "      image which runs systemd internally."
fi

# ── Optional: auto-update timer ────────────────────────────────────────────────
if [[ "$AUTO_UPDATE" == "true" ]]; then
    AUTO_UPDATE_SCRIPT="$INSTALL_DIR/tools_scripts/perfSONAR-auto-update.sh"
    AUTO_UPDATE_BIN="/usr/local/bin/perfsonar-auto-update.sh"
    AUTO_UPDATE_SVC="/etc/systemd/system/perfsonar-auto-update.service"
    AUTO_UPDATE_TIMER="/etc/systemd/system/perfsonar-auto-update.timer"

    echo ""
    echo "==> Installing auto-update timer"

    # Use the versioned script from tools_scripts if present, else fall back to a
    # minimal inline version.
    if [[ -f "$AUTO_UPDATE_SCRIPT" ]]; then
        cp "$AUTO_UPDATE_SCRIPT" "$AUTO_UPDATE_BIN"
    else
        echo "WARNING: $AUTO_UPDATE_SCRIPT not found; writing minimal inline script."
        cat > "$AUTO_UPDATE_BIN" << 'AUTOUPDATE_EOF'
#!/bin/bash
# perfsonar-auto-update.sh (minimal inline fallback)
# For the full versioned script, re-run bootstrap (install_tools_scripts.sh).
set -euo pipefail
LOGFILE="/var/log/perfsonar-auto-update.log"
TESTPOINT_IMAGE="hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production"
CERTBOT_IMAGE="docker.io/certbot/certbot:latest"
log() { echo "$(date -Iseconds) $*" | tee -a "$LOGFILE"; }
get_id() { podman image inspect "$1" --format '{{.Id}}' 2>/dev/null || echo none; }
check_pull() {
    local img=$1 before after
    before=$(get_id "$img")
    podman pull "$img" >> "$LOGFILE" 2>&1 || { log "WARNING: pull failed for $img"; echo unchanged; return; }
    after=$(get_id "$img")
    [[ "$before" == "none" || "$before" != "$after" ]] && echo updated || echo unchanged
}
log '=== perfSONAR auto-update check ==='
ANY=false
[[ $(check_pull "$TESTPOINT_IMAGE") == updated ]] && ANY=true
podman ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^certbot$' && \
    [[ $(check_pull "$CERTBOT_IMAGE") == updated ]] && ANY=true
$ANY && systemctl restart perfsonar-testpoint.service && log 'Restarted testpoint.service' || log 'No updates'
log '=== done ==='
AUTOUPDATE_EOF
    fi
    chmod 0755 "$AUTO_UPDATE_BIN"
    echo "==> ✓ Installed $AUTO_UPDATE_BIN"

    cat > "$AUTO_UPDATE_SVC" << 'EOF'
[Unit]
Description=perfSONAR Container Auto-Update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/perfsonar-auto-update.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo "==> ✓ Created $AUTO_UPDATE_SVC"

    cat > "$AUTO_UPDATE_TIMER" << 'EOF'
[Unit]
Description=perfSONAR Container Auto-Update Timer

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    echo "==> ✓ Created $AUTO_UPDATE_TIMER"

    systemctl daemon-reload
    systemctl enable --now perfsonar-auto-update.timer
    echo "==> ✓ Enabled perfsonar-auto-update.timer (runs daily at 03:00 + up to 1h random delay)"
    echo ""
    echo "Useful auto-update commands:"
    echo "  Check timer:      systemctl list-timers perfsonar-auto-update.timer"
    echo "  Run now (test):   systemctl start perfsonar-auto-update.service"
    echo "  View log:         journalctl -u perfsonar-auto-update.service -f"
    echo "  Update log file:  tail -f /var/log/perfsonar-auto-update.log"
fi

# Keep an already-installed health monitor current even when --health-monitor
# is not given (e.g. update-perfsonar-deployment.sh re-running this script).
if [[ "$HEALTH_MONITOR" != "true" && -f /usr/local/bin/perfsonar-health-monitor.sh && \
      -f "$INSTALL_DIR/tools_scripts/perfSONAR-health-monitor.sh" ]]; then
    if ! cmp -s "$INSTALL_DIR/tools_scripts/perfSONAR-health-monitor.sh" /usr/local/bin/perfsonar-health-monitor.sh; then
        cp "$INSTALL_DIR/tools_scripts/perfSONAR-health-monitor.sh" /usr/local/bin/perfsonar-health-monitor.sh
        chmod 0755 /usr/local/bin/perfsonar-health-monitor.sh
        echo "==> ✓ Updated /usr/local/bin/perfsonar-health-monitor.sh"
    fi
fi

# ── Optional: health-monitor timer ────────────────────────────────────────────
if [[ "$HEALTH_MONITOR" == "true" ]]; then
    HEALTH_MONITOR_SCRIPT="$INSTALL_DIR/tools_scripts/perfSONAR-health-monitor.sh"
    HEALTH_MONITOR_BIN="/usr/local/bin/perfsonar-health-monitor.sh"
    HEALTH_MONITOR_SVC="/etc/systemd/system/perfsonar-health-monitor.service"
    HEALTH_MONITOR_TIMER="/etc/systemd/system/perfsonar-health-monitor.timer"

    echo ""
    echo "==> Installing health-monitor timer"

    if [[ -f "$HEALTH_MONITOR_SCRIPT" ]]; then
        cp "$HEALTH_MONITOR_SCRIPT" "$HEALTH_MONITOR_BIN"
        chmod 0755 "$HEALTH_MONITOR_BIN"
        echo "==> ✓ Installed $HEALTH_MONITOR_BIN"
    else
        echo "WARNING: $HEALTH_MONITOR_SCRIPT not found — re-run bootstrap (install_tools_scripts.sh) first"
    fi

    cat > "$HEALTH_MONITOR_SVC" << 'EOF'
[Unit]
Description=perfSONAR Container Health Monitor
After=perfsonar-testpoint.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/perfsonar-health-monitor.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo "==> ✓ Created $HEALTH_MONITOR_SVC"

    cat > "$HEALTH_MONITOR_TIMER" << 'EOF'
[Unit]
Description=perfSONAR Container Health Monitor Timer

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
    echo "==> ✓ Created $HEALTH_MONITOR_TIMER"

    systemctl daemon-reload
    systemctl enable --now perfsonar-health-monitor.timer
    echo "==> ✓ Enabled perfsonar-health-monitor.timer (runs every 5 minutes)"
    echo ""
    echo "Useful health-monitor commands:"
    echo "  Check timer:      systemctl list-timers perfsonar-health-monitor.timer"
    echo "  Run now (test):   systemctl start perfsonar-health-monitor.service"
    echo "  View log:         journalctl -u perfsonar-health-monitor.service -f"
    echo "  Monitor log file: tail -f /var/log/perfsonar-health-monitor.log"
fi
