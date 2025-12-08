# Host and Network Tuning (EL9)

This guide distills ESnet Fasterdata recommendations for high-throughput hosts (perfSONAR/DTN-style) on Enterprise Linux

1. Primary sources:

- <https://fasterdata.es.net/host-tuning/>

- <https://fasterdata.es.net/network-tuning/>

- <https://fasterdata.es.net/DTN/>

Use the provided audit/apply script to check your host against these recommendations and optionally enforce them. Read
the cautions before applying.

## What this covers

- Kernel networking sysctls: buffers, congestion control, qdisc, MTU probing

- Tuned profile: `network-throughput`

- Per-interface checks: ring buffers, GRO/GSO/TSO on, LRO off, checksum on, txqueuelen, fq qdisc

- Congestion control: prefer `bbr` (fallback to `cubic` if unavailable)

## When to use this

- perfSONAR testpoints, DTNs, and other dedicated measurement/transfer hosts on EL9

- Fresh installs or periodic compliance checks against Fasterdata guidance

- Not for multi-tenant or latency-sensitive hosts without review

## Script: `fasterdata-tuning.sh`

Path: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

Modes:

- `audit` (default): show current settings vs recommendations, no changes

- `apply`: set recommended values (requires root)

Options:

- `--mode audit|apply`: mode selection

- `--target measurement|dtn`: host type for scaled recommendations (default: `measurement`)

- `--ifaces eth0,eth1`: comma-separated interface list (default: auto-detect physical NICs)

- `--color`: enable color-coded output (green=compliant, yellow=warning, red=critical)

### Host Types

The script tailors recommendations by host type:

- **measurement**: perfSONAR testpoints, measurement nodes (primary focus)

- **dtn**: Data Transfer Nodes (larger buffers for bulk throughput)

Differences:

- `net.core.netdev_max_backlog`: measurement uses 500k at 100Gbps; dtn uses 600k

- `txqueuelen`: measurement targets 10k/15k/20k; dtn targets 12k/18k/25k (per link speed)

### Examples

Audit a measurement host:

```bash
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement
```

Apply tuning for a DTN (100Gbps links):

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn
```

Limit to specific NICs:

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target measurement --ifaces "ens1f0np0,ens1f1np1"
```

### What the script does

- **Sysctl**: Sets larger rmem/wmem, netdev backlog, `default_qdisc=fq`, `tcp_mtu_probing=1`, TCP r/w mem, timestamps/SACK on, low_latency off; prefers `bbr` if available. Values scale with fastest NIC link speed and target type (measurement vs dtn). Settings written to `/etc/sysctl.d/90-fasterdata.conf` in apply mode.

- **Tuned**: Ensures `network-throughput` profile if `tuned-adm` is present.

- **Ethtool persistence** (apply mode): Creates or updates `/etc/systemd/system/ethtool-persist.service` to persist NIC tunings across reboots (ring buffers, offloads, txqueuelen).

- **Driver checks**: Detects driver vendor/version (Mellanox, Broadcom, Intel, other); reports kernel/firmware updates available; provides vendor-specific guidance (e.g., "keep kernel+linux-firmware current", "consider NVIDIA OFED for Mellanox").

- **Interfaces** (per NIC, scaled by link speed):

- Set `txqueuelen` to ≥ 10k (measurement) or ≥ 12k (dtn); 20k/25k for 100Gbps

- Set RX/TX rings to driver max (if reported)

- Enable GRO/GSO/TSO and checksums; disable LRO

- Replace qdisc with `fq`

### Output and logs

The script outputs a **Host Info** section at the top showing:

- Hostname (FQDN)

- OS name/version (from `/etc/os-release`)

- Running kernel version

- System memory (GiB)

- SMT status (on/off/unavailable); yellow warning if SMT is off (off-topic: helps isolate jitter in measurement contexts, but should be on by default for throughput)

Then it displays sysctl audit and per-NIC summaries, followed by a summary block showing:

- Target type (measurement/dtn)

- Sysctl mismatches (count)

