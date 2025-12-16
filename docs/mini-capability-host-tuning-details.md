# Host Optimization and Tuning – Details

This document contains the detailed procedures, checklists, and troubleshooting content referenced by the concise plan.

## State Management

- Save location: `/var/lib/fasterdata-tuning/saved-states/` (JSON) and backups in `/var/lib/fasterdata-tuning/backups/`.
- Commands:
  - Save baseline: `sudo fasterdata-tuning.sh --save-state --label baseline`
  - List: `sudo fasterdata-tuning.sh --list-states`
  - Diff: `sudo fasterdata-tuning.sh --diff-state <file.json>`
  - Restore: `sudo fasterdata-tuning.sh --restore-state <file.json>`
  - Auto-save before apply: `sudo fasterdata-tuning.sh --mode apply --auto-save-before --label pre-apply`
- Captured: sysctl, interface settings (MTU, qdisc, txqueuelen, ethtool flags, rings), persistence artifacts, GRUB/cmdline, tuned profile, CPU governor/SMT.
- Caveats: kernel cmdline changes require reboot; some ring buffers not fully reversible.
- Verification checklist:
  - `--list-states` shows the saved file
  - `--diff-state` shows expected diffs
  - After restore, key sysctls and `tc qdisc` match baseline
  - Short transfer confirms baseline behavior

## Global Sweep – Checklist

1. Prepare configs: baseline, network-tuned (fq), network+storage, tbf-cap.
2. Record baseline on every host (`--save-state --label baseline`).
3. Apply via Ansible; storage via playbooks (`/sys/block/*/queue/scheduler`).
4. Audit all hosts (`--mode audit --json`) and collect outputs.
5. Run synchronized transfers; collect logs under `logs/<config>/`.
6. Save tuned state (`--save-state --label <config>`).
7. Repeat for each config; restore baseline between as needed.
8. Aggregate ≥3 iterations; compute means, 95% CI; paired comparisons.

## Troubleshooting

### Network Diagnostics
- perfSONAR and iperf3 (single/multi-flow), verify BBR/fq pacing, VLAN/bond integrity.
- Check packet loss/reordering (tcpdump); NIC offloads (GRO/TSO/GSO).

### Storage Diagnostics
- fio throughput/latency; iostat -x queue/service times; dCache/XRootD/EOS logs.

## Cost/Risk – Rollback Procedure

- Network: restore baseline JSON, verify diff, reboot if cmdline needed, run short WAN transfer.
- Storage: restore scheduler (`/sys/block/*/queue/scheduler`), verify fio/iostat metrics.

## References

- Fasterdata tuning script: docs/perfsonar/tools_scripts/fasterdata-tuning.sh
- Ansible playbooks for storage scheduler and NUMA affinity (site-specific)
