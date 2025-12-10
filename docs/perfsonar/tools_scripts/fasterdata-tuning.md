# Fasterdata Host & Network Tuning (EL9)

This page documents `fasterdata-tuning.sh`, a script that audits and optionally applies ESnet Fasterdata-inspired host
and NIC tuning recommendations for Enterprise Linux 9.

Script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

## Purpose

The `fasterdata-tuning.sh` script helps network administrators optimize Enterprise Linux 9 systems for high-throughput data transfers by:

- **Auditing** current system configuration against ESnet Fasterdata best practices
- **Applying** recommended tuning automatically with safe defaults
- **Testing** different configurations via save/restore state management (v1.2.0+)
- **Persisting** settings across reboots via systemd and sysctl.d

Recommended for perfSONAR testpoints, Data Transfer Nodes (DTNs), and dedicated high-performance networking hosts.

## Download & Install

You can download the script directly from the website or GitHub raw URL and install it locally for repeated use:

```bash
# Download via curl to a system location and make it executable
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh

# Or download directly from the site (if published):
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

## Verify the checksum (optional)

To verify script integrity, compare the downloaded file with the provided SHA256 checksum:

```bash
# Download script and checksum
curl -L -o /tmp/fasterdata-tuning.sh \
  https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
curl -L -o /tmp/fasterdata-tuning.sh.sha256 \
  https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh.sha256

# Verify checksum
sha256sum -c /tmp/fasterdata-tuning.sh.sha256
```

Expected output: `fasterdata-tuning.sh: OK`

**Note:** The checksum file is manually maintained and updated with each script release.

## Why use this script?

This script packages ESnet Fasterdata best practices into an audit/apply helper that:

- Provides a non-invasive audit mode to compare current host settings against Fasterdata recommendations tailored by NIC speed and host role (measurement vs DTN).

- Centralizes recommended sysctl tuning for high-throughput, long-distance transfers (buffer sizing, qdisc, congestion control), reducing guesswork and manual errors.

- Applies and persists sysctl settings in `/etc/sysctl.d/90-fasterdata.conf` and helps persist per-NIC settings (ethtool) via a `systemd` oneshot service; it also checks for problematic driver versions and provides vendor-specific guidance.

- For DTN nodes: Supports packet pacing via traffic control (tc) token bucket filter (tbf) to limit outgoing traffic to a specified rate, important for multi-stream transfer scenarios.

## Who should use it?

- perfSONAR testpoints, dedicated DTNs and other throughput-focused hosts on EL9 where you control the host configuration.

- NOT for multi-tenant or general-purpose interactive servers without prior review — these sysctl changes can affect other services.

## Verification & Basic checks

After running the script (audit or apply), verify key settings:

```
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

## Security & safety

- Always test in a staging environment first. Use `--mode audit` to review before applying.

- The `iommu` and `SMT` settings are environment-sensitive: IOMMU changes require GRUB kernel cmdline edits and a reboot. The script only suggests GRUB edits and does not automatically change the bootloader.

- If you require automated GRUB edits or SMT toggles, those should be opt-in with thorough confirmation prompts and recovery steps.

## Usage

**Quick Usage:**

```bash
# Audit mode (no changes)
/usr/local/bin/fasterdata-tuning.sh --mode audit --target measurement

# Apply tuning (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target dtn

# Apply with specific interfaces
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target measurement --ifaces "ens1f0np0,ens1f1np1"

# Apply with packet pacing
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing --packet-pacing-rate 5gbps

# Audit packet pacing settings
/usr/local/bin/fasterdata-tuning.sh --mode audit --target dtn --packet-pacing-rate 10gbps
```

Notes
-----
 - IOMMU: The script checks whether `iommu=pt` plus vendor-specific flags (`intel_iommu=on` or `amd_iommu=on`) are present. When you run with `--apply-iommu` and `--mode apply`, the script will optionally back up `/etc/default/grub`, append the appropriate IOMMU flags (or use values provided via `--iommu-args`) and regenerate GRUB (using `grubby` or `grub2-mkconfig` where available). Use `--dry-run` to preview the GRUB changes. You may also set `--iommu-args "intel_iommu=on iommu=pt"` to provide custom boot args.
- SMT: The script detects SMT status and suggests commands to toggle runtime SMT; persistence requires GRUB edits (kernel cmdline). It does not toggle SMT by default.
- Apply mode writes to `/etc/sysctl.d/90-fasterdata.conf` and creates `/etc/systemd/system/ethtool-persist.service` when necessary.
- **Packet Pacing (DTN only):** For Data Transfer Node targets, the script can apply token bucket filter (tbf) qdisc to pace outgoing traffic. This is recommended when a DTN node handles multiple simultaneous transfers where the effective transfer rate is limited by the minimum of: source read rate, network bandwidth, and destination write rate. See the `--apply-packet-pacing` and `--packet-pacing-rate` flags below. For detailed information on why packet pacing is important and how it works, see the separate [Packet Pacing guide](../packet-pacing.md).

