#!/bin/sh
# certbot-deploy-hook.sh
# This script is executed by Certbot's --deploy-hook after a successful renewal.
# It makes Apache in the perfsonar-testpoint container load the new
# certificate, by calling the Podman REST API over the mounted Unix socket.
#
# By default it reloads Apache inside the running container (exec
# "systemctl reload apache2", falling back to "apachectl graceful"). Only if
# both fail does it restart the whole container, as versions before 2.1.0 did.
# A reload does not interrupt pScheduler, and it does not fight systemd: on
# hosts where perfsonar-testpoint.service runs the container, an API restart
# makes the unit's 'podman run' exit, so systemd removes the container and
# starts it again after RestartSec (and, with Requires=, stops certbot too).
#
# Requirements (inside the certbot container):
#   - /run/podman/podman.sock mounted from the host (read-only), and the host's
#     podman.socket enabled (systemctl enable --now podman.socket)
#   - python3 available (present in docker.io/certbot/certbot:latest on Alpine)
#   - SELinux label confinement disabled for the certbot container, so it may
#     execute this bind-mounted script and connect to the socket:
#       compose:  security_opt: [label=disable]
#       systemd:  podman run --security-opt label=disable ... (written by
#                 install-systemd-units.sh >= 1.6.0)
#
# Environment overrides (mainly for testing):
#   PODMAN_SOCKET       default /run/podman/podman.sock
#   TARGET_CONTAINER    default perfsonar-testpoint
#   RELOAD_COMMANDS     ';'-separated commands tried in order inside the
#                       container; default "systemctl reload apache2;apachectl graceful"
#   RESTART_FALLBACK    1 (default) to restart the container if no reload works
#
# Version: 2.1.0 - 2026-10-09
#   - Reload Apache inside the container instead of restarting the container;
#     restart only as a fallback.
# Version: 2.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -eu

export PODMAN_SOCKET="${PODMAN_SOCKET:-/run/podman/podman.sock}"
export TARGET_CONTAINER="${TARGET_CONTAINER:-perfsonar-testpoint}"
export RELOAD_COMMANDS="${RELOAD_COMMANDS:-systemctl reload apache2;apachectl graceful}"
export RESTART_FALLBACK="${RESTART_FALLBACK:-1}"
STOP_TIMEOUT=30
export STOP_TIMEOUT

echo "[INFO] Certbot deploy hook triggered for domains: ${RENEWED_DOMAINS:-unknown}"

python3 - <<'PYEOF'
import http.client, json, os, socket, sys, time

SOCKET = os.environ["PODMAN_SOCKET"]
TARGET = os.environ["TARGET_CONTAINER"]
RELOADS = [c.split() for c in os.environ["RELOAD_COMMANDS"].split(";") if c.strip()]
FALLBACK = os.environ.get("RESTART_FALLBACK", "1") == "1"
STOP_TIMEOUT = os.environ.get("STOP_TIMEOUT", "30")
API = "/v4.0.0"


class _UnixConn(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=60)
        self._path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(60)
        self.sock.connect(self._path)


def call(method, path, body=None):
    conn = _UnixConn(SOCKET)
    try:
        data = json.dumps(body) if body is not None else None
        headers = {"Content-Type": "application/json"} if data is not None else {}
        conn.request(method, API + path, body=data, headers=headers)
        resp = conn.getresponse()
        return resp.status, resp.read().decode(errors="replace")
    finally:
        conn.close()


def exec_in_container(cmd):
    """Run cmd in TARGET; return its exit code (or None if the API failed)."""
    status, body = call("POST", f"/containers/{TARGET}/exec",
                        {"Cmd": cmd, "AttachStdout": False, "AttachStderr": False})
    if status != 201:
        print(f"[WARN] exec create '{' '.join(cmd)}' failed: HTTP {status}: {body.strip()}")
        return None
    exec_id = json.loads(body)["Id"]
    status, body = call("POST", f"/exec/{exec_id}/start", {"Detach": True, "Tty": False})
    if status not in (200, 204):
        print(f"[WARN] exec start '{' '.join(cmd)}' failed: HTTP {status}: {body.strip()}")
        return None
    for _ in range(120):
        status, body = call("GET", f"/exec/{exec_id}/json")
        if status == 200:
            info = json.loads(body)
            if not info.get("Running", False):
                return info.get("ExitCode")
        time.sleep(0.5)
    print(f"[WARN] '{' '.join(cmd)}' did not finish within 60s")
    return None


try:
    for cmd in RELOADS:
        print(f"[INFO] Reloading Apache in '{TARGET}': {' '.join(cmd)}")
        rc = exec_in_container(cmd)
        if rc == 0:
            print(f"[SUCCESS] Apache in '{TARGET}' reloaded; the new certificate is in use.")
            sys.exit(0)
        if rc is not None:
            print(f"[WARN] '{' '.join(cmd)}' exited with {rc}")

    if not FALLBACK:
        print("[ERROR] Could not reload Apache and the restart fallback is disabled.", file=sys.stderr)
        sys.exit(1)

    print(f"[WARN] Reload failed; restarting container '{TARGET}' instead...")
    status, body = call("POST", f"/containers/{TARGET}/restart?t={STOP_TIMEOUT}")
    if status == 204:
        print(f"[SUCCESS] Container '{TARGET}' restarted.")
        sys.exit(0)
    print(f"[ERROR] Podman API returned {status}: {body.strip()}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"[ERROR] Failed to use the Podman socket at {SOCKET}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
