#!/bin/sh
# certbot-deploy-hook.sh
# This script is executed by Certbot's --deploy-hook after a successful renewal.
# It gracefully restarts the perfsonar-testpoint container to load the new certificate.
#
# It requires the host's Podman socket to be mounted into the certbot container.
#
# Version: 1.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -eu

# The name of the container to restart
TARGET_CONTAINER="perfsonar-testpoint"

echo "[INFO] Certbot deploy hook triggered for domains: $RENEWED_DOMAINS"
echo "[INFO] Attempting to gracefully restart container: $TARGET_CONTAINER"

# Use the mounted Podman socket to restart the container on the host
# The --time=30 gives the container 30 seconds to shut down gracefully
if podman restart --time=30 "$TARGET_CONTAINER" >/dev/null 2>&1; then
  echo "[SUCCESS] Container '$TARGET_CONTAINER' restarted successfully."
else
  echo "[ERROR] Failed to restart container '$TARGET_CONTAINER'." >&2
  exit 1
fi
