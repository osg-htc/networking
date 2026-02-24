#!/bin/sh
# certbot-deploy-hook.sh
# This script is executed by Certbot's --deploy-hook after a successful renewal.
# It restarts the perfsonar-testpoint container to load the new certificate by
# calling the Podman REST API over the mounted Unix socket.
#
# Requirements (inside the certbot container):
#   - /run/podman/podman.sock mounted from the host (read-only)
#   - python3 available (present in docker.io/certbot/certbot:latest on Alpine)
#
# The compose file must mount the socket and disable SELinux labeling:
#   volumes:
#     - /run/podman/podman.sock:/run/podman/podman.sock:ro
#   security_opt:
#     - label=disable
#
# Version: 2.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -eu

SOCKET="/run/podman/podman.sock"
TARGET_CONTAINER="perfsonar-testpoint"
STOP_TIMEOUT=30

echo "[INFO] Certbot deploy hook triggered for domains: ${RENEWED_DOMAINS:-unknown}"
echo "[INFO] Restarting container '${TARGET_CONTAINER}' via Podman socket..."

python3 - <<PYEOF
import http.client, socket, sys

class _UnixConn(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost")
        self._path = path
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self._path)

conn = _UnixConn("${SOCKET}")
try:
    conn.request("POST",
                 "/v4.0.0/containers/${TARGET_CONTAINER}/restart?t=${STOP_TIMEOUT}")
    resp = conn.getresponse()
    body = resp.read().decode()
    if resp.status == 204:
        print("[SUCCESS] Container '${TARGET_CONTAINER}' restarted successfully.")
        sys.exit(0)
    else:
        print(f"[ERROR] Podman API returned {resp.status}: {body}", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"[ERROR] Failed to contact Podman socket at ${SOCKET}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