Optional apply flags (use with `--mode apply`):

- `--apply-packet-pacing`: Apply packet pacing to DTN interfaces via tc token bucket filter. Only works with `--target dtn`. Default pacing rate is 2 Gbps (adjustable with `--packet-pacing-rate`).
- `--packet-pacing-rate RATE`: Set the packet pacing rate for DTN nodes. Accepts units: kbps, mbps, gbps, tbps (e.g., `2gbps`, `10gbps`, `10000mbps`). Default: 2000mbps. Burst size is automatically calculated as 1 millisecond worth of packets at the specified rate.
- `--apply-iommu`: Edit GRUB to add `iommu=pt` and vendor-specific flags (e.g., `intel_iommu=on iommu=pt`) to the kernel cmdline and regenerate GRUB. On EL9/BLS systems the script will use `grubby` to update kernel entries; otherwise it falls back to `grub2-mkconfig -o /boot/grub2/grub.cfg` or `update-grub` as available. Requires confirmation or `--yes` to skip the interactive prompt.
- `--iommu-args ARGS`: Provide custom kernel cmdline arguments to apply for IOMMU (e.g., `intel_iommu=on iommu=pt`). When set, these args override vendor-appropriate defaults.
- `--apply-smt on|off`: Toggle SMT state at runtime. Requires `--mode apply`. Example: `--apply-smt off`.
- `--persist-smt`: If set along with `--apply-smt`, also persist the change via GRUB edits (`nosmt` applied/removed).
- `--yes`: Skip interactive confirmations; use with caution.
- `--dry-run`: Preview the exact GRUB, sysctl, tc, and sysfs commands that would be run without actually applying them. Useful for audits and CI checks.

**Examples:**

```bash
# Preview IOMMU changes (dry-run)
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --apply-iommu --dry-run

# Apply with custom IOMMU args
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --apply-iommu --iommu-args "intel_iommu=on iommu=pt" --yes
```

## State management: Save and restore configurationsns

**NEW in v1.2.0**: The script now supports saving and restoring system state for testing different tuning configurations.

### Quick testing workflow

**TL;DR**: Save baseline → Apply tuning → Test → Restore → Compare

```bash
# Save baseline state
sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline

# Apply tuning
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target measurement --yes

# Run your performance tests here (iperf3, perfSONAR tests, etc.)

# Restore baseline
sudo /usr/local/bin/fasterdata-tuning.sh --restore-state baseline --yes

# Compare configurations
/usr/local/bin/fasterdata-tuning.sh --diff-state baseline
```