- Per-interface issues (tx queue, qdisc, offloads, rings)

- Driver/version actions (kernel updates available, vendor guidance)

- SMT control guidance (if SMT is off, suggests toggle commands)

- Missing tools (ethtool, tuned-adm, cpupower)

Detailed log with full ethtool/sysctl/tc output is written to `/tmp/fasterdata-tuning-<UTC>.log` (configurable via
`LOGFILE` env var).

## Getting the Fasterdata script

You can download the script directly from the GitHub repo (raw) or the site after it is published:

```text
https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-tuning.sh
```

Install quickly as follows:

```bash
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

Then run an audit before applying changes:

```bashbash
bash /usr/local/bin/fasterdata-tuning.sh --mode audit --target measurement
```

### Color Output

Use `--color` flag to enable ANSI color codes:

- Green: settings comply with recommendations

- Yellow: warning/attention needed (e.g., SMT off, missing tools, suboptimal settings)

- Red: critical issues requiring immediate attention (not currently used, reserved for future severity levels)

### Driver Guidance

The script identifies your NIC drivers and provides upgrade paths:

- **Mellanox/NVIDIA** (`mlx5_core`, `mlx4_en`): Keep kernel+linux-firmware current or use NVIDIA OFED (<https://network.nvidia.com/products/ethernet-drivers/>).

- **Broadcom** (`bnxt_en`, `tg3`, `bnx2x`, `bnx2`): Track distro kernel; use vendor firmware tools (e.g., `bnxtnvm`) when available.

- **Intel** (`ixgbe`, `i40e`, `ice`, `e1000e`, `igb`): Update kernel+linux-firmware for latest drivers and firmware blobs.

If a kernel update is available, the summary will recommend: `dnf update kernel && reboot`.

### Cautions

- **Apply mode changes the running system** and writes sysctl to `/etc/sysctl.d/90-fasterdata.conf`.

- **Persistence of ethtool settings**: In apply mode, the script automatically creates or updates `/etc/systemd/system/ethtool-persist.service` to persist NIC tunings (ring buffers, offloads, txqueuelen) across reboots. The service is enabled automatically.

- **Sysctl settings** in `/etc/sysctl.d/90-fasterdata.conf` persist across reboots.

- **SMT control** (if changed) requires GRUB config to persist; see [SMT section](#smt-simultaneous-multi-threading) below.

- **Tuned profile** changes persist if tuned-adm writes to its default config.

- The script assumes EL9 userland (`sysctl`, `ethtool`, `tc`, `tuned-adm`). It skips steps if tools are missing.

- If `bbr` is not available, it falls back to `cubic` live but keeps `bbr` in the config for future kernels.

- Always validate after applying: check `podman ps`/services, run a quick throughput test, and review `dmesg`/`journal` for NIC or driver warnings.

- To verify ethtool persistence service: `systemctl status ethtool-persist` and `systemctl cat ethtool-persist.service`

## Optional apply flags

The script supports a few additional opt-in apply flags when run with `--mode apply`:

- `--apply-iommu`: Edit GRUB to add recommended `iommu=pt` plus vendor-specific flags (Intel/AMD) and regenerate grub. Requires root and careful review before committing. Example:

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --apply-iommu --yes
```

