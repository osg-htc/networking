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

We evaluate comprehensive host optimizations for RHEL 9 systems with high-speed NICs (25/40/100/200/400 Gbps) and high-performance storage (NVMe/SSD). This capability addresses end-to-end data movement performance by optimizing **network**, **storage**, **CPU**, and **memory** subsystems.

**Scope**: Mini-Challenge 1 focuses on two primary areas:
1. **Network Tuning** (ESnet Fasterdata recommendations): Sysctl buffers, qdisc pacing, ethtool offloads, NIC ring buffers
2. **Storage Tuning** (New exploration): I/O scheduler selection, storage queue depth, read-ahead, NUMA affinity for storage controllers

**Note on Prior Work**: An earlier test of congestion control protocols (Edoardo, DC24) focused on algorithm selection alone (BBR vs CUBIC) — no gains observed. This mini-challenge expands scope to:
- **Sysctl TCP buffer tuning** (rmem/wmem scaled by link speed)
- **Qdisc packet pacing** (fq for fair scheduling, tbf for rate capping)
- **Ethtool offload optimization** (GRO/TSO/GSO tuning)
- **NIC ring buffer and txqueuelen scaling**
- **Storage I/O scheduler tuning** (ioscheduler selection for high-speed storage)
- **Storage queue depth and I/O concurrency optimization**
- **NUMA-aware memory and I/O affinity**
- **Automated audit and state management** (safe rollback via `fasterdata-tuning.sh` and storage tuning tools)

The hypothesis is that **comprehensive host optimization across all subsystems** (not individual components in isolation) provides significant throughput and latency improvements, with measurable benefit for data-intensive workflows (HTC, HPC, AI/ML).

## Capability Tracking Table

Per the WLCG Capability Test Framework, this table tracks all mini-challenges and their status:

| Mini-Challenge | Status | Start Date | Expected End | Key Sites | Primary Focus | Outcome |
|---|---|---|---|---|---|---|
| MC-1: Network + Storage Tuning | Planned | Jan 10, 2026 | Mar 14, 2026 | FNAL, Purdue, BNL, UCI | Network (Fasterdata), Storage I/O, CPU affinity | TBD |
| MC-2: Host Tuning + Jumbo Frames | Planned | Q2 2026 | TBD | TBD (subset MC-1 + new) | Jumbo Frames (MTU 9000), Advanced storage | TBD |

## Tracking History

This document tracks mini-challenge instances. Clone the section below for each new challenge, incrementing N.

## Participants
(Please add your name): Shawn McKee, Lincoln Bryant, Eduardo Bach, Eli Dart, 

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

### Objectives
1. **Validate network tuning effectiveness**: Measure throughput and latency improvements with Fasterdata tuning applied vs. baseline
2. **Validate storage tuning effectiveness**: Measure storage I/O throughput and latency with tuning applied vs. baseline
3. **Test automation reliability**: Confirm `fasterdata-tuning.sh` and storage playbooks complete without errors across diverse hardware
4. **Evaluate operational cost**: Assess prerequisites, deployment time, post-apply stability, resource overhead
5. **Document best practices**: Provide deployment guidance for network, storage, and CPU/memory optimization
6. **Identify site-specific constraints**: Discover hardware/firmware limitations (e.g., NIC driver bugs, storage controller limits)
5. **Inform WLCG infrastructure decisions**: Gather evidence for whether host tuning should become a recommended best practice

### Key Considerations
- **Minimal risk**: Tuning changes are reversible; state save/restore feature enables easy rollback
- **Staged rollout**: Start with 1–2 dedicated test nodes per site before broader deployment
- **Hardware diversity**: Include varied NIC types (Broadcom, Mellanox, Intel) and bond/VLAN configurations to validate tool robustness
- **Network isolation**: Test data transfers occur on dedicated test networks to avoid production impact
- **Baseline preservation**: Maintain unmodified reference nodes for comparison

### Requirements
- **Network**:
  - RHEL 9.x systems with 25 Gbps or faster NICs
  - Dedicated test network or isolated VLAN for data transfer tests
  - Data transfer tools (iperf3, iperf, gridftp) and monitoring infrastructure (netflow, packet sniffers)
  - Administrative access to apply sysctl, ethtool, and tc commands
- **Storage**:
  - RHEL 9.x systems with NVMe or SSD storage
  - Dedicated storage test paths (can be on shared storage, isolated by filesystem mount point)
  - Storage benchmarking tools (fio, iozone, bonnie++)
  - I/O scheduler change capability (change via `/sys/block/*/queue/scheduler`)
  - Monitoring infrastructure (iostat, pmdk/ndctl for NVMe, custom I/O profiling if desired)
