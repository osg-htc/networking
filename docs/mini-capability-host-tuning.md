# Host Network Tuning Optimization Testing

Capability:  Host Network Tuning Optimization Testing

Description:  We need to evaluate what host network tunings are still relevant/appropriate for RHEL9 (or similar) OSes using high speed NICs (25/40/100/200/400 Gbps) and fast storage (suggested by Dale Carder and Eli Dart)

This document can be used to track the history of the capability challenge.   Clone the set below, replacing N with 1 for the first mini-challenge.  Future mini-challenges will be 2, 3, etc.

## Participants

(Please add your name): Shawn McKee, Lincoln Bryant, Eduardo Bach, Eli Dart, 

# Capability Challenge 1: Host Network Tuning Optimization Testing (January 2026)

## Overview

Validate and optimize ESnet Fasterdata-recommended host network tuning configurations for RHEL 9 systems with high-speed NICs (25/40/100 Gbps) and high-performance storage. This challenge will test the `fasterdata-tuning.sh` v1.3.1 automated tuning tool across USCMS and USATLAS production sites to measure impact on data transfer throughput, latency, and operational overhead.

## Plan-1: Testing Methodology and Implementation

### Objectives
1. **Validate tuning effectiveness**: Measure throughput and latency improvements with automated host tuning applied vs. baseline (stock RHEL 9 defaults)
2. **Test automation reliability**: Confirm `fasterdata-tuning.sh` audit and apply operations complete without errors across diverse hardware
3. **Evaluate operational cost**: Assess prerequisites, deployment time, post-apply stability, and resource overhead
4. **Document best practices**: Provide site operators with clear deployment guidance and decision criteria

### Key Considerations
- **Minimal risk**: Tuning changes are reversible; state save/restore feature enables easy rollback
- **Staged rollout**: Start with 1–2 dedicated test nodes per site before broader deployment
- **Hardware diversity**: Include varied NIC types (Broadcom, Mellanox, Intel) and bond/VLAN configurations to validate tool robustness
- **Network isolation**: Test data transfers occur on dedicated test networks to avoid production impact
- **Baseline preservation**: Maintain unmodified reference nodes for comparison

### Requirements
- RHEL 9.x systems with 25 Gbps or faster NICs
- Dedicated test network or isolated VLAN for data transfer tests
- Data transfer tools (iperf3, iperf, gridftp) and monitoring infrastructure (netflow, packet sniffers)
- Administrative access to apply sysctl, ethtool, and tc commands
- Systems administration time for coordination and troubleshooting

### Procedure

#### Phase 1: Setup and Baseline (Week 1–2)
1. Deploy test harness on 2 USCMS + 2 USATLAS sites (4 sites total; 2 nodes per site)
2. Perform baseline measurements (no tuning applied):
   - Single-flow and multi-flow TCP throughput
   - Latency and jitter percentiles
   - CPU utilization and context switches
   - Memory footprint and cache misses
3. Capture system configuration (kernel, drivers, firmware versions)
4. Save baseline state using `fasterdata-tuning.sh --save-state`

#### Phase 2: Deployment (Week 3–4)
1. Run audit on all test nodes: `./fasterdata-tuning.sh --mode audit --target measurement`
2. Apply tuning on half of test nodes (one per site): `sudo ./fasterdata-tuning.sh --mode apply --target measurement`
3. Log all changes to sysctl, ethtool, and tc settings
4. Verify persistence across reboot

#### Phase 3: Performance Testing (Week 5–7, overlaps Phase 2)
1. **Data transfer tests** (weekly, 3 iterations per configuration):
   - 1-hour sustained single-flow TCP transfer (iperf3)
   - 10 parallel flows (iperf3) to simulate production workload
   - GridFTP transfers (if available) to test real application behavior
2. **Network protocol validation**:
   - Verify BBR congestion control is active and behaving correctly
   - Confirm fq qdisc packet pacing without breaking VLAN/bond interfaces
   - Check for unexpected packet loss or reordering
3. **System stability**:
   - Monitor dmesg for errors or warnings
   - Check for NIC resets or driver issues
   - Verify no memory leaks in long-running tests

#### Phase 4: Cost/Risk Assessment (Week 8)
1. Document time to apply tuning per site (includes audit, apply, testing)
2. Quantify resource overhead (CPU for fq qdisc, memory for larger TCP buffers)
3. Identify any compatibility issues (driver bugs, performance regressions)
4. Test rollback procedure: restore baseline state and verify transfer performance returns to baseline

#### Phase 5: Analysis and Reporting (Week 9–10)
1. Aggregate results across 4 sites
2. Calculate throughput/latency improvements (statistical significance testing)
3. Produce site-specific and aggregate reports
4. Recommendations for production deployment

## Metrics-1: Measurements and Monitoring

### Primary Metrics
| Metric | Method | Target | Success Criterion |
|--------|--------|--------|-------------------|
| **Single-flow throughput** | iperf3 -t 3600 (1 hour) | Baseline + 10% | Improvement or no regression |
| **Multi-flow throughput** | iperf3 -P 10 (10 parallel) | Baseline + 5% | Improvement or no regression |
| **Latency (p50, p95, p99)** | iperf3 histogram or netperf | <100μs (p50) | Stable or improved |
| **CPU utilization** | top, /proc/stat | <80% at saturation | Tuning does not create bottleneck |
| **Memory usage (TCP buffers)** | /proc/meminfo | <5% of system RAM | Acceptable overhead |