- `--apply-smt on|off`: Apply SMT change at runtime. Use `--persist-smt` to make the choice persistent in GRUB. Example:

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --apply-smt off --persist-smt --yes
```

Preview (dry-run) example:

```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --apply-iommu --dry-run
```

## Manual checklist (summary of recommendations)

Values shown below are baseline (1Gbps). The script scales them by fastest NIC speed and target type.

- Sysctl

- `net.core.rmem_max`/`wmem_max`: 536M–1G (measurement); 1G (dtn at 100Gbps)s)

- `net.core.rmem_default`/`wmem_default`: 128M

- `net.core.netdev_max_backlog`: 250k–500k (measurement); 250k–600k (dtn)

- `net.core.default_qdisc`: `fq`

- `net.ipv4.tcp_rmem`: `4096 87380 536870912`

- `net.ipv4.tcp_wmem`: `4096 65536 536870912`

- `net.ipv4.tcp_congestion_control`: `bbr` (or `cubic` if `bbr` absent)

- `net.ipv4.tcp_mtu_probing`: `1`

- `net.ipv4.tcp_window_scaling`: `1`

- `net.ipv4.tcp_timestamps`: `1`

- `net.ipv4.tcp_sack`: `1`

- `net.ipv4.tcp_low_latency`: `0`

- Tuned: `tuned-adm profile network-throughput`

- Interfaces

- `txqueuelen` ≥ 10000

- RX/TX rings at driver max (`ethtool -g` / `-G`)

- GRO/GSO/TSO on; checksums on; LRO off

- qdisc `fq` (root)

## Verification after tuning

```bash
sysctl -a | egrep "(rmem|wmem|max_backlog|default_qdisc|tcp_congestion_control|tcp_mtu_probing)"
tuned-adm active
```

For each NIC: `ethtool -k <iface>`, `ethtool -g <iface>`, `tc qdisc show dev <iface>`, `cat
/sys/class/net/<iface>/tx_queue_len`

Run a representative throughput test (e.g., `iperf3`) end-to-end.

## Additional Topics

### SMT (Simultaneous Multi-Threading)

The script detects and reports SMT status. For most measurement hosts (perfSONAR), **SMT should be on** to maximize CPU
throughput. However, for isolated low-latency workloads, SMT off may reduce jitter.

**To check SMT status:**

```bash
cat /sys/devices/system/cpu/smt/control
```

**To enable SMT:**

```bash
echo on | sudo tee /sys/devices/system/cpu/smt/control
```

**To disable SMT:**

```bash
echo off | sudo tee /sys/devices/system/cpu/smt/control
```

Note: SMT changes take effect immediately but are not persisted across reboots. To persist, add to kernel command line
(GRUB): `nosmt` (to disable) or remove it (to enable).

### Driver Updates

The script checks for available kernel and driver updates via `dnf list --showduplicates kernel`. If an update is
available, the summary recommends:

```bash
dnf update kernel && reboot
```

For vendor-specific drivers (Mellanox OFED, Broadcom firmware tools), the script provides URLs and guidance. Always
validate driver compatibility before updating in production.

### Troubleshooting

If the script fails to detect certain hardware or settings:

- **Missing `ethtool`**: Install via `dnf install ethtool`

- **Missing `tuned-adm`**: Install via `dnf install tuned`

- **No cpufreq/governor**: Some VMs lack CPU frequency scaling; this is normal

- **No IOMMU**: Fasterdata recommends `iommu=pt` generally, with vendor additions: enable in GRUB (e.g., `intel_iommu=on iommu=pt` for Intel, `amd_iommu=on iommu=pt` for AMD) if using SR-IOV or isolation features. Add `iommu=pt` to improve throughput on high-speed NICs.

- **ethtool-persist.service fails to start**: Check `/var/log/messages` or `journalctl -u ethtool-persist` for errors; ensure ethtool and ip commands exist at `/sbin/` paths

### Persistence Service Details

When running with `--mode apply`, the script generates `/etc/systemd/system/ethtool-persist.service` containing:

```systemd
[Unit]
Description=Persist ethtool settings (Fasterdata)
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ethtool -G <iface> rx <max> tx <max>
ExecStart=/sbin/ethtool -K <iface> gro on gso on tso on rx on tx on lro off
ExecStart=/sbin/ip link set dev <iface> txqueuelen <value>
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

The service is automatically enabled. To verify:

```bash
systemctl status ethtool-persist.service
systemctl cat ethtool-persist.service
```

To manually update this service, re-run the script with `--mode apply` to regenerate it with current NIC settings.

## Persistence notes

- Sysctl settings persist via `/etc/sysctl.d/90-fasterdata.conf`

- NIC ethtool changes do not persist by default; consider:

- running this script from a boot-time systemd unit, or

- translating the settings into your network manager configuration
