# Fasterdata Host & Network Tuning (EL9)

This page documents `fasterdata-tuning.sh`, a script that audits and optionally applies ESnet Fasterdata-inspired host and NIC tuning recommendations for Enterprise Linux 9.

Script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

Purpose
-------
- Audit system settings (sysctl, qdiscs, ethtool, SMT, IOMMU, drivers) against Fasterdata recommendations.
- Apply tuned sysctl settings and persist NIC tunings (via systemd service) when run in `--mode apply`.

Usage
-----
Audit a measurement host (default):

```bash
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