### Secondary Metrics
- **Packet loss rate**: Goal <0.01% over sustained transfers
- **Reboot safety**: Tuning persists correctly post-reboot without errors
- **Rollback success**: State restore returns system to baseline state exactly
- **Deployment time**: Minutes to complete audit and apply on a node
- **Hardware compatibility**: Pass audit on 100% of tested NIC types (Broadcom, Mellanox, Intel)

### Monitoring Infrastructure
- **netperf** or **iperf3** for throughput and latency
- **ifstat** / **ethtool -S** for NIC statistics (errors, drops, retransmits)
- **sysstat** (sar) for CPU, memory, context switches
- **tcpdump** for packet-level inspection (sample-based, not full packet capture)
- **systemd journal** for ethtool-persist service logs and errors

## Cost-Benefit-1: Cost and Benefit Analysis

### Benefit Estimation
1. **Throughput improvement**: If baseline is 18 Gbps and tuning achieves 20 Gbps (11% gain), then:
   - Benefit = `(20 - 18) / 18 × 100 = 11% faster data transfers`
   - Operational impact: ~10% reduction in transfer time for long-running jobs
2. **Energy efficiency**: Lower CPU utilization per Gbps transferred translates to reduced power consumption
3. **Latency reduction**: Lower jitter enables more predictable job scheduling and fewer retransmissions

### Cost Estimation
1. **Personnel**: 
   - Site admins: 2–4 hours per site for initial setup and monitoring (total 8–16 hours across 4 sites)
   - Central team: 4–8 hours for test harness setup, coordination, analysis
2. **Infrastructure**: 
   - Dedicated test NICs or VLANs (typically already available at HPC sites)
   - Storage for baseline captures and test logs (~100 MB per site)
3. **Runtime**: 
   - Baseline testing: 4 hours per node (1 day for all 8 nodes)
   - Tuned testing: 6 hours per node (1.5 days for all 4 tuned nodes)
   - Total test runtime: ~3 weeks (overlapping phases)

### Cost-Benefit Comparison
- **Scenario A (10% throughput gain, 10 PB/year data)**: 
  - Benefit: 1 PB faster transfer capacity
  - Cost: ~50 site-hours + test infrastructure; amortized over 1 year = negligible
  - **Recommendation: Deploy**
  
- **Scenario B (no improvement observed)**:
  - Benefit: Validation that RHEL 9 defaults are adequate; knowledge benefit
  - Cost: As above
  - **Recommendation: Document findings; do not mandate deployment**

### Contingency
If a site observes instability or regressions:
- Immediate action: Restore baseline state using `--restore-state` feature
- Investigation: Capture logs and hardware details for root cause analysis
- Fallback: Tuning is optional; sites can defer deployment until issue is resolved

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
- **Shawn McKee (U. Michigan)**: Lead, test plan owner, fasterdata-tuning.sh expert
- **Lincoln Bryant (U. Wisconsin)**: Testing infrastructure, data analysis
- **Eduardo Bach (UC San Diego/SuperCC)**: Network monitoring, results validation

### USCMS Sites (2 sites)
1. **T1 Site (Fermilab)**
   - Proponent: [Site admin name]
   - Responsibilities: Deploy on 2 test nodes, run baseline and tuned test cycles, report results
   
2. **T2 Site (Purdue)**
   - Proponent: [Site admin name]
   - Responsibilities: Same as above; additional focus on multi-flow workloads

### USATLAS Sites (2 sites)
1. **T1 Site (BNL)**
   - Proponent: [Site admin name]
   - Responsibilities: Deploy on 2 test nodes, focus on stability and rollback validation
   
2. **T2 Site (UC Irvine)**
   - Proponent: [Site admin name]
   - Responsibilities: Same as above; additional focus on hardware compatibility (mixed NIC types)

### Advisory Committee
- **Eli Dart (LBNL/ESnet)**: Fasterdata recommendations validation
- **Dale Carder (LBNL)**: Storage and network architecture guidance
- Additional WLCG Network Operations contacts as needed

### Communication
- **Weekly syncs**: Mondays 2 PM ET during active testing phases
- **Shared spreadsheet**: Track test runs, measurement results, issues, and blockers
- **Central repo**: All logs, scripts, and analysis pushed to `/root/Git-Repositories/networking/` branch `mini-challenge-1`

## Evaluation Criteria-1: Success Metrics and Decision Framework

### Success Criteria
1. ✅ **Data quality**: Baseline and tuned measurements completed for ≥80% of planned test cycles
2. ✅ **No regressions**: Throughput does not decrease by >5% after tuning (or isolated to specific hardware)
3. ✅ **Stability**: All nodes complete test phases without unplanned reboots or service errors
4. ✅ **Reproducibility**: Tuning changes are consistently applied and measured across all sites
5. ✅ **Cost acceptable**: Total site effort ≤20 hours per site

### Go/No-Go Decision Framework
- **Go for production recommendation**: If ≥2 sites show ≥5% improvement with no major regressions
- **Conditional recommendation**: If improvement is site-specific or hardware-specific; recommend per-site evaluation
- **No recommendation**: If no improvement observed or regressions encountered; document findings and defer

## Results-1: Summary and Follow-Up

*To be completed by March 2026.*

- **Aggregate throughput improvement**: [TBD]
- **Sites deploying to production**: [TBD]
- **Key lessons learned**: [TBD]
- **Recommended next steps**: [TBD]
- **Full report location**: `/root/Git-Repositories/networking/docs/reports/mini-challenge-1-final-report.md` (or similar)

# Capability Challenge N+1

…