#!/bin/bash
# install-systemd-service.sh
# --------------------------
# Purpose:
#   Install and enable a systemd service to manage perfSONAR testpoint containers
#   with podman-compose. This ensures containers restart automatically after a 
#   host reboot.
#
# Usage:
#   sudo bash install-systemd-service.sh [/opt/perfsonar-tp]
#
# Arguments:
#   $1 - Installation directory (default: /opt/perfsonar-tp)
#
# Requirements:
#   - Root privileges (sudo)
#   - podman-compose installed
#   - perfSONAR testpoint docker-compose.yml in the installation directory
#
# Author: OSG perfSONAR deployment tools
# Version: 1.0.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -e

# Default installation directory
INSTALL_DIR="${1:-/opt/perfsonar-tp}"
SERVICE_NAME="perfsonar-testpoint"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)" 
   exit 1
fi

# Check if podman-compose is installed
if ! command -v podman-compose &> /dev/null; then
    echo "ERROR: podman-compose is not installed"
    echo "Install it with: dnf install -y podman-compose"
    exit 1
fi

# Check if installation directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "ERROR: Installation directory does not exist: $INSTALL_DIR"
    exit 1
fi

# Check if docker-compose.yml exists
if [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    echo "ERROR: docker-compose.yml not found in $INSTALL_DIR"
    exit 1
fi

echo "==> Installing systemd service for perfSONAR testpoint"
echo "    Installation directory: $INSTALL_DIR"
echo "    Service file: $SERVICE_FILE"

# Create systemd service file
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=perfSONAR Testpoint Container Service
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/opt/perfsonar-tp

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/perfsonar-tp
ExecStart=/usr/bin/podman-compose up -d
ExecStop=/usr/bin/podman-compose down
TimeoutStartSec=300
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Update WorkingDirectory if non-default path is used
if [[ "$INSTALL_DIR" != "/opt/perfsonar-tp" ]]; then
    sed -i "s|WorkingDirectory=/opt/perfsonar-tp|WorkingDirectory=$INSTALL_DIR|g" "$SERVICE_FILE"
    sed -i "s|RequiresMountsFor=/opt/perfsonar-tp|RequiresMountsFor=$INSTALL_DIR|g" "$SERVICE_FILE"
fi

echo "==> Reloading systemd daemon"
systemctl daemon-reload

echo "==> Enabling $SERVICE_NAME service"
systemctl enable "$SERVICE_NAME.service"

echo "==> ✓ Systemd service installed and enabled successfully"
echo ""
echo "Useful commands:"
echo "  Start service:   systemctl start $SERVICE_NAME"
echo "  Stop service:    systemctl stop $SERVICE_NAME"
echo "  Restart service: systemctl restart $SERVICE_NAME"
echo "  Check status:    systemctl status $SERVICE_NAME"
echo "  View logs:       journalctl -u $SERVICE_NAME -f"
echo ""
echo "The service will automatically start containers on boot."
