---
title: "Playbook: Performance Issues"
description: "Diagnostics and fixes for high latency, low bandwidth, or slow test execution."
tags: [troubleshoot, performance, tuning]
---

## Playbook: Performance Issues

!!! info "Status"
    This playbook is a placeholder for the [troubleshooter
    persona](../landing.md). Detailed step-by-step diagnostics coming soon.

## Quick Diagnosis

**When to use this playbook:** Tests run but show high latency, low bandwidth, or slow execution times.

### Step 1: Audit Host Tuning

```bash

# Download and run audit

curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/main/docs/perfsonar/tools_scripts/fasterdata-tuning.sh \
  -o /tmp/fasterdata-tuning.sh
chmod 0755 /tmp/fasterdata-tuning.sh

# Run audit (no changes)

/tmp/fasterdata-tuning.sh audit

# Look for yellow (warnings) and red (critical) items

```

### Step 2: Check NIC Settings

```bash

# View interface statistics

ip -s link show

# Check ring buffers

ethtool -g eth0
ethtool -g eth1

# Check offload settings (should be ON)

ethtool -k eth0 | grep -E 'gro|gso|tso|rx-offload'

# Check MTU (should be 1500 or higher if supported)

ip link show | grep mtu
```

### Step 3: Monitor During Test

```bash

# Watch CPU and memory

watch -n 1 'top -b -n 1 | head -20'

# Monitor network traffic

iftop -i eth0

# Check for packet loss/errors

watch -n 1 'ip -s link show eth0'
```

### Step 4: Identify Bottlenecks

**Is it the testpoint?**

```bash

# Local bandwidth test

iperf3 -s

# (from another host)

iperf3 -c <testpoint_ip>

# Should reach near link speed (1Gbps, 10Gbps, 100Gbps)

```

**Is it the network path?**

```bash

# Traceroute to remote testpoint

traceroute -n <remote_testpoint>

# MTU path discovery

ping -M do -s 1472 <remote_testpoint>

# Check for ECMP load balancing

mtr -r -c 100 <remote_testpoint>
```

**Is it contention?**

```bash

# Check for competing traffic

iftop -i eth0

# Check qdisc

tc qdisc show

# Look at interface queue depth

watch -n 1 'cat /proc/net/dev | head -5'
```

### Step 5: Escalate

If still slow, collect:

- Tuning audit: `/tmp/fasterdata-tuning.sh audit > /tmp/audit.txt`
- NIC stats: `ethtool -i eth0` and `ethtool -g eth0`
- Local iperf results
- Test results from measurement archive
- perfSONAR logs: `podman logs perfsonar-testpoint | tail -100 > /tmp/logs.txt`

Then contact:

- [OSG GOC](https://support.opensciencegrid.org/) (OSG sites)
- [WLCG GGUS](https://ggus.eu/) (WLCG sites)

---

## Common Solutions

### Kernel Buffers Too Small

**Problem:** `fasterdata-tuning.sh audit` shows red for `net.core.rmem_max` or `net.core.wmem_max`

**Solution:**

```bash

# Apply tuning

sudo /tmp/fasterdata-tuning.sh apply

# Reboot to apply qdisc changes

sudo reboot
```

### NIC Ring Buffers Too Small

**Problem:** Packet drops during bandwidth tests

**Solution:**

```bash

# Check current

ethtool -g eth0

# Increase (example for 1Gbps)

sudo ethtool -G eth0 rx 4096 tx 4096

# Verify

ethtool -g eth0

# Make persistent (add to network config or startup script)

```

### MTU Mismatch

**Problem:** Path MTU discovery failing or fragmentation

**Solution:**

```bash

# Check MTU on all hops

ping -M do -s 1472 <remote_testpoint>

# Adjust testpoint MTU if needed

sudo ip link set dev eth0 mtu 9000

# Update interface config for persistence

# (varies by OS/network manager)

```

### Competing Tests

**Problem:** Multiple tests running simultaneously, causing slowdown

**Solution:**

```bash

# Check scheduled tests

pscheduler tasks --host localhost

# View test execution schedule

pscheduler tasks --host localhost --format json

# Space out high-bandwidth tests via pSConfig

# (contact mesh administrators)

```

---

## See Also

- [Host Tuning Guide](../../../host-network-tuning.md)
- [Multiple NIC Setup](../../../perfsonar/multiple-nic-guidance.md)
- [Installation Guide](../../quick-deploy/install-perfsonar-testpoint.md)
- [Troubleshooter Landing](../landing.md)
