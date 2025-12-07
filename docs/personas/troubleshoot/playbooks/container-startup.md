---
title: "Playbook: Container Won't Start"
description: "Step-by-step diagnostics for perfSONAR container startup failures."
tags: [troubleshoot, container, docker, podman]
---

## Playbook: Container Won't Start

!!! info "Status" This playbook is a placeholder for the [troubleshooter persona](../landing.md). Detailed step-by-step
diagnostics coming soon.

## Quick Diagnosis

**When to use this playbook:** The perfSONAR container fails to start or immediately exits.

### Step 1: Check Container Status

```bash

# For Podman

podman ps -a | grep perfsonar

# For Docker

docker ps -a | grep perfsonar
```

Look for:

- Exit code (non-zero = failure)

- Last restart time

- Error messages

### Step 2: View Container Logs

```bash

# For Podman

podman logs perfsonar-testpoint

# For Docker

docker logs perfsonar-testpoint
```

Common errors:

- `OCI runtime error` — host kernel/runtime issue

- `Failed to bind port` — port already in use

- `No such file or directory` — missing volume/mount

- `permission denied` — volume permission issue

### Step 3: Check Prerequisites

- **Image available:** `podman images | grep perfsonar`

- **Volumes exist:** `podman volume ls | grep perfsonar`

- **Ports available:** `ss -ltnp | grep -E '(443|5001|9000|8080)'`

- **Disk space:** `df -h /var/lib/podman` or `/var/lib/docker`

### Step 4: Escalate

If the above doesn't resolve the issue, collect:

- Container logs: `podman logs perfsonar-testpoint > /tmp/logs.txt`

- Systemd logs: `journalctl -u perfsonar-testpoint -n 50 > /tmp/systemd.txt`

- Host info: `uname -a`, `cat /etc/os-release`

Then contact:

- [OSG GOC](https://support.opensciencegrid.org/) (OSG sites)

- [WLCG GGUS](https://ggus.eu/) (WLCG sites)

- [perfSONAR Mailing List](https://lists.internet2.edu/sympa/info/perfsonar-user)

---

## Common Solutions

### Port Already in Use

**Problem:** Container fails with "Address already in use"

**Solution:**

```bash

# Find what's using the port (e.g., 443)

ss -ltnp | grep 443

# Kill the process or change container port mapping

podman stop conflicting-container
podman rm conflicting-container
```

### Volume Permission Denied

**Problem:** Container fails with "permission denied" on volume

**Solution:**

```bash

# Check volume ownership

ls -la /var/lib/podman/volumes/perfsonar_data/

# Fix permissions (adjust UID/GID as needed)

sudo chown -R 65534:65534 /path/to/volume
```

### Out of Disk Space

**Problem:** Container fails with "no space left"

**Solution:**

```bash

# Check disk usage

df -h

# Clean old images/containers

podman system prune -a

# Or increase disk allocation

# (varies by host setup)

```

---

## See Also

- [Installation Guide](../../quick-deploy/install-perfsonar-testpoint.md)

- [Troubleshooter Landing](../landing.md)

- [Quick Triage Checklist](../triage-checklist.md)
