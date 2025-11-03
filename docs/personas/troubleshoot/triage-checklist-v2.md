---
title: "Triage checklist (minimal)"
description: "Short checklist to quickly gather the information needed to troubleshoot network and perfSONAR problems."
persona: troubleshoot
owners: ["networking-team@osg-htc.org"]
status: draft
tags: [troubleshoot, checklist]
---

## Quick triage checklist

1. Gather host information

```bash
hostnamectl
cat /etc/os-release
uname -a
ip -c a
```

2. Check basic connectivity

```bash
ping -c 4 <remote-ip-or-host>
traceroute -n <remote-ip-or-host>
```

3. Verify perfSONAR services and containers

```bash
systemctl status perfsonar-*
ps aux | grep perfsonar
sudo podman ps || sudo docker ps
```

4. Check firewall and ports

```bash
sudo nft list ruleset
sudo ss -ltnp
```

5. Collect logs and measurements

- Container logs: `sudo podman logs perfsonar-testpoint`
- perfSONAR checks: `pscheduler tasks --host localhost`

Use the scenario playbooks in `playbooks/` for step-by-step remediation instructions.
