---
title: "Playbook: Firewall & Network Access Issues"
description: "Diagnostics for firewall blocking, port access, and network connectivity problems."
tags: [troubleshoot, firewall, networking, nftables]
---

## Playbook: Firewall & Network Access Issues

!!! info "Status" This playbook is a placeholder for the [troubleshooter persona](../landing.md). Detailed step-by-step
diagnostics coming soon.

## Quick Diagnosis

**When to use this playbook:** Tests fail to execute, firewall errors in logs, or remote testpoints can't connect.

### Step 1: Check Required Ports

```bash

# perfSONAR required ports

PORTS="443 5001 8080 9000"

# Check if listening

ss -ltnp | grep -E '(443|5001|8080|9000)'

# Test remote connectivity

for port in $PORTS; do nc -zv <remote_testpoint> $port done
```

Expected results:

- **443** (pScheduler) — REQUIRED, must be open

- **5001** (iperf) — bandwidth tests only

- **8080** (pSConfig) — configuration/discovery

- **9000** (logging) — optional

### Step 2: Check Local Firewall

```bash

# List current rules

nft list ruleset

# Check filter table specifically

nft list table filter

# Look for DROP/REJECT rules on required ports

nft list table filter | grep -E '(443|5001|8080|9000|DROP|REJECT)'
```

### Step 3: Test Connectivity to Remote

```bash

# DNS resolution

dig +short <remote_testpoint_hostname> nslookup <remote_testpoint_hostname>

# Basic ping

ping -c 3 <remote_testpoint_ip>

# Traceroute to identify hops

traceroute -n <remote_testpoint_ip>

# Test port connectivity

curl -v <https://<remote_testpoint_hostname>>:443/

# Test from remote back (may need to ask admin)

ssh <remote_admin> "curl -v <https://<YOUR_TESTPOINT>>:443/"
```

### Step 4: Check Campus/Upstream Firewall

```bash

# Ask your network team to check for:

# 1. Outbound HTTPS (443) to perfSONAR hosts

# 2. Inbound HTTPS (443) from perfSONAR hosts

# 3. Outbound ephemeral ports (5000-6000 range)

# 4. Inbound from trusted perfSONAR subnets

# Provide them:

- Your testpoint IP

- Remote testpoint IPs you need to reach

- Required ports (443 primary, 5001/8080 secondary)

```

### Step 5: Review Container & Host Logs

```bash

# Container firewall errors

podman logs perfsonar-testpoint | grep -i "firewall\|iptables\|nftables\|refused\|unreachable"

# System logs

journalctl -n 100 | grep -i "firewall\|dropped\|rejected"

# nftables audit logs (if enabled)

dmesg | grep -i nft
```

### Step 6: Escalate

If still blocked, collect:

- Firewall rules: `nft list ruleset > /tmp/firewall.txt`

- Listening ports: `ss -ltnp > /tmp/ports.txt`

- Test connectivity results

- Container logs: `podman logs perfsonar-testpoint > /tmp/logs.txt`

- Traceroute output: `traceroute -n <remote> > /tmp/traceroute.txt`

Then contact:

- **Local network team** — for campus firewall checks

- [OSG GOC](https://support.opensciencegrid.org/) (OSG sites)

- [WLCG GGUS](https://ggus.eu/) (WLCG sites)

---

## Common Solutions

### Port Not Open on Testpoint

**Problem:** `ss -ltnp | grep 443` shows nothing

**Solution:**

```bash

# Restart container

systemctl restart perfsonar-testpoint

# Verify it started

systemctl status perfsonar-testpoint

# Check logs

podman logs perfsonar-testpoint | tail -20
```

### Local Firewall Blocking (nftables)

**Problem:** `nft list ruleset` shows DROP/REJECT on 443

**Solution:**

```bash

# View current rules

nft list ruleset

# Check if rule exists

nft list table filter | grep "dport 443"

# If missing, add rule (before DROP rule)

sudo nft add rule inet filter input tcp dport 443 accept

# Verify

nft list table filter

# Make persistent (varies by host setup)

# Usually in /etc/nftables.conf or similar

```

### Campus Firewall Blocking

**Problem:** Can ping remote, but can't reach port 443

**Solution:**

1. **Contact your campus network team** with:

- Your testpoint IP address

- List of remote perfSONAR testpoints you need to reach

- Required ports: 443 (primary), 5001/8080 (secondary)

1. **Provide them:** OSG/WLCG mesh documentation

- List available at: `psconfig.opensciencegrid.org`

1. **Verify after firewall changes:**

```bash curl -v https://<remote_testpoint>:443/ pscheduler tasks --host localhost
``` text

### DNS Resolution Failing

**Problem:** `nslookup <remote_testpoint>` fails

**Solution:**

```

# Check local resolver

cat /etc/resolv.conf

# Test with Google's DNS

ping 8.8.8.8 dig @8.8.8.8 <remote_testpoint_hostname>

# Verify DNS server is reachable

nc -zv <dns_server> 53

```text

---

## Reference: Required Ports

| Port | Protocol | Purpose | Required | |------|----------|---------|----------| | 443 | HTTPS | pScheduler (test
scheduling) | **YES** | | 5001 | TCP/UDP | iperf (bandwidth tests) | No (bandwidth only) | | 8080 | HTTP | pSConfig
(configuration) | No (can use 443) | | 9000 | TCP | Logging (optional) | No |

---

## See Also

- [Security & Firewall Guide](../../../perfsonar/installation.md#security-considerations)

- [Network Troubleshooting Guide](../../../network-troubleshooting.md)

- [Troubleshooter Landing](../landing.md)

- [Quick Triage Checklist](../triage-checklist.md)