**For detailed step-by-step workflow with multiple tuning profiles, see [Example Performance Testing Workflow](#example-performance-testing-workflow) below.**

### Why use save/restore?

When testing performance with different tuning configurations, you need to:

1. Save your baseline (pre-tuning) configuration
2. Apply tuning changes
3. Test performance
4. Restore the baseline to test alternative configurations
5. Compare results

The save/restore functionality captures all settings that `--mode apply` modifies, including:

- Sysctl parameters (TCP buffers, congestion control, etc.)
- Per-interface settings (txqueuelen, MTU, ring buffers, offload features, qdisc)
- Configuration files (`/etc/sysctl.d/90-fasterdata.conf`, `/etc/systemd/system/ethtool-persist.service`)
- CPU governor settings
- Tuned profile
- SMT (Simultaneous Multithreading) state

**Note**: GRUB/boot configuration (IOMMU, persistent SMT) is not saved/restored as it requires a reboot to take effect.

### Save Current State

Save the current system configuration before making changes:

```bash
# Save state with a descriptive label (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline

# Save state with automatic timestamp
sudo /usr/local/bin/fasterdata-tuning.sh --save-state
```

State files are stored in: `/var/lib/fasterdata-tuning/saved-states/`

### Auto-save Before Apply

Automatically save the current state before applying changes:

```bash
# Apply tuning and auto-save the pre-apply state
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target measurement --auto-save-before --label pre-tuning
```

### List Saved States

View all saved configuration states:

```bash
/usr/local/bin/fasterdata-tuning.sh --list-states
```

Example output:

```
Saved States:
=============

File: 20251210-143000-baseline.json
  Timestamp: 2025-12-10T14:30:00Z
  Label: baseline
  Hostname: perfsonar.example.org
  Path: /var/lib/fasterdata-tuning/saved-states/20251210-143000-baseline.json

File: 20251210-150000-tuned-measurement.json
  Timestamp: 2025-12-10T15:00:00Z
  Label: tuned-measurement
  Hostname: perfsonar.example.org
  Path: /var/lib/fasterdata-tuning/saved-states/20251210-150000-tuned-measurement.json
```

### Compare Current vs Saved State

Show differences between current configuration and a saved state:

```bash
# Compare using label
/usr/local/bin/fasterdata-tuning.sh --diff-state baseline

# Compare using filename
/usr/local/bin/fasterdata-tuning.sh --diff-state 20251210-143000-baseline.json
```

### Restore State

Restore a previously saved configuration:

```bash
# Restore using label (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --restore-state baseline --yes

# Restore using filename (with interactive confirmation)
sudo /usr/local/bin/fasterdata-tuning.sh --restore-state 20251210-143000-baseline.json
```

The restore process:

1. Validates the state file exists and is valid JSON
2. Warns if restoring from a different hostname
3. Prompts for confirmation (unless `--yes` specified)
4. Restores all saved settings:
   - Sysctl parameters (runtime)
   - Configuration files
   - Per-interface settings
   - CPU governor
   - Tuned profile
5. Reports success/failure for each component

### Delete Saved State

Remove a saved state file:

```bash
# Delete using label (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --delete-state baseline --yes

# Delete using filename (with interactive confirmation)
sudo /usr/local/bin/fasterdata-tuning.sh --delete-state 20251210-143000-baseline.json
```

### Example Performance Testing Workflow

Complete workflow for testing before/after tuning:

```bash
# 1. Save baseline configuration
sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline

# 2. Run baseline performance tests
# ... run your perfSONAR tests, iperf3, etc ...

# 3. Apply tuning with auto-save
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target measurement --auto-save-before --label pre-measurement-tuning

# 4. Run tests with tuned configuration
# ... run your perfSONAR tests, iperf3, etc ...

# 5. Compare configurations
/usr/local/bin/fasterdata-tuning.sh --diff-state baseline

# 6. Try alternative tuning (e.g., DTN profile)
sudo /usr/local/bin/fasterdata-tuning.sh --restore-state baseline --yes
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target dtn --auto-save-before --label pre-dtn-tuning

# 7. Run tests with DTN tuning
# ... run your perfSONAR tests, iperf3, etc ...

# 8. Restore to baseline when done
sudo /usr/local/bin/fasterdata-tuning.sh --restore-state baseline --yes

# 9. Verify restoration
/usr/local/bin/fasterdata-tuning.sh --mode audit
```

### State management caveats

**What is and is not saved/restored:**

| Component | Saved/Restored | Notes |
|-----------|----------------|-------|
| Sysctl parameters | ✅ Yes | Runtime values (TCP buffers, congestion control, etc.) |
| Configuration files | ✅ Yes | `/etc/sysctl.d/90-fasterdata.conf`, systemd services |
| Per-interface settings | ✅ Yes | txqueuelen, MTU, ring buffers, offload features, qdisc |
| CPU governor | ✅ Yes | Runtime setting |
| SMT state | ✅ Yes | Runtime setting |
| Tuned profile | ✅ Yes | Active profile |
| GRUB kernel cmdline | ❌ No | Requires reboot (IOMMU, persistent nosmt); not suitable for testing cycles |
| Kernel module parameters | ❌ No | Out of scope |
| Firewall rules | ❌ No | Not modified by this script |
| Network interfaces | ❌ No | Interface creation/deletion not supported |

**Important limitations:**

1. **Hardware-dependent**: Ring buffer sizes are limited by NIC hardware; restoration may fail if hardware doesn't support saved values
2. **Hostname-specific**: Restoring a state from a different hostname will trigger a warning but proceed
3. **NetworkManager**: Connection modifications may cause brief network interruptions
4. **Side effects**: Changing tuned profile may modify additional sysctls not tracked by this script
5. **Requires python3**: State save/restore operations require python3 for JSON processing

### State file format

State files are stored as JSON in `/var/lib/fasterdata-tuning/saved-states/` with the following structure:

- **Metadata**: Timestamp, hostname, kernel version, label, creator version
- **Sysctl values**: All tracked network tuning parameters
- **Configuration files**: Base64-encoded content with backup paths
- **Per-interface settings**: MTU, txqueuelen, qdisc, ethtool features, ring buffers, NetworkManager connection info
- **System settings**: CPU governor, SMT state, tuned profile
- **Warnings**: List of restoration limitations

Backup copies of modified files are stored in `/var/lib/fasterdata-tuning/backups/`.

## Reference and source

- Source script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`
- Fasterdata docs: https://fasterdata.es.net/host-tuning/
- DTN tuning and packet pacing guidance: https://fasterdata.es.net/DTN/tuning/

If you use this script as part of a host onboarding flow, ensure you test it in a VM or staging host before applying to production hosts.
