# Host Optimization and Tuning Testing

## Capability Summary

| Attribute | Value |
|-----------|-------|
| **Capability Name** | Host Optimization and Tuning (Network, Storage, CPU, Memory) |
| **Related Framework Items** | Congestion Control (BBRv3), Jumbo Frames support, Storage performance, CPU affinity |
| **Importance** | 4 (High) |
| **Urgency** | 3 (Medium) |
| **Potential Gains** | 4–5 (Significant to Major) |
| **Dependencies** | RHEL 9, 25+ Gbps NICs, NVMe/SSD storage, Linux kernel 5.x+, ethtool, tc, iostat tools |
| **Status** | Mini-Challenge 1 scheduled for January 2026 |
| **Framework Reference** | See [WLCG Capability Test Framework](https://docs.google.com/document/d/1KOExqbp5DKwtjBaVwRDJvBmGPIHiBOk5ldfNK0RQS78/edit) |

## Overview and Rationale

We evaluate comprehensive host optimizations for RHEL 9 systems with high-speed NICs (25/40/100/200/400 Gbps) and high-performance storage (NVMe/SSD, dCache, XRootD, EOS). This capability addresses **WAN (wide-area network) data transfer performance** by optimizing host-level **network**, **storage**, **CPU**, and **memory** subsystems.

**Primary Goal**: Improve site ability to transfer data across the WAN by tuning hosts to better utilize available bandwidth and reduce transfer latency.

**Scope**: Mini-Challenge 1 optimizes two host subsystems that impact WAN data transfer performance:
1. **Network Tuning** (ESnet Fasterdata recommendations): Sysctl buffers, qdisc pacing, ethtool offloads, NIC ring buffers — enables full utilization of high-speed links
2. **Storage Tuning** (New exploration): I/O scheduler selection, storage queue depth, read-ahead, NUMA affinity — reduces I/O wait that throttles data transfer throughput

**Note on Prior Work**: An earlier test of congestion control protocols (Edoardo, DC24) focused on algorithm selection alone (BBR vs CUBIC) — no gains observed. This mini-challenge expands scope to:
- **Sysctl TCP buffer tuning** (rmem/wmem scaled by link speed)
- **Qdisc packet pacing** (fq for fair scheduling, tbf for rate capping)
- **Ethtool offload optimization** (GRO/TSO/GSO tuning)
- **NIC ring buffer and txqueuelen scaling**
- **Storage I/O scheduler tuning** (ioscheduler selection for high-speed storage)
- **Storage queue depth and I/O concurrency optimization**
- **NUMA-aware memory and I/O affinity**
- **Automated audit and state management** (safe rollback via `fasterdata-tuning.sh` and storage tuning tools)

The hypothesis is that **comprehensive host optimization across all subsystems** (not individual components in isolation) provides significant WAN data transfer throughput and latency improvements, with measurable benefit for:
- **Data-intensive workflows** (HTC job input/output staging, HPC dataset transfers, AI/ML training data)
- **Site data transfer capacity** (higher effective bandwidth utilization, fewer stalled transfers)
- **Operational efficiency** (reduced transfer time, lower host CPU utilization per Gbps transferred)

## Capability Tracking Table

Per the WLCG Capability Test Framework, this table tracks all mini-challenges and their status:

| Mini-Challenge | Status | Start Date | Expected End | Key Sites | Primary Focus | Outcome |
|---|---|---|---|---|---|---|
| MC-1: Network + Storage Tuning | Planned | Jan 10, 2026 | Mar 14, 2026 | FNAL, Purdue, BNL, UCI | Network (Fasterdata), Storage I/O, CPU affinity | TBD |
| MC-2: Host Tuning + Jumbo Frames | Planned | Q2 2026 | TBD | TBD (subset MC-1 + new) | Jumbo Frames (MTU 9000), Advanced storage | TBD |

## Tracking History

This document tracks mini-challenge instances. Clone the section below for each new challenge, incrementing N.

## Participants
(Please add your name): Shawn McKee, Lincoln Bryant, Eduardo Bach, Eli Dart, Diego Davila, Garhan Attebury, Asif Shaw, Carlos Gamboa, Hiro Ito, Wendy Dronen, Philippe Laurens

**Participants & Roles**
- **Shawn McKee (AGLT2 / University of Michigan)**: Lead, test plan owner, dCache, networking and storage expert; organizing mini-capability challenges and central coordination.
- **Lincoln Bryant (U. Wisconsin)**: Testing infrastructure, automation, data analysis and result aggregation.
- **Eduardo Bach (UC San Diego / SuperCC)**: Network monitoring, dCache and network admin, results validation.
- **Eli Dart (LBNL / ESnet)**: Fasterdata and perfSONAR expert; advisory role on network tuning validation.
- **Diego Davila (UCSD / USCMS T2)**: Storage and network expert; CMS data transfer configuration and testing lead.
- **Garhan Attebury (University of Nebraska / USCMS T2)**: Network and systems expert; site proponent and test operator for Nebraska.
- **Asif Shaw (Fermilab / USCMS T1)**: CMS network and systems expert; FNAL site proponent and transfer testing lead.
- **Carlos Gamboa (BNL / USATLAS T1)**: BNL dCache manager; storage tuning and compatibility lead.
- **Hiro Ito (BNL)**: FTS and ATLAS data transfer expert; transfer orchestration and validation.
- **Wendy Dronen (AGLT2 / U. Michigan)**: System administrator and site operator at AGLT2.
- **Philippe Laurens (AGLT2 / Michigan State)**: System administrator and AGLT2 site operator.
- **Others**: Additional participants may join; list to be updated as volunteers sign up. 

# Capability Challenge 1: Comprehensive Host Optimization Testing (January 2026)

## Overview and Advantages

**Goal**: Validate comprehensive host optimization for RHEL 9 systems, including network tuning (Fasterdata), storage I/O tuning, and CPU/memory optimization. Target: high-speed NICs (25/40/100+ Gbps) and high-performance storage (NVMe/SSD).

**Expected Advantages**:
1. **Improved throughput** (5–15% for single and multi-flow transfers, 10%+ for storage-bound workloads)
2. **Reduced latency** and jitter (more predictable job scheduling, lower tail latencies)
3. **Better CPU efficiency** (lower CPU utilization per Gbps via fq pacing; improved I/O efficiency via queue tuning)
4. **Enhanced storage performance** (faster data staging, reduced I/O wait on batch jobs)
5. **Operational simplicity** (automated audit and rollback via `fasterdata-tuning.sh` and storage tuning playbooks)
6. **Hardware compatibility** (validated across Broadcom, Mellanox, Intel NICs; various storage controllers and SSDs)
7. **Production-ready tooling** (state save/restore for safe testing and deployment)

**Differentiators from Prior Work**:
- Previous congestion control test (DC24) focused on algorithm selection alone (BBR vs CUBIC)
- This challenge includes **full-stack host optimization**: sysctl, qdisc, ethtool, NIC ring buffers, **storage I/O scheduler**, **queue depth**, **NUMA affinity**
- Comprehensive approach addresses bottlenecks across network, storage, and CPU subsystems

## Plan-1: Testing Methodology and Implementation

**Primary Tools**: 
- ESnet Fasterdata tuning script (`fasterdata-tuning.sh` v1.3.1+, https://github.com/osg-htc/networking/blob/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh)
- Storage tuning playbooks and tools (Ansible for I/O scheduler, queue depth; `fio` / `iozone` for benchmarks)

## State Management: Save/Restore with `fasterdata-tuning.sh`

`fasterdata-tuning.sh` provides structured state capture and restore functionality which is central to safe A/B testing of host tuning. Key points:

- Save location: saved states are written as JSON to `/var/lib/fasterdata-tuning/saved-states/` with filenames like `<timestamp>-<label>.json` (e.g., `20251210T143000Z-baseline.json`). Backups of modified files are stored in `/var/lib/fasterdata-tuning/backups/`.
- Basic commands:
  - Save baseline state: `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline`
  - List saved states: `sudo /usr/local/bin/fasterdata-tuning.sh --list-states`
  - Show difference vs current: `sudo /usr/local/bin/fasterdata-tuning.sh --diff-state /var/lib/fasterdata-tuning/saved-states/<file>.json`
  - Restore a saved state: `sudo /usr/local/bin/fasterdata-tuning.sh --restore-state /var/lib/fasterdata-tuning/saved-states/<file>.json`
  - Auto-save before apply: `sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --auto-save-before --label pre-apply`
- What is captured: sysctl values (and `/etc/sysctl.d/90-fasterdata.conf`), per-interface settings (MTU, qdisc, txqueuelen, ethtool feature flags, ring settings), `ethtool-persist` service content, GRUB/kernel cmdline (for IOMMU/SMT), tuned profile, CPU governor/SMT state, and helpful warnings about non-restorable items.
- File format: JSON with `metadata`, `sysctl`, `interfaces`, `grub`, `tuned`, and other sections (human- and machine-readable for test automation).
- Restore caveats:
  - Restores sysctl and per-interface runtime settings and will restore persistence artifacts (sysctl file, ethtool service). Some changes (GRUB/kernel cmdline) require a reboot to take effect.
  - Ring buffer values may not be fully reversible on hardware that doesn't support previous values; the state file includes warnings.
  - Always validate a restore on a non-production node first.

Recommended usage in the test plan:
- Phase 1 (baseline): run `--save-state --label baseline` and record the saved filename in the test log.
- Phase 2 (apply): use `--mode apply --auto-save-before --label pre-apply` or run a separate `--save-state --label post-apply` after applying tuning to capture the tuned state.
- Between test iterations: use `--diff-state` to confirm only expected changes were made.
- Phase 4 (rollback and validation): run `--restore-state` with the baseline file, then verify via `--diff-state` that the system is back to baseline and re-run a short transfer test to ensure behavior returned to baseline.
- Archive the state JSON files alongside test logs for reproducibility and postmortem analysis.

Add a short verification checklist to each test run to confirm save/restore success:
- `sudo /usr/local/bin/fasterdata-tuning.sh --list-states` shows saved file
- `sudo /usr/local/bin/fasterdata-tuning.sh --diff-state <file>` shows expected diffs
- After `--restore-state <file>`, verify `sysctl -n net.core.rmem_max` (or another key) equals the baseline value and that `tc qdisc show` shows baseline qdisc
- Run a short (e.g., 10 minute) transfer to confirm baseline behavior restored

### Objectives
1. **Validate WAN data transfer performance improvement**: Measure real-world data transfer throughput and latency (GridFTP, XRootD, HTTP/WebDAV) with host tuning applied vs. baseline
2. **Validate host tuning effectiveness**: Use perfSONAR and diagnostic tools (iperf3, fio) to isolate network and storage bottlenecks
3. **Quantify host impact**: Measure CPU utilization, memory usage, and I/O wait reduction during WAN transfers
4. **Test automation reliability**: Confirm `fasterdata-tuning.sh` and storage playbooks complete without errors on production data transfer nodes
5. **Evaluate operational cost**: Assess prerequisites, deployment time, post-apply stability, resource overhead on production infrastructure (dCache, XRootD, EOS)
6. **Document best practices**: Provide deployment guidance for network, storage, and CPU/memory optimization tailored to data transfer workloads
7. **Identify site-specific constraints**: Discover hardware/firmware limitations and storage software compatibility (e.g., dCache with fq pacing, XRootD with I/O scheduler changes)
5. **Inform WLCG infrastructure decisions**: Gather evidence for whether host tuning should become a recommended best practice

### Key Considerations
- **Minimal risk**: Tuning changes are reversible; state save/restore feature enables easy rollback
- **Staged rollout**: Start with 1–2 dedicated data transfer nodes per site before broader deployment (may be production or pre-production nodes)
- **Hardware diversity**: Include varied NIC types (Broadcom, Mellanox, Intel) and bond/VLAN configurations to validate tool robustness
- **Storage infrastructure**: Sites use existing production storage (dCache, XRootD, EOS); no new storage deployment required
- **Real-world workloads**: Test WAN transfers using actual data transfer protocols and tools (GridFTP, XRootD, FTS, Rucio)
- **Baseline preservation**: Maintain unmodified reference nodes for comparison; measure baseline WAN transfer performance before tuning

### Requirements
- **Data Transfer Infrastructure**:
  - Production or pre-production data transfer nodes (GridFTP, XRootD, FTS, dCache, EOS)
  - RHEL 9.x systems with 25 Gbps or faster NICs
  - WAN connectivity to remote test endpoints (other WLCG sites or perfSONAR nodes)
  - perfSONAR nodes or testpoints for baseline network validation
  - Data transfer monitoring (FTS logs, XRootD monitoring, GridFTP logs, perfSONAR dashboards)
- **Network**:
  - Administrative access to apply sysctl, ethtool, and tc commands on data transfer nodes
  - Ability to test on production or dedicated data transfer VLANs
  - Network diagnostic tools (iperf3, netperf, ping, traceroute, mtr)
- **Storage**:
  - Existing production storage (dCache, XRootD, EOS, NFS, or direct-attached NVMe/SSD)
  - I/O scheduler change capability (change via `/sys/block/*/queue/scheduler`)
  - Storage diagnostic tools (fio, iostat, iotop)
- **General**:
  - Systems administration and storage operations time (~6–8 hours per site)
  - Centralized communication and result tracking (shared spreadsheet, git repo, weekly syncs)

### Procedure

#### Phase 1: Setup and Baseline (Week 1–2)
**WAN Data Transfer Baseline** (PRIMARY):
1. Deploy test harness on 2 USCMS + 2 USATLAS sites (4 sites total; 2 data transfer nodes per site)
2. Perform baseline WAN data transfer measurements (no tuning applied):
   - **GridFTP/FTS transfers**: 1-hour sustained transfer to remote WLCG site; measure throughput, transfer time, stalls
   - **XRootD transfers** (if available): Read/write to remote XRootD endpoint; measure throughput and latency
   - **HTTP/WebDAV** (if available): Download/upload tests to remote storage endpoint
   - **perfSONAR tests**: Automated throughput tests to remote perfSONAR nodes; validate link capacity and baseline RTT
3. Monitor host impact during baseline transfers:
   - CPU utilization (top, sar) for data transfer process and kernel I/O
   - Memory usage and TCP buffer utilization
   - I/O wait percentage (iostat, sar)
   - Network statistics (ethtool -S, retransmits, drops)
4. Capture system configuration (kernel, NIC drivers, firmware, storage software versions)
4. Save baseline state and record the saved filename (example):
   - `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline`
   - Run `sudo /usr/local/bin/fasterdata-tuning.sh --list-states` to note the saved filename (e.g., `/var/lib/fasterdata-tuning/saved-states/20251210T143000Z-baseline.json`) and include it in test logs

**Network Diagnostic Tests** (SECONDARY):
1. Run perfSONAR on-demand tests (iperf3, ping) to validate link capacity and baseline RTT
2. Single-flow and multi-flow TCP throughput (iperf3) to isolate pure network performance
3. Document any observed bottlenecks (CPU saturation, I/O wait, retransmits)

**Storage Diagnostic Tests** (SECONDARY):
1. Identify baseline I/O scheduler for storage devices (cat /sys/block/*/queue/scheduler)
2. Run fio benchmarks on storage paths used by data transfer software:
   - Sequential read/write throughput (large block sizes matching transfer tools)
   - I/O latency percentiles (p50, p95, p99)
3. Capture storage system configuration (device model, firmware, NUMA topology, dCache/XRootD/EOS configuration)

#### Phase 2: Deployment (Week 3–4)
**Network Tuning**:
1. Run audit on all network test nodes: `./fasterdata-tuning.sh --mode audit --target measurement`
2. Apply tuning on half of test nodes (one per site): `sudo ./fasterdata-tuning.sh --mode apply --target measurement`
3. Log all changes to sysctl, ethtool, and tc settings
4. Verify persistence across reboot

**Storage Tuning**:
1. For each storage device, identify best I/O scheduler for your workload (candidates: `mq-deadline`, `noop`, `bfq`):
   - Test each scheduler via: `echo "scheduler-name" | sudo tee /sys/block/*/queue/scheduler`
   - Run fio benchmarks (same tests as baseline) and compare results
2. Select tuned I/O scheduler based on performance and latency results
3. Apply tuned scheduler to half of storage test nodes (one per site)
4. Optionally apply NUMA affinity (if storage controller visible in numa topology): `numactl -m N -C N fio [test]`
5. Document selected scheduler and any NUMA settings

#### Phase 3: Performance Testing (Week 5–7, overlaps Phase 2)
**WAN Data Transfer Performance Testing** (PRIMARY - weekly, 2–3 iterations per configuration):
1. Real-world data transfer tests:
   - **GridFTP/FTS transfers**: 1–2 hour sustained transfers to remote WLCG sites; measure throughput improvement vs. baseline
   - **XRootD transfers**: Read/write to remote endpoints; measure throughput and latency improvement
   - **HTTP/WebDAV**: Upload/download tests; measure throughput and transfer time reduction
   - **perfSONAR automated tests**: Scheduled throughput tests to validate link utilization improvement
2. Host impact measurements (compare tuned vs. baseline):
   - CPU utilization during transfers (should decrease with tuning)
   - I/O wait percentage (should decrease with storage tuning)
   - Memory usage and TCP buffer efficiency
   - Network retransmits and packet loss (should stay low or decrease)
3. Data transfer software validation:
   - Verify GridFTP/XRootD/FTS continue to operate correctly with tuning applied
   - Check for compatibility issues with dCache/XRootD/EOS and fq pacing or I/O scheduler changes
   - Monitor transfer logs for errors or performance warnings
4. Stability and long-duration testing:
   - Run multi-hour transfers (4+ hours) to detect stability issues
   - Monitor system logs (dmesg, syslog) for errors
   - Verify no service restarts or transfer failures

**Global Configuration Sweep (synchronized across all sites)**:

Purpose: Measure the end-to-end impact when all data transfer hosts are placed on the same configuration, then change the entire fleet to a different configuration and repeat the measurements. This avoids partial-path inconsistencies and better isolates host-level effects on WAN transfers.

Steps:
1. **Prepare configuration variants**: Define the configurations to compare (e.g., `baseline` (stock), `network-tuned` (Fasterdata apply with fq), `network+storage-tuned` (Fasterdata + I/O scheduler), `tbf-cap` (tbf cap + storage tune)). Document the exact commands/playbooks used to apply each.
2. **Record baseline**: On every test host, save baseline state and record filenames:
   - `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline`
   - Use `sudo /usr/local/bin/fasterdata-tuning.sh --list-states` and save the returned filenames centrally (one per host).
3. **Apply configuration to all hosts**: Use an orchestration tool (Ansible recommended) to run the apply on all data-transfer nodes simultaneously or in a controlled batch. Example Ansible ad-hoc:

```bash
ansible data-transfer -i inventory -m shell -a "sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --apply-packet-pacing --yes"
```

For storage changes use an Ansible playbook that sets `/sys/block/*/queue/scheduler` and any NUMA affinity settings.
4. **Confirm successful apply**: On all hosts, run an audit to verify the expected changes are in place and collect JSON output to central logging:
   - `ansible data-transfer -m shell -a "sudo /usr/local/bin/fasterdata-tuning.sh --mode audit --json" -o > audit-outputs/<config>-audit.json`
5. **Run synchronized WAN transfers**: Coordinate start times (within 1 minute) across sites and run the signed transfer jobs (GridFTP/FTS/XRootD) for the defined duration. Collect per-host and transfer-system logs.
6. **Save tuned state**: After verification and before heavy testing, save the tuned state on each host:
   - `sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label network-tuned`
7. **Repeat for each configuration**: Restore baseline or apply the next configuration across all hosts and repeat steps 4–6. For restore between configs use `--restore-state` with the recorded baseline file or the appropriate saved-state file for that configuration.
8. **Aggregate and compare**: For each configuration, run at least 3 iterations of the transfer tests; aggregate results, compute means and 95% confidence intervals, and perform paired comparisons between configurations to detect statistically significant differences.

Verification checklist for each global sweep:
- All hosts report the expected audit results (`--mode audit --json`) for the current configuration
- Saved state files are present and recorded centrally for each host
- Transfer job start times are synchronized (within 1 minute) across all sites
- Logs (GridFTP, XRootD, FTS, perfSONAR, host metrics) are collected and archived under `logs/<config>/`
- After restore, a short transfer confirms baseline behavior

Notes and cautions:
- Always test restores on non-production nodes first. If GRUB/cmdline changes are present, schedule a reboot window and test restores with coordination to avoid service disruption.
- If any host cannot restore to its previous ring buffer values, document the limitation and exclude the host from the cross-configuration comparison or mark it as a special-case in the analysis.


**Network Diagnostic Tests** (SECONDARY - for troubleshooting):
1. perfSONAR on-demand tests (iperf3) to isolate network performance:
   - Single-flow and multi-flow TCP throughput
   - Verify BBR congestion control is active and performing correctly
   - Confirm fq qdisc packet pacing without breaking VLAN/bond interfaces
2. Network protocol validation:
   - Check for unexpected packet loss or reordering (tcpdump sampling)
   - Verify NIC offloads (GRO/TSO/GSO) are functioning correctly

**Storage Diagnostic Tests** (SECONDARY - for troubleshooting):
1. Run fio benchmarks to isolate storage performance changes:
   - Compare sequential read/write throughput to baseline
   - Measure I/O latency improvement with tuned I/O scheduler
2. Monitor storage subsystem during data transfers:
   - iostat -x for I/O queue depth and service time
   - Verify no storage bottlenecks (queue saturation, throttling)
   - Check dCache/XRootD/EOS logs for storage-related warnings

#### Phase 4: Cost/Risk Assessment (Week 8)
**Network Assessment**:
1. Document time to apply network tuning per site (includes audit, apply, testing)
2. Quantify resource overhead (CPU for fq qdisc, memory for larger TCP buffers)
3. Identify any compatibility issues (driver bugs, performance regressions, bond/VLAN issues)
4. Test rollback procedure:
   - Restore baseline state: `sudo /usr/local/bin/fasterdata-tuning.sh --restore-state /var/lib/fasterdata-tuning/saved-states/<baseline-file>.json`
   - Confirm restoration with `sudo /usr/local/bin/fasterdata-tuning.sh --diff-state /var/lib/fasterdata-tuning/saved-states/<baseline-file>.json` (should show no unexpected diffs)
   - Reboot if GRUB/kernel cmdline changes were recorded in the state and required for full restoration
   - Run a short WAN transfer to verify transfer behavior returned to baseline and log the results

**Storage Assessment**:
1. Document time to identify and apply best I/O scheduler per site
2. Quantify resource overhead (CPU for scheduler changes, memory for queue depth tuning)
3. Identify hardware constraints (e.g., "Scheduler X not supported on this NVMe firmware")
4. Test rollback procedure:
   - Restore baseline I/O scheduler and configuration (use site tools or `echo "<scheduler>" | sudo tee /sys/block/*/queue/scheduler`)
   - Confirm that storage settings match the captured baseline (compare fio short-run results and `iostat -x` metrics)
   - If a storage change required kernel/module reload or other action, document the steps and validate with a short transfer test

#### Phase 5: Analysis and Reporting (Week 9–10)
1. Aggregate results across 4 sites
2. Calculate throughput/latency improvements (statistical significance testing)
3. Produce site-specific and aggregate reports
4. Recommendations for production deployment

## Metrics-1: Measurements and Monitoring

### Primary Metrics: WAN Data Transfer Performance
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **GridFTP/FTS throughput** | Real transfers to remote sites | Baseline + 10–15% | Significant improvement |
| **XRootD transfer throughput** | XRootD read/write to remote endpoint | Baseline + 10% | Improvement or stable |
| **HTTP/WebDAV throughput** | Upload/download to remote storage | Baseline + 10% | Improvement or stable |
| **perfSONAR throughput** | Automated tests to remote nodes | Link capacity - 5% | Near-line-rate utilization |
| **Transfer completion time** | GridFTP/FTS transfer duration | Baseline - 10% | Faster transfers |
| **CPU utilization during transfer** | top, sar (during WAN transfer) | <70% at saturation | Improved efficiency |
| **I/O wait during transfer** | iostat, sar (%iowait) | <20% during transfer | Storage not bottleneck |
| **Network retransmits** | ss -ti, ethtool -S | <0.01% of packets | Stable or improved |

### Secondary Metrics: Network Diagnostic Tests (perfSONAR, iperf3)
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **Single-flow throughput** | iperf3 -t 3600 (1 hour) | Baseline + 10% | Improvement or no regression |
| **Multi-flow throughput** | iperf3 -P 10 (10 parallel) | Baseline + 5% | Improvement or no regression |
| **RTT latency** | perfSONAR ping, iperf3 | Stable vs. baseline | No degradation |
| **Memory usage (TCP buffers)** | /proc/meminfo | <5% of system RAM | Acceptable overhead |

### Secondary Metrics: Storage Diagnostic Tests (fio)
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **Sequential read throughput** | fio (seq-read, direct I/O) | Baseline + 5% | Improvement or stable |
| **Sequential write throughput** | fio (seq-write, direct I/O) | Baseline + 5% | Improvement or stable |
| **I/O latency (p50, p99)** | fio (latency histogram) | <10ms (p50) | Stable or improved |
| **I/O queue depth utilization** | iostat -x (avgqu-sz) | Optimized per scheduler | No bottleneck |

### Operational Metrics
- **Data transfer software compatibility**: GridFTP, XRootD, FTS, dCache, EOS operate correctly with tuning
- **Reboot safety**: Tuning persists correctly post-reboot; transfers resume without manual intervention
- **Rollback success**: State restore returns system to baseline; data transfer performance returns to baseline
- **Deployment time**: Minutes to complete audit and apply tuning on a data transfer node
- **Hardware compatibility**: Pass audit on 100% of tested NIC types (Broadcom, Mellanox, Intel) and storage backends
- **Storage I/O scheduler selection**: Optimal scheduler documented for dCache, XRootD, EOS on different storage hardware
- **NUMA affinity impact**: Measure WAN transfer performance change with I/O process affinity to storage controller NUMA node

### Monitoring Infrastructure
- **Data transfer logs**: GridFTP transfer logs, XRootD monitoring, FTS dashboard, dCache/EOS admin logs
- **perfSONAR**: Automated throughput tests and historical performance data
- **iperf3/netperf**: Network diagnostic tests for troubleshooting
- **fio**: Storage diagnostic tests for troubleshooting I/O bottlenecks
- **sysstat** (sar): CPU, memory, I/O wait, context switches during transfers
- **ethtool -S**: NIC statistics (errors, drops, retransmits)
- **iostat -x**: Storage I/O queue depth, service time, utilization
- **ss -ti**: TCP connection statistics (retransmits, congestion window)
- **systemd journal**: ethtool-persist service logs and tuning application errors

## Cost-Benefit-1: Cost and Benefit Analysis

### Benefit Estimation
1. **WAN data transfer throughput improvement**: If baseline GridFTP transfer is 15 Gbps and tuning achieves 18 Gbps (20% gain on 100 Gbps link):
   - Benefit = `(18 - 15) / 15 × 100 = 20% faster WAN transfers`
   - Operational impact: For a site transferring 10 PB/year, this saves ~60 days of transfer time annually
   - Cost savings: Reduced transfer duration = lower risk of transfer failures, faster job turnaround
2. **Host efficiency improvement**: Lower CPU utilization and I/O wait during transfers:
   - Benefit: More headroom for concurrent transfers and batch jobs on same host
   - Operational impact: Can increase number of concurrent FTS transfers per node by 10–15%
3. **Storage-bound workload improvement**: If storage I/O is bottleneck, tuning can improve WAN transfer by reducing I/O wait:
   - Benefit: Transfers no longer stalled waiting for storage read/write
   - Example: XRootD reads complete faster → higher sustained transfer rate
4. **Latency reduction**: Lower jitter and fewer retransmissions enable more stable high-speed transfers:
   - Benefit: Fewer transfer failures and restarts
   - Operational impact: Improved success rate for large (multi-TB) file transfers
5. **Combined impact (network + storage)**: For sites with both network and storage tuning, WAN transfer improvements of 15–25% are achievable

### Cost Estimation
1. **Personnel**: 
   - Site admins (network tuning): 3–4 hours per site for tuning application and WAN transfer testing
   - Site storage operations (storage tuning): 2–3 hours per site for I/O scheduler selection and validation
   - Site data transfer team: 2–3 hours per site for GridFTP/XRootD/FTS testing and log analysis
   - Central team: 8–12 hours for test coordination, perfSONAR setup, result analysis
   - **Total: ~60–70 site-hours across 4 sites**
2. **Infrastructure**: 
   - Use existing production or pre-production data transfer nodes (GridFTP, XRootD, dCache, EOS)
   - Use existing perfSONAR nodes for baseline validation
   - Use existing WAN connectivity to remote WLCG sites
   - Storage for transfer logs and baseline captures (~500 MB per site)
   - **No new hardware or network infrastructure required**
3. **Runtime**: 
   - WAN transfer baseline testing: 3–4 hours per site (includes multiple transfer tests)
   - Network and storage diagnostic baseline: 2 hours per site
   - Tuning application and reboot validation: 1 hour per site
   - Tuned WAN transfer testing: 4–5 hours per site (includes multiple transfer iterations)
   - Total test runtime: ~4 weeks (overlapping phases, allowing time for scheduled WAN transfers)

### Tools and Cost
- **Network tuning tools**: `fasterdata-tuning.sh` (open-source, free)
- **Storage benchmarking tools**: `fio`, `iozone`, `bonnie++` (open-source, free)
- **System analysis tools**: `iostat`, `ethtool`, `numactl` (standard RHEL 9, free)
- **Automation**: Ansible playbooks for storage tuning (to be developed; ~4 hours effort)

### Cost-Benefit Comparison
- **Scenario A (WAN transfer 15–20% improvement, 10 PB/year site)**:
  - Benefit: 15–20% faster WAN transfers = 1.5–2 PB more data transferred in same time window OR 50–60 days saved annually
  - Cost: ~60–70 site-hours for testing + tuning deployment; amortized over 1 year = negligible
  - **Recommendation: Deploy to production data transfer nodes**
  
- **Scenario B (WAN transfer 5–10% improvement, storage software compatibility concerns)**:
  - Benefit: Modest WAN transfer improvement; may require monitoring for dCache/XRootD stability
  - Cost: As above + ongoing monitoring overhead
  - **Recommendation: Selective deployment; document constraints (e.g., "dCache pool nodes need specific fq settings"); deploy where stable**

- **Scenario C (No WAN transfer improvement observed, but diagnostic tests show gains)**:
  - Benefit: iperf3 shows improvement but real transfers don’t → bottleneck elsewhere (application layer, remote site, storage backend)
  - Cost: As above
  - **Recommendation: Document findings; investigate application-layer bottlenecks; defer host tuning until root cause identified**

- **Scenario D (Site-specific hardware issue: regression observed)**:
  - Benefit: None; specific NIC or storage controller incompatible with tuning
  - Cost: As above + troubleshooting time
  - **Recommendation: Rollback immediately; document hardware constraint; share with community for awareness**

### Contingency
If a site observes instability, performance regression, or compatibility issues:
- **Immediate action**: Restore baseline state using `--restore-state` feature of fasterdata-tuning.sh and storage rollback playbook
- **Investigation**: Capture logs and hardware details (NIC model, storage device, firmware versions) for root cause analysis
- **Fallback**: Tuning is optional; sites can defer deployment until issue is resolved or workaround is identified
- **Knowledge sharing**: Document site-specific constraints (e.g., "Broadcom BCM5719 driver does not support fq pacing") for the community


## Schedule-1: Timeline (January 2026)

| Phase | Duration | Dates | Deliverables |
|-------|----------|-------|--------------|
| **Planning & Coordination** | 1 week | Jan 1–10 | Site participant list, test plan review, hardware inventory |
| **Setup & Baseline** | 2 weeks | Jan 10–24 | Baseline measurements, system configs captured, baseline states saved |
| **Deployment & Testing** | 4 weeks | Jan 24–Feb 21 | Tuning applied, weekly test runs, logs and raw data collected |
| **Analysis & Reporting** | 2 weeks | Feb 21–Mar 7 | Results aggregated, cost-benefit analysis, final report |
| **Presentation** | 1 week | Mar 7–14 | Summary slides for WLCG/LHCONE meetings |

**Key Milestones**:
- Jan 10: Participant kickoff call
- Jan 24: All sites ready for testing
- Feb 7: Interim results discussion
- Mar 14: Final presentation at next WLCG or LHCONE meeting

## Team-1: Participants and Responsibilities

### Central Coordination
- **Shawn McKee (U. Michigan / AGLT2)**: Lead, test plan owner, dCache, network and storage tuning expert; main organizer and contact for mini-challenge logistics
- **Lincoln Bryant (U. Wisconsin)**: Testing infrastructure, automation, data aggregation and analysis; test harness lead
- **Eduardo Bach (UC San Diego / SuperCC)**: Network monitoring, perfSONAR coordination and results validation; dCache and network admin
- **Eli Dart (LBNL / ESnet)**: Fasterdata advisor, perfSONAR and network tuning validation
- **Diego Davila (UCSD / USCMS T2)**: Storage and CMS data transfer expert; assists with transfer-job setup and validation
- **Hiro Ito (BNL)**: FTS and transfer orchestration expert; advisor for ATLAS transfer testing

### USCMS Sites (2 sites)
1. **T1 Site (Fermilab)**
   - **Network Proponent**: Asif Shaw (FNAL)
   - **Storage/Data Transfer Proponent**: [Site storage or data transfer engineer]
   - **Responsibilities**: 
     - Deploy network tuning on 2 data transfer nodes (production or pre-production)
     - Baseline and tuned WAN transfer tests: GridFTP/FTS to remote T1/T2 sites, perfSONAR validation
     - Storage tuning: Identify and apply best I/O scheduler for GridFTP backends
     - Monitor host impact: CPU, I/O wait, retransmits during WAN transfers
     - Document compatibility and any site-specific constraints
   - **Effort**: ~7–8 hours per site
   
2. **T2 Site (Purdue)**
   - **Network Proponent**: [Site admin name]
   - **Storage/Data Transfer Proponent**: [Site storage or data transfer engineer]
   - **Responsibilities**: 
     - Same as Fermilab; focus on XRootD or HTTP-based transfers if dCache not used
     - Explore NUMA-aware tuning for data transfer processes if applicable
     - Test multi-flow WAN transfers (concurrent FTS jobs) to validate tuning under load
   - **Effort**: ~7–8 hours per site

### USATLAS Sites (2 sites)
1. **T1 Site (BNL)**
   - **Network Proponent**: [Site admin name]
   - **Storage/Data Transfer Proponent**: Carlos Gamboa (BNL)
   - **Responsibilities**: 
     - Deploy on 2 data transfer nodes; focus on stability and rollback validation
     - Baseline and tuned WAN transfer tests: XRootD, GridFTP, or Rucio/FTS transfers to remote sites
     - Storage tuning: Test I/O scheduler options for EOS or dCache storage backend
     - Collaborate with Hiro Ito for FTS orchestration and ATLAS-specific transfer validation
     - Extensive error log collection for dCache/XRootD compatibility analysis
     - Validate rollback procedure does not disrupt production transfers
   - **Effort**: ~7–8 hours per site
   
2. **T2 Site (UC Irvine)**
   - **Network Proponent**: [Site admin name]
   - **Storage/Data Transfer Proponent**: [Site storage or data transfer engineer]
   - **Responsibilities**: 
     - Same as BNL; additional focus on hardware compatibility (mixed NIC types, storage controllers)
     - Document firmware-specific constraints for I/O schedulers or fq pacing
     - Test WAN transfers with tuning on mixed hardware to validate portability
   - **Effort**: ~7–8 hours per site

### Advisory Committee
- **Eli Dart (LBNL/ESnet)**: Network tuning (Fasterdata) validation and guidance; perfSONAR expertise
- **Dale Carder (LBNL)**: Storage and network architecture guidance
- **Hiro Ito (BNL)**: FTS and ATLAS transfer orchestration and validation
- **[TBD WLCG Data Transfer Expert]**: GridFTP, XRootD, FTS, and Rucio expertise; data transfer best practices
- **[TBD Storage Software Expert]**: dCache, XRootD, EOS tuning and compatibility guidance
- **Additional WLCG Network Operations, Storage, and Data Management contacts** as needed

### Communication
- **Weekly syncs**: Mondays 2 PM ET during active testing phases (Jan–Mar 2026)
- **Shared spreadsheet**: Track WAN transfer tests, measurement results (GridFTP/XRootD throughput, perfSONAR tests, host CPU/I/O wait), issues, and blockers
- **Central repo**: All logs (GridFTP, XRootD, FTS, perfSONAR, fio, iperf3), scripts, Ansible playbooks, and analysis pushed to `/root/Git-Repositories/networking/` branch `mini-challenge-1`
- **Escalation**: Any blocker (transfer failures, data corruption, dCache/XRootD errors, driver bug) reported immediately to central coordination team
- **Data transfer dashboards**: Use existing FTS, perfSONAR, and site monitoring dashboards to track real-time performance

## Evaluation Criteria-1: Success Metrics and Decision Framework

### Success Criteria
1. ✅ **Data quality**: Baseline and tuned measurements completed for ≥80% of planned test cycles (network and storage)
2. ✅ **No regressions**: Throughput does not decrease by >5% after tuning; latency does not increase by >10% (or isolated to specific hardware)
3. ✅ **Stability**: All nodes complete test phases without unplanned reboots or service errors
4. ✅ **Reproducibility**: Tuning changes are consistently applied and measured across all sites
5. ✅ **Cost acceptable**: Total site effort ≤25 hours per site (network + storage)
6. ✅ **Storage insights**: I/O scheduler recommendations documented for each site's hardware

### Go/No-Go Decision Framework
- **Go for production recommendation**: If ≥2 sites show ≥5% improvement in network throughput OR ≥5% improvement in storage I/O, with no major regressions
- **Conditional recommendation**: If improvement is site-specific or hardware-specific (e.g., NVMe benefits from noop, SSD from mq-deadline); recommend per-site evaluation and document constraints
- **Partial recommendation**: If only network OR only storage shows improvement; recommend for the subsystem showing gains; defer other pending resolution
- **No recommendation**: If no improvement observed or significant regressions encountered; document findings and defer for future kernel/driver versions

## Results-1: Summary and Follow-Up

*To be completed by March 14, 2026.*

- **Aggregate WAN data transfer throughput improvement**: [TBD] (GridFTP, XRootD, FTS)
- **perfSONAR throughput improvement**: [TBD]
- **Host efficiency improvement** (CPU utilization, I/O wait reduction): [TBD]
- **Sites deploying network tuning to production**: [TBD]
- **Sites deploying storage tuning to production**: [TBD]
- **Data transfer software compatibility findings**: [TBD] (dCache, XRootD, EOS, GridFTP, FTS)
- **Key lessons learned**: [TBD]
- **I/O scheduler recommendations by storage software and hardware**: [TBD]
- **NUMA affinity impact on WAN transfers**: [TBD]
- **Recommended next steps**: [TBD]
- **Full report location**: `/root/Git-Repositories/networking/docs/reports/mini-challenge-1-final-report.md` (or similar)


# Capability Challenge N+1

…