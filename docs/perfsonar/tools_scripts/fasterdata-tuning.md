# Fasterdata Host & Network Tuning (EL9)

This page documents `fasterdata-tuning.sh`, a script that audits and optionally applies ESnet Fasterdata-inspired host and NIC tuning recommendations for Enterprise Linux 9.

Script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

Purpose
-------
 
Download & Install
------------------
You can download the script directly from the website or GitHub raw URL and install it locally for repeated use:

```bash
# Download via curl to a system location and make it executable
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh

# Or download directly from the site (if published):
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

Why use this script?
---------------------
This script packages ESnet Fasterdata best practices into an audit/apply helper that:

- Provides a non-invasive audit mode to compare current host settings against Fasterdata recommendations tailored by NIC speed and host role (measurement vs DTN).
- Centralizes recommended sysctl tuning for high-throughput, long-distance transfers (buffer sizing, qdisc, congestion control), reducing guesswork and manual errors.
- Applies and persists sysctl settings in `/etc/sysctl.d/90-fasterdata.conf` and helps persist per-NIC settings (ethtool) via a `systemd` oneshot service; it also checks for problematic driver versions and provides vendor-specific guidance.

Who should use it?
------------------
- perfSONAR testpoints, dedicated DTNs and other throughput-focused hosts on EL9 where you control the host configuration.
- NOT for multi-tenant or general-purpose interactive servers without prior review — these sysctl changes can affect other services.

Verification & Basic checks
--------------------------
After running the script (audit or apply), verify key settings:

```bash
# Sysctl
sysctl net.core.rmem_max net.core.wmem_max net.core.netdev_max_backlog net.core.default_qdisc
# Tuned active profile
tuned-adm active || echo "tuned-adm not present"
# Per NIC checks
ethtool -k <iface> # offload features
ethtool -g <iface> # ring buffer sizes
tc qdisc show dev <iface>
# Verify IOMMU in kernel cmdline
cat /proc/cmdline | grep -E "iommu=pt|intel_iommu=on|amd_iommu=on"
```

Security & Safety
-----------------
- Always test in a staging environment first. Use `--mode audit` to review before applying.
- The `iommu` and `SMT` settings are environment-sensitive: IOMMU changes require GRUB kernel cmdline edits and a reboot. The script only suggests GRUB edits and does not automatically change the bootloader.
- If you require automated GRUB edits or SMT toggles, those should be opt-in with thorough confirmation prompts and recovery steps.

Usage
-----
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement
```

Apply tuning (requires root):

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn
```

Limit apply to specific NICs (comma-separated):

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target measurement --ifaces "ens1f0np0,ens1f1np1"
```

Notes
-----
- IOMMU: The script checks whether `iommu=pt` plus vendor-specific flags (`intel_iommu=on` or `amd_iommu=on`) are present. It only recommends GRUB edits (requires reboot) — it does not modify GRUB automatically unless you explicitly opt-in via a future apply flag.
- SMT: The script detects SMT status and suggests commands to toggle runtime SMT; persistence requires GRUB edits (kernel cmdline). It does not toggle SMT by default.
- Apply mode writes `/etc/sysctl.d/90-fasterdata.conf` and creates `/etc/systemd/system/ethtool-persist.service` when necessary.

Reference and source
--------------------
- Source script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`
- Fasterdata docs: https://fasterdata.es.net/host-tuning/

If you use this script as part of a host onboarding flow, ensure you test it in a VM or staging host before applying to production hosts.
