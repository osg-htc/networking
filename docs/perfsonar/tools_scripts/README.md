# perfSONAR Tools & Scripts

This directory contains helper scripts for perfSONAR deployment, configuration, and tuning.

## Available Tools

| Tool | Purpose | Documentation |
|------|---------|---------------|
| **fasterdata-tuning.sh** | Host & NIC tuning (ESnet Fasterdata) | [Fasterdata Tuning Guide](fasterdata-tuning.md) |
| **perfSONAR-pbr-nm.sh** | Multi-NIC policy-based routing | [Multiple NIC Guidance](../multiple-nic-guidance.md) |
| **perfSONAR-update-lsregistration.sh** | LS registration management | [LS Registration Tools](README-lsregistration.md) |
| **perfSONAR-auto-enroll-psconfig.sh** | Automatic pSConfig enrollment | [Installation Guides](../../personas/quick-deploy/landing.md) |
| **install_tools_scripts.sh** | Bulk installer for all scripts | [Installation](#installation) |
| **install-systemd-service.sh** | Container auto-start on boot | [Container Management](#container-management) |

---

## Quick Start

### Download All Scripts

Install all scripts to a target directory (default: `/opt/perfsonar-tp/tools_scripts`):

```bash
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh | sudo bash -s -- /opt/perfsonar-tp
```

### Download Individual Scripts

```bash
# Example: fasterdata-tuning.sh
sudo curl -fsSL -o /usr/local/bin/fasterdata-tuning.sh \
  https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

---

## Host Tuning

### Fasterdata Tuning Script

Audit and apply ESnet Fasterdata-inspired host and NIC tuning for EL9 systems.

**Quick Usage:**

```bash
# Audit mode (no changes)
/usr/local/bin/fasterdata-tuning.sh --mode audit --target measurement

# Apply tuning (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target dtn
```

**Full Documentation:** [Fasterdata Tuning Guide](fasterdata-tuning.md)

**Download:**
```bash
# Direct download
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh \
  -o /tmp/fasterdata-tuning.sh

# Or from the published site
curl -fsSL https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-tuning.sh \
  -o /tmp/fasterdata-tuning.sh
```

---

## Multi-NIC Configuration

### Policy-Based Routing (PBR)

Configure static IPv4/IPv6 addressing and per-NIC source-based routing via NetworkManager.

**Script:** `perfSONAR-pbr-nm.sh`

**Config file:** `/etc/perfSONAR-multi-nic-config.conf`

**Log file:** `/var/log/perfSONAR-multi-nic-config.log`

**Quick Usage:**

```bash
# Generate config automatically
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto

# Preview changes (dry-run)
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --dry-run --debug

# Apply configuration
sudo /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes
```

**Full Documentation:** [Multiple NIC Guidance](../multiple-nic-guidance.md)

---

## LS Registration

### Lookup Service Registration Tools

Manage perfSONAR Lookup Service registration configuration.

**Script:** `perfSONAR-update-lsregistration.sh`

**Quick Usage:**

```bash
# For RPM Toolkit (local mode)
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh update --local \
  --site-name "My Site" --admin-email admin@example.org

# For container-based testpoint
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh update \
  --container perfsonar-testpoint \
  --site-name "My Site" --admin-email admin@example.org
```

**Full Documentation:** [LS Registration Tools](README-lsregistration.md)

---

## Auto-Enrollment

### pSConfig Auto-Enrollment

Automatically enroll perfSONAR instances in OSG/WLCG pSConfig meshes by deriving FQDNs from configured IPs.

**Script:** `perfSONAR-auto-enroll-psconfig.sh`

**Quick Usage:**

```bash
# For RPM Toolkit (local mode)
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-auto-enroll-psconfig.sh --local -v

# For container-based testpoint
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -v
```

**Full Documentation:** See [Testpoint Installation](../../personas/quick-deploy/install-perfsonar-testpoint.md) or [Toolkit Installation](../../personas/quick-deploy/install-perfsonar-toolkit.md)

---

## Installation

### Bulk Script Installer

Install all helper scripts to a target directory.

**Script:** `install_tools_scripts.sh`

**Usage:**

```bash
# Preview (dry-run)
bash /opt/perfsonar-tp/tools_scripts/install_tools_scripts.sh --dry-run

# Install to default location (/opt/perfsonar-tp/tools_scripts)
bash /opt/perfsonar-tp/tools_scripts/install_tools_scripts.sh

# Install to custom location
bash /opt/perfsonar-tp/tools_scripts/install_tools_scripts.sh /custom/path
```

**Options:**
- `--dry-run`: Preview changes without modifying files
- `--skip-testpoint`: Skip cloning testpoint repo if already present

---

## Container Management

### Systemd Service for Container Auto-Start

Install and enable a systemd service for automatic container restart on boot.

**Script:** `install-systemd-service.sh`

**Usage:**

```bash
# Install with default path (/opt/perfsonar-tp)
sudo /opt/perfsonar-tp/tools_scripts/install-systemd-service.sh

# Install with custom path
sudo /opt/perfsonar-tp/tools_scripts/install-systemd-service.sh /custom/path
```

**Service Management:**

```bash
# Start/stop/restart containers
systemctl start perfsonar-testpoint
systemctl stop perfsonar-testpoint
systemctl restart perfsonar-testpoint

# View status and logs
systemctl status perfsonar-testpoint
journalctl -u perfsonar-testpoint -f
```

**Integration:**

After deploying containers with `podman-compose up -d`, install the service to ensure containers start automatically on boot.

---

## Dependencies

Essential packages (install before using these scripts):

```bash
# RHEL/AlmaLinux/Rocky Linux
dnf install -y bash coreutils iproute NetworkManager rsync curl openssl \
  nftables podman podman-compose fail2ban policycoreutils python3

# Debian/Ubuntu
apt-get install -y bash coreutils iproute2 network-manager rsync curl openssl \
  nftables podman podman-compose docker.io fail2ban policycoreutils python3
```

---

## Support & Additional Resources

- **Installation Guides:** [Quick Deploy Landing](../../personas/quick-deploy/landing.md)
- **Troubleshooting:** [Troubleshooter Guide](../../personas/troubleshoot/landing.md)
- **Network Issues:** [Network Troubleshooting Guide](../../network-troubleshooting.md)
- **perfSONAR FAQ:** [FAQ](../faq.md)
- **Community Support:** [perfSONAR User Mailing List](https://lists.internet2.edu/sympa/info/perfsonar-user)

---

## Contact

**Script Author:** Shawn McKee — [smckee@umich.edu](mailto:smckee@umich.edu)

**OSG Networking Team:** [networking-team@osg-htc.org](mailto:networking-team@osg-htc.org)
