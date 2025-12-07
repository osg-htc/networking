
---
title: "Troubleshooter — Diagnose & Fix Network Issues"
description: "Triage checklist, diagnostics, and playbooks for network troubleshooting in OSG/WLCG."
persona: troubleshoot
owners: ["networking-team@osg-htc.org"]
status: active
tags: [troubleshoot, playbook, diagnostics]
---

# 🔧 Troubleshooter — Diagnose & Fix Network Issues

Systematic approach to identifying and resolving network and perfSONAR problems.

---

## Quick Start (5 Minutes)

### Is it a Network Problem?

1. **Gather facts:** Run the **[Quick Triage Checklist](triage-checklist.md)** —
   collects system info, connectivity, services, logs
2. **Basic diagnostics:** Follow **[Network Troubleshooting Guide](
   ../../network-troubleshooting.md)** — contact procedures, support escalation
3. **Learn more:** **[ESnet Troubleshooting Guide](
   https://fasterdata.es.net/performance-testing/troubleshooting/)** — detailed
   network investigation

### Is it a perfSONAR Problem?

- **[perfSONAR FAQ](../../perfsonar/faq.md)** — quick answers to common issues
- **[OSG Debugging Guide](../../network-troubleshooting/osg-debugging-document.md)** — investigation steps
- **[perfSONAR Official Docs](https://docs.perfsonar.net/troubleshooting_overview.html)** — comprehensive reference

---

## Diagnostic Tools & Guides

### On the perfSONAR Host

**Check system status:**
- Systemd services: `systemctl status perfsonar-*`
- Container status: `podman ps -a` or `docker ps -a`
- Container logs: `podman logs perfsonar-testpoint` or `docker logs`

**Verify network configuration:**
- **[Triage Checklist](triage-checklist.md)** — step-by-step verification
- **[Multiple NIC Setup](../../perfsonar/multiple-nic-guidance.md)** — for multi-interface issues
- **[Host Tuning](../../host-network-tuning.md)** — audit kernel and NIC settings

**Check firewall & security:**
- **[Security & Firewall Guide](../../perfsonar/installation.md#security-considerations)** — required ports and rules
- nftables rules: `nft list ruleset`
- Port status: `ss -ltnp`

### Network Path Analysis

**ESnet tools:** [ESnet Troubleshooting Guide](https://fasterdata.es.net/performance-testing/troubleshooting/)

**perfSONAR tools:**
- pScheduler: [pScheduler documentation](https://docs.perfsonar.net/pscheduler_intro.html)
- Test API: Query test meshes and historical results
- Measurement archive: Access stored results via web interface

---

## Common Scenarios & Playbooks

### Container Won't Start
**Playbook:** [Container Startup Issues](playbooks/container-startup.md) *(in progress)*

Quick checks:
- Image available: `podman images | grep perfsonar`
- Volumes mounted: `podman volume ls`
- Ports available: `ss -ltnp | grep -E '(443|5001|9000|8080)'`
- Logs: `podman logs perfsonar-testpoint`

### Tests Not Running
**Playbook:** [Tests Not Running](playbooks/tests-not-running.md) *(in progress)*

Quick checks:
- pSConfig enrolled: `psconfig remote list`
- Mesh connectivity: Can reach `psconfig.opensciencegrid.org`?
- pScheduler agent: `systemctl status perfsonar-pscheduler-agent`
- Log errors: `podman logs perfsonar-testpoint | grep -i error`

### High Latency / Slow Tests
**Playbook:** [Performance Issues](playbooks/performance-issues.md) *(in progress)*

Quick checks:
- Host tuning: Run `fasterdata-tuning.sh` audit mode
- NIC settings: Check MTU, GRO, GSO, ring buffers
- Network load: Peak bandwidth during test time?
- Competing tests: Multiple tests running simultaneously?

### Firewall Blocking Tests
**Playbook:** [Firewall & Network Access](playbooks/firewall-issues.md) *(in progress)*

Quick checks:
- Required ports: [Security & Firewall Guide](../../perfsonar/installation.md#security-considerations)
- Test connectivity: Can reach remote perfSONAR instances?
- Firewall logs: Check local and campus firewall rules
- DNS resolution: Can resolve perfSONAR hosts?

---

## Escalation & Support

**When to contact support:**

### Level 1: Self-Service Diagnostics
- Run [Triage Checklist](triage-checklist.md)
- Consult [perfSONAR FAQ](../../perfsonar/faq.md)
- Review [OSG Debugging Document](../../network-troubleshooting/osg-debugging-document.md)
- Search [perfSONAR Mailing List Archives](https://lists.internet2.edu/sympa/info/perfsonar-user)

### Level 2: Site-Specific Support
- Contact your **site's network administrator**
- Check local firewall, VLAN, NIC configuration
- Verify DNS, IP routing, upstream connectivity

### Level 3: OSG/WLCG Support
- **OSG sites:** [GOC Support Ticket](https://support.opensciencegrid.org/support/home)
  - Include: hostname, triage checklist results, error messages, logs
- **WLCG sites:** [GGUS Ticket](https://ggus.eu/) → "WLCG Network Throughput" or "WLCG perfSONAR support"

### Level 4: perfSONAR Community
- **[perfSONAR Community](https://lists.internet2.edu/sympa/info/perfsonar-user)** — active support
- **[perfSONAR Documentation](https://docs.perfsonar.net/)** — comprehensive reference
- **[GitHub Issues](https://github.com/perfsonar/perfsonar/issues)** — report bugs

---

## Related Resources

### Setup & Installation
- **[Quick Deploy Guide](../quick-deploy/landing.md)** — initial installation help
- **[Installation Guide](../../perfsonar/installation.md)** — detailed setup steps
- **[Deployment Models](../../perfsonar/deployment-models.md)** — choosing the right setup

### Configuration & Optimization
- **[Host Tuning](../../host-network-tuning.md)** — performance optimization
- **[Multiple NIC Setup](../../perfsonar/multiple-nic-guidance.md)** — multi-interface configuration
- **[Security Features](../../features/)** — fail2ban, nftables, SELinux

### Understanding the System
- **[perfSONAR in OSG/WLCG](../../perfsonar-in-osg.md)** — why perfSONAR matters
- **[Architecture Overview](../research/landing.md)** — system design and data flow
