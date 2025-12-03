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
#   --help                Show this help message
#
# Requirements:
#   - Root privileges (sudo)
#   - podman installed
#   - perfSONAR testpoint scripts in installation directory
#
# Author: OSG perfSONAR deployment tools
# Version: 1.0.0

set -e

# Default values
INSTALL_DIR="/opt/perfsonar-tp"
WITH_CERTBOT=false

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
        --help)
            head -n 20 "$0" | grep "^#" | sed 's/^# \?//'
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

# Create perfsonar-testpoint service
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
  --network host \\
  -v /run/podman/podman.sock:/run/podman/podman.sock:ro \\
  -v /var/www/html:/var/www/html:Z \\
  -v /etc/letsencrypt:/etc/letsencrypt:Z \\
  -v $INSTALL_DIR/tools_scripts/certbot-deploy-hook.sh:/etc/letsencrypt/renewal-hooks/deploy/certbot-deploy-hook.sh:ro \\
  --label=io.containers.autoupdate=registry \\
  docker.io/certbot/certbot:latest \\
  /bin/sh -c 'trap exit TERM; while :; do certbot renew --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/certbot-deploy-hook.sh; sleep 12h & wait \$\$!; done'
ExecStop=/usr/bin/podman stop -t 10 certbot
ExecStopPost=/usr/bin/podman rm -f certbot

[Install]
WantedBy=multi-user.target
EOF

    echo "==> ✓ Created $CERTBOT_SERVICE"
fi

# Reload systemd
echo "==> Reloading systemd daemon"
systemctl daemon-reload

# Enable services
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
