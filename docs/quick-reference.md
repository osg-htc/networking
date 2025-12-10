---
title: "Quick Reference"
description: "One-page cheat sheet for perfSONAR deployment, troubleshooting, and common commands."
tags: [reference, cheat-sheet, commands]
---

# 🚀 Quick Reference Card

One-page cheat sheet for perfSONAR deployment, configuration, and troubleshooting.

---

## Essential Contacts

| Scenario | Contact | |----------|---------| | **OSG Site Issues** | [GOC
Support](https://support.opensciencegrid.org/) | | **WLCG Issues** | [GGUS Ticket](https://ggus.eu/) → "WLCG perfSONAR
support" | | **perfSONAR Questions** | [User Mailing List](https://lists.internet2.edu/sympa/info/perfsonar-user) | |
**Local Network** | Your site's network administrator |

---

## Deployment Quick Start

### Pre-Deployment Checklist

- [ ] EL9 OS installed (AlmaLinux, Rocky, RHEL)

- [ ] Hostname set: `hostnamectl set-hostname <name>`

- [ ] Time sync enabled: `systemctl enable --now chronyd`

- [ ] Network interfaces documented: `nmcli device status`

- [ ] Required packages: `dnf install -y podman podman-compose git curl dig nft`

### Orchestrated Deploy (Recommended)

```bash
# Download and run
curl -fsSL \
  https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh \
  -o /tmp/perfSONAR-orchestrator.sh
chmod 0755 /tmp/perfSONAR-orchestrator.sh

# Interactive (pauses at each step)
/tmp/perfSONAR-orchestrator.sh

# Non-interactive (auto-confirm all)
/tmp/perfSONAR-orchestrator.sh --non-interactive --option A

# With Let's Encrypt
/tmp/perfSONAR-orchestrator.sh --option B --fqdn <FQDN> --email <EMAIL>
```

### Post-Deploy Validation

```bash
# Verify services running
systemctl status perfsonar-testpoint

# Check container
podman ps | grep perfsonar

# Verify pSConfig enrollment
psconfig remote list

# List scheduled tests
pscheduler tasks --host localhost
```

---

## Required Ports & Firewall

| Port | Protocol | Purpose | Allow From | |------|----------|---------|-----------| | **443** | HTTPS | pScheduler
(required) | All perfSONAR nodes | | 5001 | TCP/UDP | iperf (bandwidth) | Mesh nodes | | 8080 | HTTP | pSConfig config |
All (or 443) | | 9000 | TCP | Logging | Central server |

### Open Firewall (nftables)

```bash
# Add rule to allow 443
sudo nft add rule inet filter input tcp dport 443 accept

# Verify
nft list table filter
```

---

## Common Commands

### Container Management

```bash
# Status
podman ps -a | grep perfsonar
systemctl status perfsonar-testpoint

# View logs
podman logs perfsonar-testpoint
podman logs -f perfsonar-testpoint          # follow

# Restart
systemctl restart perfsonar-testpoint

# Stop/Start
systemctl stop perfsonar-testpoint
systemctl start perfsonar-testpoint
```

### pScheduler & Tests

```bash
# List all tasks
pscheduler tasks --host localhost

# View scheduled tests (JSON format)
pscheduler tasks --host localhost --format json

# Run manual test
pscheduler task add --host <local> --dest <remote> \
  --test-type latencybg

# Check pScheduler status
systemctl status perfsonar-pscheduler-agent
```

### Network Configuration

```bash
# View interfaces
nmcli device status
ip -br addr

# Check routing
ip route show
ip rule show

# View firewall rules
nft list ruleset

# Check listening ports
ss -ltnp | grep -E '(443|5001)'
```

### Host Tuning

```bash
# Download tuning script
curl -fsSL \
  https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh \
  -o /tmp/fasterdata-tuning.sh
chmod 0755 /tmp/fasterdata-tuning.sh

# Audit (no changes)
/tmp/fasterdata-tuning.sh audit

# Apply tuning
sudo /tmp/fasterdata-tuning.sh apply

# For DTN (large buffers)
sudo /tmp/fasterdata-tuning.sh apply --target dtn
```

### LS Registration

```bash
# Update registration
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh update

# Auto-enroll in mesh
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh \
  --fqdn $(hostname -f) \
  --profile latency
```

---

## Troubleshooting Quick Checklist

```bash
# 1. System info
hostnamectl
cat /etc/os-release
uname -a

# 2. Connectivity
ping -c 3 8.8.8.8
ping -c 3 psconfig.opensciencegrid.org

# 3. Container status
podman ps -a
podman logs perfsonar-testpoint | head -50

# 4. Services
systemctl status perfsonar-*
systemctl status podman

# 5. Network
ip -br addr
netstat -ltnp | grep -E '(443|5001|8080)'
nft list ruleset | head -20

# 6. pScheduler
psconfig remote list
pscheduler tasks --host localhost

# 7. DNS
dig psconfig.opensciencegrid.org
nslookup $(hostname -f)

# 8. Firewall test
curl -v https://psconfig.opensciencegrid.org/
nc -zv <remote_testpoint> 443
```

---

## Configuration Files

| File | Purpose | |------|---------| | `/etc/perfsonar/` | Config backups (from legacy toolkit) | | `/opt/perfsonar-
tp/docker-compose.yml` | Container definition | | `/opt/perfsonar-tp/tools_scripts/` | Helper scripts | |
`/etc/NetworkManager/conf.d/` | NIC configuration (if using PBR) | | `/etc/nftables.conf` | Firewall rules | |
`~/.ssh/authorized_keys` | SSH keys |

---

## Log Locations

| Source | Location | |--------|----------| | **Container** | `podman logs perfsonar-testpoint` | | **Systemd** |
`journalctl -u perfsonar-testpoint -f` | | **Host** | `/var/log/messages` (EL9) | | **Kernel** | `dmesg` | |
**Firewall** | `dmesg \| grep -i nft` |

---

## Documentation Links

| Topic | Link | |-------|------| | **Installation** | [Quick Deploy Guide](personas/quick-deploy/landing.md) | |
**Troubleshooting** | [Troubleshooter Guide](personas/troubleshoot/landing.md) | | **Host Tuning** | [Fasterdata Tuning](perfsonar/tools_scripts/fasterdata-tuning.md)
Tuning](host-network-tuning.md) | | **Architecture** | [System Overview](personas/research/landing.md) | | **Tools** |
[Tools & Scripts](perfsonar/tools_scripts/README.md) | | **FAQ** | [perfSONAR FAQ](perfsonar/faq.md) | | **Official
Docs** | [docs.perfsonar.net](https://docs.perfsonar.net/) |

---

## Performance Benchmarks

### Expected Bandwidth

| Link Speed | Expected Throughput | |------------|-------------------| | 1 Gbps | 900+ Mbps | | 10 Gbps | 9+ Gbps | |
100 Gbps | 90+ Gbps |

*Depends on testpoint tuning, network conditions, and competing tests.*

### Normal Latency

- **Local campus network:** < 5 ms

- **Same region:** 10-50 ms

- **Cross-country:** 50-150 ms

- **Transatlantic:** 100-200 ms

---

## Emergency Procedures

### Container Won't Start

```bash
# 1. Check logs
podman logs perfsonar-testpoint

# 2. Verify image
podman images | grep perfsonar

# 3. Free disk space
podman system prune -a

# 4. Restart service
systemctl restart perfsonar-testpoint

# 5. Check ports
ss -ltnp | grep -E '(443|5001)'
```

### Container Lost Network

```bash
# 1. Check network
ip link show
nmcli device status

# 2. Restart network
systemctl restart NetworkManager

# 3. Restart container
systemctl restart perfsonar-testpoint

# 4. Verify routes
ip route show
```

### Tests Not Running

```bash
# 1. Check enrollment
psconfig remote list

# 2. Verify connectivity
curl -v https://psconfig.opensciencegrid.org/

# 3. Check pScheduler
systemctl status perfsonar-pscheduler-agent
pscheduler tasks --host localhost

# 4. Restart all services
systemctl restart perfsonar-testpoint

# 5. Escalate
# Contact: [Troubleshooter Guide](personas/troubleshoot/landing.md)
```

---

## Common Issues & Solutions

| Issue | Quick Fix | |-------|-----------| | Port 443 in use | `ss -ltnp \| grep 443` → kill process | | Volume
permission denied | `sudo chown 65534:65534 /volume/path` | | DNS not resolving | `systemctl restart systemd-resolved` |
| firewall blocking | `sudo nft add rule inet filter input tcp dport 443 accept` | | High latency | Run:
`/tmp/fasterdata-tuning.sh apply` | | Tests scheduled but not running | `pscheduler tasks` → check network connectivity
| | Cannot reach remote testpoint | Check firewall on both ends, verify 443 is open |

---

## Version Information

- **Quick Deploy**: v1.4.0+

- **perfSONAR**: 5.0.3+

- **OS**: EL9 (AlmaLinux, Rocky, RHEL)

- **Container**: Podman/Docker

---

**Last Updated:** December 2025 **For issues:** [troubleshooter landing](personas/troubleshoot/landing.md) or [support
contacts](#essential-contacts)
