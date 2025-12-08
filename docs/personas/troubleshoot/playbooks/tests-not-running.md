---
title: "Playbook: Tests Not Running"
description: "Diagnostics for perfSONAR tests that don't execute or produce results."
tags: [troubleshoot, pscheduler, psconfig, tests]
---

## Playbook: Tests Not Running

!!! info "Status" This playbook is a placeholder for the [troubleshooter persona](../landing.md). Detailed step-by-step
diagnostics coming soon.

## Quick Diagnosis

**When to use this playbook:** Tests configured in pSConfig don't execute, or no results appear in the measurement
archive.

### Step 1: Verify pSConfig Enrollment

<!-- markdownlint-disable MD034 -->
```bash

# Check if enrolled in meshes

psconfig remote list

# Expected output: should show OSG/WLCG mesh URLs

# Example:

# https://psconfig.opensciencegrid.org/pub/auto/<YOUR_HOSTNAME>

<!-- markdownlint-enable MD034 -->
```

If empty or missing:

- Testpoint not enrolled in mesh

- Run: `/opt/perfsonar-tp/tools_scripts/

perfSONAR-auto-enroll-psconfig.sh`

### Step 2: Check pScheduler Status

```bash

# View scheduled tests

pscheduler tasks --host localhost

# Check agent is running

systemctl status perfsonar-pscheduler-agent

# View agent logs

podman logs perfsonar-testpoint | grep -i scheduler
```

### Step 3: Verify Network Connectivity

<!-- markdownlint-disable MD034 -->
```bash

# Can reach pSConfig server?

ping psconfig.opensciencegrid.org curl -I https://psconfig.opensciencegrid.org/pub/auto

# Can reach remote perfSONAR instances?

ping <remote_testpoint_hostname> telnet <remote_testpoint_hostname> 443
<!-- markdownlint-enable MD034 -->
```

### Step 4: Check Firewall & Ports

```bash

# Verify required ports are open

ss -ltnp | grep -E '(443|5001|8080|9000)'

# Check firewall rules

nft list ruleset | grep -E '(443|5001)'

# Can connect to remote port 443?

nc -zv <remote_testpoint_hostname> 443
```

### Step 5: Review Container Logs

```bash

# Look for pscheduler errors

podman logs perfsonar-testpoint | grep -i error | tail -20

# Look for HTTP errors

podman logs perfsonar-testpoint | grep -i "http\|connection\|refused"
```

### Step 6: Escalate

If still not running, collect:

- pSConfig status: `psconfig remote list`

- pScheduler tasks: `pscheduler tasks --host localhost > /tmp/tasks.txt`

- Container logs: `podman logs perfsonar-testpoint > /tmp/logs.txt`

- Firewall rules: `nft list ruleset > /tmp/firewall.txt`

Then contact:

- [OSG GOC](https://support.opensciencegrid.org/) (OSG sites)

- [WLCG GGUS](https://ggus.eu/) (WLCG sites)

- [perfSONAR Mailing List](https://lists.internet2.edu/sympa/info/perfsonar-user)

---

## Common Solutions

### Not Enrolled in Mesh

**Problem:** `psconfig remote list` is empty

**Solution:**

```bash

# Enroll automatically

/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh \ --fqdn <YOUR_HOSTNAME> \ --profile latency

# Verify enrollment

psconfig remote list pscheduler tasks --host localhost
```

### Firewall Blocking Remote Tests

**Problem:** Tests fail to connect to remote testpoints

**Solution:**

```bash

# Test connectivity

curl -v <https://<remote_testpoint>>:443/

# Check if 443 is open

nft add rule inet filter input tcp dport 443 accept

# Or add to firewall rules permanently

# (varies by site configuration)

```

### Wrong FQDN in pSConfig

**Problem:** Hostname mismatch between pSConfig and local config

**Solution:**

```bash

# Check local FQDN

hostname -f

# Re-enroll with correct hostname

/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh \ --fqdn $(hostname -f) \ --profile latency
```

---

## See Also

- [Installation Guide](../../quick-deploy/install-perfsonar-testpoint.md)

- [pSConfig Documentation](https://docs.perfsonar.net/psconfig_intro.html)

- [Troubleshooter Landing](../landing.md)

- [Quick Triage Checklist](../triage-checklist.md)
