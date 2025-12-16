# Host Optimization and Tuning (Concise Plan)

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

## Overview

- **Goal:** Improve WAN data transfer performance on RHEL 9 hosts by tuning network and storage subsystems.
- **Focus:**
   - Network tuning (ESnet Fasterdata): sysctl, qdisc pacing, NIC features/rings
   - Storage tuning: I/O scheduler, queue depth, read-ahead, NUMA affinity
- **Approach:** Baseline → apply tuning on a subset → compare against baseline → scale out.
- **Safety:** All changes are reversible; use saved state and restore.

## Tracking

Per the WLCG Capability Test Framework, this table tracks all mini-challenges and their status:

| Mini-Challenge | Status | Start Date | Expected End | Key Sites | Primary Focus | Outcome |
|---|---|---|---|---|---|---|
| MC-1: Network + Storage Tuning | Planned | Jan 10, 2026 | Mar 14, 2026 | FNAL, UCSD, Nebraska, BNL, AGLT2, NET2 | Network (Fasterdata), Storage I/O, CPU affinity | TBD |
| MC-2: Host Tuning + Jumbo Frames | Planned | Q2 2026 | TBD | TBD (subset MC-1 + new) | Jumbo Frames (MTU 9000), Advanced storage | TBD |

See detailed timeline and history in [mini-capability-host-tuning-details.md](mini-capability-host-tuning-details.md).

## Participants
(Please add your name): Shawn McKee, Eduardo Bach, Eli Dart, Diego Davila, Garhan Attebury, Asif Shaw, Carlos Gamboa, Hiro Ito, Wendy Dronen, Philippe Laurens

**Participants & Roles**
- **Shawn McKee (AGLT2 / University of Michigan)**: Lead, test plan owner, dCache, networking and storage expert; organizing mini-capability challenges and central coordination.
- **[Vacant]**: Testing infrastructure, automation, data aggregation (role open; volunteers welcome).
- **Eduardo Bach (UC San Diego / SuperCC)**: Network monitoring, dCache and network admin, results validation.
- **Eli Dart (LBNL / ESnet)**: Fasterdata and perfSONAR expert; advisory role on network tuning validation.
- **Diego Davila (UCSD / USCMS T2)**: Storage and network expert; CMS data transfer configuration and testing lead.
- **Garhan Attebury (University of Nebraska / USCMS T2)**: Network and systems expert; site proponent and test operator for Nebraska.
- **Asif Shaw (Fermilab / USCMS T1)**: CMS network and systems expert; FNAL site proponent and transfer testing lead.
- **Carlos Gamboa (BNL / USATLAS T1)**: BNL dCache manager; storage tuning and compatibility lead.
- **Hiro Ito (BNL)**: FTS and ATLAS data transfer expert; transfer orchestration and validation.
- **Wendy Dronen (AGLT2 / U. Michigan)**: System administrator and UM site operator at AGLT2.
- **Philippe Laurens (AGLT2 / Michigan State)**: System administrator and AGLT2 MSU site operator.
- **Others**: Additional participants may join; list to be updated as volunteers sign up. 

# Challenge 1: Host Optimization (Jan 2026)

## Advantages
- Throughput gains: 10–20% typical; up to 25% with storage tuning.
- Lower latency/jitter; fewer retransmits.
- Better CPU efficiency with fq pacing and tuned queues.
- Safe rollout with audit/save/restore tooling.

## Methodology
- Tools:
   - `fasterdata-tuning.sh` (audit/apply/save/restore)
   - Ansible + `fio` for storage scheduler/queue benchmarks
- Design:
   - Baseline → apply → measure → restore → compare.
   - Global sweep: align configs across sites, run synchronized transfers.

