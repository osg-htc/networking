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
#   --with-certbot        Install certbot service alongside testpoint
#   --auto-update         Install perfsonar-auto-update.sh and a daily systemd
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
# Version: 1.3.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Version history:
#   1.3.0 - Add /run/dbus and node_exporter.defaults volume mounts to the
#           generated service unit; create conf/ dir and seed defaults file.
#   1.2.0 - Add --health-monitor flag for perfSONAR health watchdog.

set -e

# Default values
INSTALL_DIR="/opt/perfsonar-tp"
WITH_CERTBOT=false
AUTO_UPDATE=false
HEALTH_MONITOR=false

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
        --auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        --health-monitor)
            HEALTH_MONITOR=true
            shift
            ;;
        --help)
            head -n 25 "$0" | grep "^#" | sed 's/^# \?//'
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

# When --auto-update is the only goal (service already exists), skip rewriting
# the testpoint/certbot service units to avoid disrupting a running deployment.
SKIP_SERVICE_UNITS=false
if [[ "$AUTO_UPDATE" == "true" && -f "$TESTPOINT_SERVICE" ]]; then
    echo "==> Existing $TESTPOINT_SERVICE detected — skipping service unit rewrite (use without --auto-update to reinstall)"
    SKIP_SERVICE_UNITS=true
fi

# Create perfsonar-testpoint service (skip if already present and only --auto-update was requested)
if [[ "$SKIP_SERVICE_UNITS" == "false" ]]; then
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
  -v $INSTALL_DIR/psconfig:/etc/perfsonar/psconfig:Z \\
  -v /var/www/html:/var/www/html:z \\
  -v /etc/apache2:/etc/apache2:z \\
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \\
  -v /etc/letsencrypt:/etc/letsencrypt:z \\
  -v $INSTALL_DIR/tools_scripts:$INSTALL_DIR/tools_scripts:ro \\
  -v /run/dbus:/run/dbus:ro \\
  -v $INSTALL_DIR/conf/node_exporter.defaults:/etc/default/node_exporter:z \\
  --cap-add=NET_RAW --cap-add=SYS_ADMIN --cap-add=SYS_PTRACE \\
  --label=io.containers.autoupdate=registry \\
  hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production \\
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
  -v /var/www/html:/var/www/html:Z \\
  -v /etc/letsencrypt:/etc/letsencrypt:Z \\
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
