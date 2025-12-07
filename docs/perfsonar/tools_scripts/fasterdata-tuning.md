# Fasterdata Host & Network Tuning (EL9)

This page documents `fasterdata-tuning.sh`, a script that audits and optionally applies ESnet Fasterdata-inspired host
and NIC tuning recommendations for Enterprise Linux 9.

Script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

## Purpose

## Download & Install

You can download the script directly from the website or GitHub raw URL and install it locally for repeated use:

```bash

# Download via curl to a system location and make it executable

sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh <https://raw.githubusercontent.com/osg-
htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh> sudo chmod +x /usr/local/bin/fasterdata-
tuning.sh

# Or download directly from the site (if published):

sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh <https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-
tuning.sh> sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

## Verify the checksum

To verify the script integrity, compare the downloaded script with the provided SHA256 checksum file in this repo:

```bash curl -L -o /tmp/fasterdata-tuning.sh <https://raw.githubusercontent.com/osg->
htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh curl -L -o /tmp/fasterdata-tuning.sh.sha256
https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh.sha256
sha256sum -c /tmp/fasterdata-tuning.sh.sha256 --status && echo "OK" || echo "Checksum mismatch"
``` text

## Why use this script?

This script packages ESnet Fasterdata best practices into an audit/apply helper that:

* Provides a non-invasive audit mode to compare current host settings against Fasterdata recommendations tailored by NIC speed and host role (measurement vs DTN).

* Centralizes recommended sysctl tuning for high-throughput, long-distance transfers (buffer sizing, qdisc, congestion control), reducing guesswork and manual errors.

* Applies and persists sysctl settings in `/etc/sysctl.conf` and helps persist per-NIC settings (ethtool) via a `systemd` oneshot service; it also checks for problematic driver versions and provides vendor-specific guidance.

* For DTN nodes: Supports packet pacing via traffic control (tc) token bucket filter (tbf) to limit outgoing traffic to a specified rate, important for multi-stream transfer scenarios.

## Who should use it?

* perfSONAR testpoints, dedicated DTNs and other throughput-focused hosts on EL9 where you control the host configuration.

* NOT for multi-tenant or general-purpose interactive servers without prior review — these sysctl changes can affect other services.

## Verification & Basic checks

After running the script (audit or apply), verify key settings:

```

# Sysctl

sysctl net.core.rmem_max net.core.wmem_max net.core.netdev_max_backlog net.core.default_qdisc

# Tuned active profile

tuned-adm active || echo "tuned-adm not present"

# Per NIC checks

ethtool -k <iface> # offload features ethtool -g <iface> # ring buffer sizes tc qdisc show dev <iface>

# Verify IOMMU in kernel cmdline

cat /proc/cmdline | grep -E "iommu=pt|intel_iommu=on|amd_iommu=on"
``` text

## Security & Safety

* Always test in a staging environment first. Use `--mode audit` to review before applying.

* The `iommu` and `SMT` settings are environment-sensitive: IOMMU changes require GRUB kernel cmdline edits and a reboot. The script only suggests GRUB edits and does not automatically change the bootloader.

* If you require automated GRUB edits or SMT toggles, those should be opt-in with thorough confirmation prompts and recovery steps.

## Usage

bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement

```

Apply tuning (requires root):

``` text

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn

```

Limit apply to specific NICs (comma-separated):

``` text

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target measurement --ifaces
"ens1f0np0,ens1f1np1"

```

Apply packet pacing to DTN nodes (limit traffic to 5 Gbps):

``` text

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing --packet-
pacing-rate 5gbps

```

Audit without applying changes (DTN target with custom pacing rate):

``` text

bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target dtn --packet-pacing-rate 10gbps

```

Notes -----

  * IOMMU: The script checks whether `iommu=pt` plus vendor-specific flags (`intel_iommu=on` or `amd_iommu=on`) are present. When you run with `--apply-iommu` and `--mode apply`, the script will optionally back up `/etc/default/grub`, append the appropriate IOMMU flags (or use values provided via `--iommu-args`) and regenerate GRUB (using `grubby` or `grub2-mkconfig` where available). Use `--dry-run` to preview the GRUB changes. You may also set `--iommu-args "intel_iommu=on iommu=pt"` to provide custom boot args.

* SMT: The script detects SMT status and suggests commands to toggle runtime SMT; persistence requires GRUB edits (kernel cmdline). It does not toggle SMT by default.

* Apply mode writes to `/etc/sysctl.conf` and creates `/etc/systemd/system/ethtool-persist.service` when necessary.

* **Packet Pacing (DTN only):** For Data Transfer Node targets, the script can apply token bucket filter (tbf) qdisc to pace outgoing traffic. This is recommended when a DTN node handles multiple simultaneous transfers where the effective transfer rate is limited by the minimum of: source read rate, network bandwidth, and destination write rate. See the `--apply-packet-pacing` and `--packet-pacing-rate` flags below. For detailed information on why packet pacing is important and how it works, see the separate [Packet Pacing guide](../packet-pacing.md).

Optional apply flags (use with `--mode apply`):

* `--apply-packet-pacing`: Apply packet pacing to DTN interfaces via tc token bucket filter. Only works with `--target dtn`. Default pacing rate is 2 Gbps (adjustable with `--packet-pacing-rate`).

* `--packet-pacing-rate RATE`: Set the packet pacing rate for DTN nodes. Accepts units: kbps, mbps, gbps, tbps (e.g., `2gbps`, `10gbps`, `10000mbps`). Default: 2000mbps. Burst size is automatically calculated as 1 millisecond worth of packets at the specified rate.

* `--apply-iommu`: Edit GRUB to add `iommu=pt` and vendor-specific flags (e.g., `intel_iommu=on iommu=pt`) to the kernel cmdline and regenerate GRUB. On EL9/BLS systems the script will use `grubby` to update kernel entries; otherwise it falls back to `grub2-mkconfig -o /boot/grub2/grub.cfg` or `update-grub` as available. Requires confirmation or `--yes` to skip the interactive prompt.

* `--iommu-args ARGS`: Provide custom kernel cmdline arguments to apply for IOMMU (e.g., `intel_iommu=on iommu=pt`). When set, these args override vendor-appropriate defaults.

* `--apply-smt on|off`: Toggle SMT state at runtime. Requires `--mode apply`. Example: `--apply-smt off`.

* `--persist-smt`: If set along with `--apply-smt`, also persist the change via GRUB edits (`nosmt` applied/removed).

* `--yes`: Skip interactive confirmations; use with caution.

* `--dry-run`: Preview the exact GRUB, sysctl, tc, and sysfs commands that would be run without actually applying them. Useful for audits and CI checks.

Example (preview only):

``` text

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --apply-iommu --dry-run

```

To actually apply and pass specific IOMMU args:

``` text

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --apply-iommu --iommu-args "intel_iommu=on
iommu=pt" --yes

```

## Reference and source

* Source script: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

* Fasterdata docs: https://fasterdata.es.net/host-tuning/

* DTN tuning and packet pacing guidance: https://fasterdata.es.net/DTN/tuning/

If you use this script as part of a host onboarding flow, ensure you test it in a VM or staging host before applying to
production hosts.
