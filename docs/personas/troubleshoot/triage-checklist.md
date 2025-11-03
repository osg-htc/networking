---
title: Triage checklist for network issues
description: Short checklist to quickly gather the information needed to troubleshoot network and perfSONAR problems.
persona: troubleshoot
owners: [networking-team@osg-htc.org]
status: draft
tags: [troubleshoot, checklist]
---

## Quick triage checklist

1. Gather host information: hostname, distro, kernel, NICs.
1. Check basic connectivity: ping, traceroute to remote testpoints.
1. Verify perfSONAR services: systemctl status perfsonar-* and web UI.
1. Check firewall/ports (nftables/iptables) and required ports for perfSONAR.
1. Collect logs and measurement samples for sharing with support.

Use relevant playbooks in `playbooks/` for specific scenarios.
