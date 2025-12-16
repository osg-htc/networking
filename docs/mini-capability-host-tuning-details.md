# Host Optimization and Tuning – Details

This document contains the full procedures, tables, and checklists referenced by the concise plan.

## 1. State Management

- Save location:
  - States: `/var/lib/fasterdata-tuning/saved-states/*.json`
  - Backups: `/var/lib/fasterdata-tuning/backups/`
- Commands:
  - Save baseline: `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline`
  - List states: `sudo /usr/local/bin/fasterdata-tuning.sh --list-states`
  - Diff vs current: `sudo /usr/local/bin/fasterdata-tuning.sh --diff-state /var/lib/fasterdata-tuning/saved-states/<file>.json`
  - Restore: `sudo /usr/local/bin/fasterdata-tuning.sh --restore-state /var/lib/fasterdata-tuning/saved-states/<file>.json`
  - Auto-save on apply: `sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --auto-save-before --label pre-apply`
- Captured:
  - Sysctl values and `/etc/sysctl.d/90-fasterdata.conf`
  - Interface settings: MTU, qdisc, txqueuelen, ethtool flags, ring sizes
  - Persistence artifacts: ethtool-persist service content
  - GRUB/kernel cmdline (IOMMU/SMT), tuned profile, CPU governor/SMT
- Caveats:
  - Kernel cmdline changes require reboot to take effect
  - Some hardware ring buffer values may not restore exactly
- Verification checklist:
  - `--list-states` shows saved baseline file
  - `--diff-state <baseline.json>` shows expected diffs only
  - After restore, key sysctls and `tc qdisc` match baseline
  - Run a short transfer to confirm baseline behavior

## 2. Global Configuration Sweep (Fleet-Wide)

Purpose: Measure impact when all hosts share the same configuration, then switch fleet-wide and re-measure.

Steps:
1. Prepare configuration variants and exact commands/playbooks:
   - `baseline` (stock)
   - `network-tuned` (Fasterdata apply with `fq` pacing)
   - `network+storage-tuned` (Fasterdata + selected I/O scheduler)
   - `tbf-cap` (token bucket filter cap + storage tune, if needed)
2. Record baseline on every host:
   - `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline`
   - Record filenames centrally per host
3. Apply configuration via orchestration:
   - Example ad-hoc: `ansible data-transfer -i inventory -m shell -a "sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --apply-packet-pacing --yes"`
   - Storage changes via playbooks writing `/sys/block/*/queue/scheduler`
4. Confirm apply:
   - Audit all hosts and collect JSON: `ansible data-transfer -m shell -a "sudo /usr/local/bin/fasterdata-tuning.sh --mode audit --json" -o > audit-outputs/<config>-audit.json`
5. Synchronized transfers:
   - Start within 1 minute across sites; run GridFTP/FTS/XRootD tests; collect logs (production + test)
6. Save tuned state on each host:
   - `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label <config>`
7. Repeat for each configuration; restore baseline between configs as needed.
8. Aggregate results:
   - ≥3 iterations/config; compute means and 95% CI; perform paired comparisons.

Checklist:
- Expected audit results present for current config
- Saved state files recorded centrally for each host
- Transfer starts synchronized; production load documented
- Logs archived under `logs/<config>/`
- Post-restore short transfer validates baseline behavior

Cautions:
- Test restores on non-production nodes first
- Schedule reboot windows for kernel cmdline changes
- Document ring buffer limitations per hardware if restore differs

## 3. Measurements (Tables)

### 3.1 Primary WAN Metrics

| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| GridFTP/FTS throughput | Real transfers to remote sites | Baseline + 10–15% | Significant improvement |
| XRootD throughput | Read/write to remote endpoint | Baseline + 10% | Improvement or stable |
| HTTP/WebDAV throughput | Upload/download to remote storage | Baseline + 10% | Improvement or stable |
| perfSONAR throughput | Automated tests to remote nodes | Link capacity - 5% | Near-line-rate utilization |
| Transfer completion time | GridFTP/FTS duration | Baseline - 10% | Faster transfers |
| CPU during transfer | top, sar | <70% at saturation | Improved efficiency |
| I/O wait during transfer | iostat, sar (%iowait) | <20% | Storage not bottleneck |
| Network retransmits | ss -ti, ethtool -S | <0.01% of packets | Stable or improved |

### 3.2 Secondary Network Metrics

| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| Single-flow throughput | iperf3 -t 3600 | Baseline + 10% | Improvement or no regression |
| Multi-flow throughput | iperf3 -P 10 | Baseline + 5% | Improvement or no regression |
| RTT latency | perfSONAR ping, iperf3 | Stable vs baseline | No degradation |
| Memory usage (TCP buffers) | /proc/meminfo | <5% of RAM | Acceptable overhead |

### 3.3 Secondary Storage Metrics

| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| Sequential read throughput | fio (seq-read, direct I/O) | Baseline + 5% | Improvement or stable |
| Sequential write throughput | fio (seq-write, direct I/O) | Baseline + 5% | Improvement or stable |
| I/O latency (p50, p99) | fio (latency histogram) | <10ms (p50) | Stable or improved |
| I/O queue depth | iostat -x (avgqu-sz) | Optimized per scheduler | No bottleneck |

### 3.4 Operational Metrics

- Compatibility: GridFTP, XRootD, FTS, dCache, EOS remain stable
- Persistence: tuning persists across reboot; services recover
- Rollback: restore returns system to baseline behavior
- Deployment time: minutes per node (audit + apply)
- Hardware coverage: Broadcom, Mellanox, Intel NICs
- Storage scheduler selection and NUMA impact tracked

### 3.5 Monitoring Artifacts

- Transfer logs: GridFTP, XRootD, FTS
- perfSONAR historical data; iperf3 outputs
- fio, sysstat (sar)
- ethtool -S, iostat -x, ss -ti
- systemd journal (ethtool-persist, tuning apply)

## 4. Troubleshooting

### 4.1 Network Diagnostics
- perfSONAR and iperf3 (single/multi-flow); verify BBR and `fq` pacing
- Validate VLAN/bonding behavior; check packet loss/reordering (tcpdump)
- Verify NIC offloads (GRO/TSO/GSO) are configured and effective

### 4.2 Storage Diagnostics
- fio throughput/latency comparisons vs baseline
- iostat -x for queue depth and service time; watch for saturation/throttling
- dCache/XRootD/EOS logs for warnings and errors

## 5. Cost–Benefit (Scenarios & Contingency)

### 5.1 Scenarios
- Scenario A (15–20% WAN improvement, 10 PB/year): 50–60 days saved annually; recommend production deployment
- Scenario B (5–10% improvement; compatibility concerns): selective deployment; monitor stability
- Scenario C (No WAN improvement; diagnostics positive): investigate application-layer bottlenecks; defer host tuning
- Scenario D (Regression; hardware-specific): rollback; document constraint; share community notes

### 5.2 Effort & Runtime
- Personnel: ~60–70 site-hours across 4 sites (network, storage, testing, coordination)
- Infrastructure: existing hosts/connectivity; ~500 MB/site for logs
- Runtime: baselines (3–4h), diagnostics (2h), tuning + validation (1h), tuned testing (4–5h)

### 5.3 Contingency
- Immediate: restore baseline via `--restore-state`; storage rollback playbook
- Investigation: collect logs; hardware details (NIC, storage, firmware)
- Fallback: defer tuning until issue resolved; optional adoption
- Knowledge sharing: document constraints (e.g., driver limitations) for community

## 6. References

- Fasterdata tuning: docs/perfsonar/tools_scripts/fasterdata-tuning.sh
- Ansible storage scheduler/NUMA playbooks (site-specific)