- **General**:
  - Systems administration time for coordination and troubleshooting (~5–6 hours per site)
  - Centralized communication and result tracking mechanism (shared spreadsheet, git repo)

### Procedure

#### Phase 1: Setup and Baseline (Week 1–2)
**Network Testing**:
1. Deploy network test harness on 2 USCMS + 2 USATLAS sites (4 sites total; 2 nodes per site)
2. Perform network baseline measurements (no tuning applied):
   - Single-flow and multi-flow TCP throughput (iperf3)
   - Latency and jitter percentiles (iperf3 histogram)
   - CPU utilization and context switches (top, /proc/stat)
   - Memory footprint and cache misses (sysstat, perf)
3. Capture network system configuration (kernel, NIC drivers, firmware versions, ethtool -i)
4. Save network baseline state using `fasterdata-tuning.sh --save-state`

**Storage Testing**:
1. Identify baseline I/O scheduler for each storage device (cat /sys/block/*/queue/scheduler)
2. Perform storage baseline measurements (existing I/O scheduler):
   - Sequential read throughput (fio seq-read, direct I/O, large block size)
   - Random read IOPS and latency (fio rand-read, 4K blocks, percentiles)
   - Sequential write throughput (fio seq-write, direct I/O)
   - Write latency (fio, percentiles)
3. Capture storage system configuration (device model, firmware, NUMA topology, queue depth settings)
4. Document baseline I/O scheduler and any custom queue settings

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
**Network Testing** (weekly, 3 iterations per configuration):
1. Data transfer tests:
   - 1-hour sustained single-flow TCP transfer (iperf3)
   - 10 parallel flows (iperf3) to simulate production workload
   - GridFTP transfers (if available) to test real application behavior
2. Network protocol validation:
   - Verify BBR congestion control is active and behaving correctly
   - Confirm fq qdisc packet pacing without breaking VLAN/bond interfaces
   - Check for unexpected packet loss or reordering
3. System stability:
   - Monitor dmesg for errors or warnings
   - Check for NIC resets or driver issues
   - Verify no memory leaks in long-running tests

**Storage Testing** (weekly, 2–3 iterations per configuration):
1. Run same fio benchmarks as Phase 1 baseline:
   - Sequential read/write throughput
   - Random read IOPS and latency (percentiles)
   - Compare to baseline for same scheduler
   - Compare different schedulers for same device
2. Monitor storage system during tests:
   - iostat -x for I/O queue depth, service time
   - Check for throttling or command queue saturation
   - Verify data integrity (md5sum checks on read/write cycles)
3. Longer-duration stability test:
   - Run fio for 4+ hours to detect memory leaks or stalls in I/O subsystem
   - Monitor kernel logs for storage errors or timeouts

#### Phase 4: Cost/Risk Assessment (Week 8)
**Network Assessment**:
1. Document time to apply network tuning per site (includes audit, apply, testing)
2. Quantify resource overhead (CPU for fq qdisc, memory for larger TCP buffers)
3. Identify any compatibility issues (driver bugs, performance regressions, bond/VLAN issues)
4. Test rollback procedure: restore network baseline state and verify transfer performance returns to baseline

**Storage Assessment**:
1. Document time to identify and apply best I/O scheduler per site
2. Quantify resource overhead (CPU for scheduler changes, memory for queue depth tuning)
3. Identify hardware constraints (e.g., "Scheduler X not supported on this NVMe firmware")
4. Test rollback procedure: restore baseline I/O scheduler and verify I/O performance returns to baseline

#### Phase 5: Analysis and Reporting (Week 9–10)
1. Aggregate results across 4 sites
2. Calculate throughput/latency improvements (statistical significance testing)
3. Produce site-specific and aggregate reports
4. Recommendations for production deployment

## Metrics-1: Measurements and Monitoring

### Primary Network Metrics
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **Single-flow throughput** | iperf3 -t 3600 (1 hour) | Baseline + 10% | Improvement or no regression |
| **Multi-flow throughput** | iperf3 -P 10 (10 parallel) | Baseline + 5% | Improvement or no regression |
| **Latency (p50, p95, p99)** | iperf3 histogram or netperf | <100μs (p50) | Stable or improved |
| **CPU utilization** | top, /proc/stat | <80% at saturation | Tuning does not create bottleneck |
| **Memory usage (TCP buffers)** | /proc/meminfo | <5% of system RAM | Acceptable overhead |

### Primary Storage Metrics
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **Sequential read throughput** | fio (seq-read, direct I/O) | Baseline + 5% | Improvement or stable |
| **Random read IOPS** | fio (rand-read, 4K blocks) | Baseline + 5% | Improvement or stable |
| **Read latency (p50, p99)** | fio (latency histogram) | <5ms (p50) | Stable or improved |
| **Sequential write throughput** | fio (seq-write, direct I/O) | Baseline + 5% | Improvement or stable |
| **Write latency (p50, p99)** | fio (latency histogram) | <10ms (p50) | Stable or improved |
| **I/O queue depth utilization** | iostat -x (avgqu-sz) | Optimized per scheduler | No bottleneck |

### Secondary Metrics
- **Network packet loss rate**: Goal <0.01% over sustained transfers
- **Network reboot safety**: Tuning persists correctly post-reboot without errors
- **Network rollback success**: State restore returns system to baseline state exactly
- **Storage I/O scheduler performance**: Compare mq-deadline vs noop vs bfq for your workload
- **Network deployment time**: Minutes to complete audit and apply on a node
- **Network hardware compatibility**: Pass audit on 100% of tested NIC types (Broadcom, Mellanox, Intel)
- **Storage NUMA affinity impact**: Measure latency change when I/O processes are affinized to storage controller NUMA node
- **Filesystem cache effectiveness**: Monitor dirty pages, writeback latency, sync stalls

### Monitoring Infrastructure
- **netperf** or **iperf3** for throughput and latency
- **ifstat** / **ethtool -S** for NIC statistics (errors, drops, retransmits)
- **sysstat** (sar) for CPU, memory, context switches
- **tcpdump** for packet-level inspection (sample-based, not full packet capture)
- **systemd journal** for ethtool-persist service logs and errors

## Cost-Benefit-1: Cost and Benefit Analysis

### Benefit Estimation
1. **Network throughput improvement**: If baseline is 18 Gbps and tuning achieves 20 Gbps (11% gain):
   - Benefit = `(20 - 18) / 18 × 100 = 11% faster data transfers`
   - Operational impact: ~10% reduction in transfer time for long-running jobs
2. **Storage I/O improvement**: If baseline is 500 MB/s and storage tuning achieves 550 MB/s (10% gain):
   - Benefit = `(550 - 500) / 500 × 100 = 10% faster I/O-bound workloads`
   - Operational impact: Data staging time reduced; job turnaround improved for storage-heavy workflows
3. **CPU efficiency**: Lower CPU utilization per Gbps + per IOPS translates to reduced power consumption and headroom for job scheduling
4. **Latency reduction**: Lower jitter enables more predictable job scheduling and fewer retransmissions
5. **Combined impact (network + storage)**: For workflows with both network and storage bottlenecks, combined tuning can deliver 15%+ improvement

### Cost Estimation
1. **Personnel**: 
   - Site admins (network tuning): 2–4 hours per site for initial setup and monitoring
   - Site admins (storage tuning): 2–3 hours per site for I/O scheduler selection, NUMA affinity exploration
   - Central team: 6–10 hours for test harness setup, coordination, analysis
   - **Total: ~50 site-hours across 4 sites**
2. **Infrastructure**: 
   - Dedicated test NICs or VLANs (typically already available at HPC sites)
   - Test storage paths on existing storage (no new hardware required)
   - Storage for baseline captures and test logs (~200 MB per site)
3. **Runtime**: 
   - Network baseline testing: 2 hours per node (0.5 days for all 8 nodes)
   - Storage baseline testing: 2 hours per node (0.5 days for all 8 nodes)
   - Tuned network testing: 3 hours per node (0.75 days for 4 tuned nodes)
   - Tuned storage testing: 3 hours per node (0.75 days for 4 tuned nodes)
   - Total test runtime: ~3 weeks (overlapping phases)

### Tools and Cost
- **Network tuning tools**: `fasterdata-tuning.sh` (open-source, free)
- **Storage benchmarking tools**: `fio`, `iozone`, `bonnie++` (open-source, free)
- **System analysis tools**: `iostat`, `ethtool`, `numactl` (standard RHEL 9, free)
- **Automation**: Ansible playbooks for storage tuning (to be developed; ~4 hours effort)

### Cost-Benefit Comparison
- **Scenario A (Network 10% + Storage 8% improvement, 10 PB/year data)**:
  - Benefit: Faster transfers + faster staging = ~10–15% overall improvement in data movement time
  - Cost: ~50 site-hours + automation development (~4 hours); amortized over 1 year = negligible
  - **Recommendation: Deploy**
  
- **Scenario B (Network 5% + Storage 3%, but high stability concern)**:
  - Benefit: Modest improvement with monitoring overhead
  - Cost: As above
  - **Recommendation: Selective deployment; identify constraints and resolve before wider rollout**

- **Scenario C (No improvement observed)**:
  - Benefit: Validation that RHEL 9 + modern storage defaults are adequate; knowledge benefit
  - Cost: As above
  - **Recommendation: Document findings; do not mandate; continue monitoring for future kernel/driver improvements**

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
- **Shawn McKee (U. Michigan)**: Lead, test plan owner, network tuning (fasterdata-tuning.sh) expert
- **Lincoln Bryant (U. Wisconsin)**: Testing infrastructure, data analysis, automation
- **Eduardo Bach (UC San Diego/SuperCC)**: Network monitoring, results validation
- **TBD (Storage Expert)**: Storage tuning lead, I/O scheduler and benchmark tool expert

### USCMS Sites (2 sites)
1. **T1 Site (Fermilab)**
   - **Network Proponent**: [Site admin name]
   - **Storage Proponent**: [Site storage engineer or admin name]
   - **Responsibilities**: 
     - Deploy network tuning on 2 test nodes; run baseline and tuned test cycles (iperf3, netperf)
     - Identify and try I/O scheduler options for storage tests; baseline and tune on 2 storage nodes
     - Run fio benchmarks (seq-read, rand-read, seq-write); document storage hardware and firmware
   - **Effort**: ~4–5 hours per site
   
2. **T2 Site (Purdue)**
   - **Network Proponent**: [Site admin name]
   - **Storage Proponent**: [Site storage engineer or admin name]
   - **Responsibilities**: 
     - Same as Fermilab; additional focus on multi-flow workloads and NUMA-aware storage tuning
     - Explore `numactl` affinity for I/O processes if storage controller supports it
   - **Effort**: ~5–6 hours per site

### USATLAS Sites (2 sites)
1. **T1 Site (BNL)**
   - **Network Proponent**: [Site admin name]
   - **Storage Proponent**: [Site storage engineer or admin name]
   - **Responsibilities**: 
     - Deploy on 2 network test nodes; focus on stability and rollback validation
     - Deploy storage tuning; validate rollback procedure
     - Extensive error log collection for compatibility analysis
   - **Effort**: ~5–6 hours per site
   
2. **T2 Site (UC Irvine)**
   - **Network Proponent**: [Site admin name]
   - **Storage Proponent**: [Site storage engineer or admin name]
   - **Responsibilities**: 
     - Same as BNL; additional focus on hardware compatibility (mixed NIC types and storage controllers)
     - Document any firmware-specific I/O scheduler constraints
   - **Effort**: ~5–6 hours per site

### Advisory Committee
- **Eli Dart (LBNL/ESnet)**: Network tuning (Fasterdata) validation and guidance
- **Dale Carder (LBNL)**: Storage and network architecture guidance
- **[TBD Storage Architect]**: Storage tuning best practices and I/O scheduler recommendations
- **Additional WLCG Network Operations and Storage contacts** as needed

### Communication
- **Weekly syncs**: Mondays 2 PM ET during active testing phases (Jan–Mar 2026)
- **Shared spreadsheet**: Track test runs, measurement results (network throughput, storage IOPS, latency), issues, and blockers
- **Central repo**: All logs, scripts, Ansible playbooks, and analysis pushed to `/root/Git-Repositories/networking/` branch `mini-challenge-1`
- **Escalation**: Any blocker (hardware failure, data corruption, driver bug) reported immediately to central coordination team

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

- **Aggregate network throughput improvement**: [TBD]
- **Aggregate storage I/O improvement**: [TBD]
- **Sites deploying network tuning to production**: [TBD]
- **Sites deploying storage tuning to production**: [TBD]
- **Key lessons learned**: [TBD]
- **I/O scheduler recommendations by hardware type**: [TBD]
- **NUMA affinity impact**: [TBD]
- **Recommended next steps**: [TBD]
- **Full report location**: `/root/Git-Repositories/networking/docs/reports/mini-challenge-1-final-report.md` (or similar)


# Capability Challenge N+1

…