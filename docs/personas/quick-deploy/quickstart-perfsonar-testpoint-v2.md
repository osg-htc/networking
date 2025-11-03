---
title: "Quickstart: perfSONAR Testpoint (Minimal)"
description: "Minimal set of commands and verification to deploy a perfSONAR testpoint for WLCG/OSG."
persona: quick-deploy
owners: ["networking-team@osg-htc.org"]
status: draft
tags: [quickstart, perfSONAR]
---

## Quickstart (minimal)

Prerequisites

- A clean EL8/EL9 host with root access and network connectivity.
- Sufficient disk and memory for the testpoint container(s).

1. Update the host and install required packages (example for EL9):

```bash
sudo dnf update -y
sudo dnf install -y git podman podman-compose nftables iproute
```

2. Clone the perfSONAR testpoint container compose repository:

```bash
git clone https://github.com/perfsonar/perfsonar-testpoint-docker.git
cd perfsonar-testpoint-docker
```

3. Prepare configuration storage and edit compose if needed:

```bash
sudo mkdir -p /opt/testpoint/
sudo cp -r compose/psconfig /opt/testpoint/
# Edit docker-compose.systemd.yml if you need to change resources or volumes
```

4. Pull and launch the container in host network mode (recommended for accurate timing):

```bash
sudo podman-compose -f docker-compose.systemd.yml pull
sudo podman-compose -f docker-compose.systemd.yml up -d
```

If you use Docker, replace the podman-compose commands with the Docker Compose equivalents.

5. Verify the testpoint is running and reachable:

```bash
sudo podman ps
curl -sSf http://localhost/ | head -n 5
```

6. Basic smoke checks

- Confirm pscheduler tasks: `pscheduler tasks --host localhost`
- Check container logs if problems: `sudo podman logs perfsonar-testpoint`

Optional: register remotes or configure archives using `psconfig` inside the container.

References

- https://github.com/perfsonar/perfsonar-testpoint-docker
- https://docs.perfsonar.net/