## State Management (Quick)
- Save baseline: `fasterdata-tuning.sh --save-state --label baseline`
- Apply with auto-save: `fasterdata-tuning.sh --mode apply --auto-save-before --label pre-apply`
- Compare: `fasterdata-tuning.sh --diff-state <saved.json>`
- Restore: `fasterdata-tuning.sh --restore-state <saved.json>`
- Details and caveats: see [state-management guide](mini-capability-host-tuning-details.md#state-management).

### Objectives
- Improve WAN throughput/latency vs baseline (GridFTP/XRootD/HTTP).
- Isolate network vs storage bottlenecks (perfSONAR, iperf3, fio).
- Quantify CPU/iowait changes; validate automation reliability.
- Document best practices and constraints; inform WLCG guidance.

### Considerations
- Reversible changes; staged rollout; coordinate with ops.
- Include diverse NIC/storage; use real workloads; keep a baseline node.

### Requirements (Summary)
- RHEL 9, 25+ Gbps NICs, NVMe/SSD, admin access.
- perfSONAR/testpoints; iperf3/fio; monitoring/logs.
- 6–8 hours/site and central coordination.

### Procedure (High-Level)

Phase 1: Baseline (Week 1–2)
- Measure WAN transfers (GridFTP/XRootD/HTTP) and perfSONAR.
- Capture host metrics; save baseline state.
- Run iperf3/fio for diagnostic baselines.

Phase 2: Apply (Week 3–4)
- Network: audit → apply on half the nodes; verify.
- Storage: test schedulers via fio; select/apply on half; note NUMA if applicable.

Phase 3: Performance (Week 5–7)
- Real transfers (GridFTP/XRootD/HTTP); perfSONAR.
- Measure CPU/iowait/memory; validate logs and stability.
- Global sweep: align config fleet-wide; audit; save tuned state; run synchronized transfers; repeat per config; compare.
- Checklist and cautions: see [details](mini-capability-host-tuning-details.md#global-sweep).


Troubleshooting quick refs are in [details](mini-capability-host-tuning-details.md#troubleshooting).

Phase 4: Cost/Risk (Week 8)
- Time to apply; resource overhead; compatibility.
- Rollback validation (network + storage).

Phase 5: Analysis (Week 9–10)
- Aggregate, compare (CI/95%); report per-site and aggregate; recommend deployment.

## Measurements (Summary)
- Primary WAN: GridFTP/FTS, XRootD, HTTP/WebDAV throughput; perfSONAR utilization; completion time; CPU and %iowait; retransmits.
- Secondary Network: iperf3 single/multi-flow; RTT; memory overhead.
- Secondary Storage: fio read/write; latency; queue depth.
- Operational: compatibility, persistence across reboot, rollback, deployment time, hardware coverage, NUMA impact.
- Monitoring: transfer logs, perfSONAR, iperf3/fio, sar, ethtool/iostat/ss, journal.

Full metric tables and thresholds: see [details](mini-capability-host-tuning-details.md#measurements).

## Cost–Benefit (Brief)
- Benefits: +10–25% WAN throughput; lower latency/jitter; improved efficiency; fewer failures.
- Costs: Personnel effort (~60–70 hours across sites); existing infra; few hours per phase.

Detailed calculations, scenarios, and contingencies: see [details](mini-capability-host-tuning-details.md#cost-benefit).


## Schedule-1: Timeline (January 2026)

| Phase | Duration | Dates | Deliverables |
|-------|----------|-------|--------------|
| **Planning & Coordination** | 1 week | Jan 1–10 | Site participant list, test plan review, hardware inventory |
| **Setup & Baseline** | 2 weeks | Jan 10–24 | Baseline measurements, system configs captured, baseline states saved |
| **Deployment & Testing** | 4 weeks | Jan 24–Feb 21 | Tuning applied, weekly test runs, logs and raw data collected |
| **Analysis & Reporting** | 2 weeks | Feb 21–Mar 7 | Results aggregated, cost-benefit analysis, final report |
| **Presentation** | 1 week | Mar 7–14 | Summary slides for WLCG/LHCONE meetings |

**Key Milestones**:
- Dec 18, 2025: Submit CHEP 2026 abstract
- Jan 10: Participant kickoff call
- Jan 24: All sites ready for testing
- Feb 7: Interim results discussion
- Feb 9–13, 2026: Report initial results at ATLAS Software & Computing Week
- Mar 14: Final presentation at next WLCG or LHCONE meeting

**Conference & Publication Milestones**:
- May 25–29, 2026: Present results at CHEP 2026
- Jun 30, 2026: Finalize CHEP paper on results

## Team-1: Participants and Responsibilities

### Central Coordination
- **Shawn McKee (U. Michigan / AGLT2)**: Lead, test plan owner, dCache, network and storage tuning expert; main organizer and contact for mini-challenge logistics
- **[Volunteer Needed]**: Testing infrastructure, automation, data aggregation and analysis; test harness lead (volunteer needed)
- **Eduardo Bach (UC San Diego / SuperCC)**: Network monitoring, perfSONAR coordination and results validation; dCache and network admin
- **Eli Dart (LBNL / ESnet)**: Fasterdata advisor, perfSONAR and network tuning validation
- **Diego Davila (UCSD / USCMS T2)**: Storage and CMS data transfer expert; assists with transfer-job setup and validation
- **Hiro Ito (BNL)**: FTS and transfer orchestration expert; advisor for ATLAS transfer testing

### USCMS Sites (3 sites)
1. **T1 Site (Fermilab)**
   - **Network Proponent**: Asif Shaw (FNAL)
   - **Storage/Data Transfer Proponent**: [Site storage or data transfer engineer]
   - **Responsibilities**: 
     - Deploy network tuning on data transfer nodes (production or pre-production)
     - Baseline and tuned WAN transfer tests: GridFTP/FTS to remote sites, perfSONAR validation
     - Storage tuning: Identify and apply best I/O scheduler for GridFTP backends
     - Monitor host impact: CPU, I/O wait, retransmits during WAN transfers
     - Document compatibility and any site-specific constraints
   - **Effort**: ~7–8 hours per site
   
2. **T2 Site (UCSD)**
   - **Network Proponent**: Diego Davila (UCSD)
   - **Storage/Data Transfer Proponent**: Diego Davila (UCSD)
   - **Responsibilities**: 
     - Same as Fermilab; focus on UCSD transfer infrastructure and XRootD/CMS workflows
     - Explore NUMA-aware tuning for data transfer processes if applicable
     - Test multi-flow WAN transfers (concurrent FTS jobs) to validate tuning under load
   - **Effort**: ~7–8 hours per site

3. **T3 Site (Nebraska)**
   - **Network Proponent**: Garhan Attebury (University of Nebraska)
   - **Storage/Data Transfer Proponent**: [Site storage or data transfer engineer]
   - **Responsibilities**: 
     - Deploy tuning and run baseline/tuned WAN transfer tests; focus on Nebraskan infrastructure
     - Validate multi-site transfer behavior and concurrency under load
     - Document any site-specific constraints or firmware issues
   - **Effort**: ~7–8 hours per site

### USATLAS Sites (3 sites)
1. **T1 Site (BNL)**
   - **Network Proponent**: [Site admin name]
   - **Storage/Data Transfer Proponent**: Carlos Gamboa (BNL)
   - **Responsibilities**: 
     - Deploy on data transfer nodes; focus on stability and rollback validation
     - Baseline and tuned WAN transfer tests: XRootD, GridFTP, or Rucio/FTS transfers to remote sites
     - Storage tuning: Test I/O scheduler options for EOS or dCache storage backend
     - Collaborate with Hiro Ito for FTS orchestration and ATLAS-specific transfer validation
     - Extensive error log collection for dCache/XRootD compatibility analysis
     - Validate rollback procedure does not disrupt production transfers
   - **Effort**: ~7–8 hours per site

2. **T2 Site (AGLT2)**
   - **Network Proponent**: Wendy Dronen (AGLT2)
   - **Storage/Data Transfer Proponent**: Shawn McKee (AGLT2)
   - **Responsibilities**: 
     - Same as BNL; additional focus on AGLT2 hardware and mixed NIC compatibility
     - Validate tuning against AGLT2 dCache pools and transfer nodes
     - Document any firmware-specific constraints for storage or NIC drivers
   - **Effort**: ~7–8 hours per site

3. **T3 Site (NET2)**
   - **Network Proponent**: Eduardo Bach (NET2)
   - **Storage/Data Transfer Proponent**: Eduardo Bach (NET2)
   - **Responsibilities**: 
     - NET2 site proponent for ATLAS; validate transfer behavior for ATLAS workflows
     - Collaborate on cross-site Global Configuration Sweeps and ATLAS-specific transfer validation
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