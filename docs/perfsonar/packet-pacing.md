# Packet Pacing for Data Transfer Nodes

## Overview

**Packet pacing** is a critical tuning technique for high-performance Data Transfer Nodes (DTNs) and other hosts that

need to move large amounts of data reliably across wide-area networks. By controlling the rate at which packets are sent
from the host, packet pacing can dramatically reduce packet loss, prevent receiver buffer overflows, and improve overall
throughput — sometimes by **2-4x on long paths**.

This document explains why packet pacing matters, how it works, and how to implement it on DTN nodes using Linux traffic
control (`tc`).

---

## The Problem: Data Rate Bottlenecks and Packet Loss

When transferring data across a network, the effective throughput is limited by the **minimum of three factors**:

1. **Source host read rate** — How fast the sending host can read data from storage/memory

1. **Available network bandwidth** — The capacity of the network path

1. **Destination write rate** — How fast the receiving host can write data to storage/memory

### Common Bottleneck Scenarios

### Scenario 1: Fast Source, Slower Network Path

* A 10G DTN sends to a 1G receiver or via a 1G network path

* Without pacing, the DTN floods the network with packets

* The receiver cannot keep up, leading to buffer overflow and packet loss

* TCP backs off, causing dramatic throughput drops

### Scenario 2: Multiple Parallel Streams

* A 10G DTN with 4-8 parallel GridFTP streams to a 10G receiver

* Total available bandwidth is 10G, but each stream tries to max out its connection

* Streams compete for buffers on the receiver

* Packet loss and TCP backing off reduce overall throughput

### Scenario 3: Unbalanced CPU/Network Performance

* A fast 40G/100G host with a slower CPU

* Network can send packets faster than the CPU can process them

* Receive-side bottleneck at the slower host

* Packet loss and retransmission overhead

### Scenario 4: Long-Distance Paths (50-80ms RTT)

* Network paths with high latency across continents

* Even with adequate bandwidth, mismatched send/receive rates cause issues

* Packets arrive faster than the receiver can drain them

* Studies show 2-4x throughput improvement with pacing on these paths

---

## How Packet Pacing Works

Packet pacing solves this problem by **controlling the rate at which packets leave the source host**, ensuring the
receiver is never overwhelmed and can process packets at a sustainable rate.

### Mechanism: Fair Queuing (FQ) Qdisc

Modern Linux (kernel 3.11+) includes the **Fair Queuing (FQ)** scheduler, which implements sophisticated packet pacing.
The FQ qdisc:

* **Maintains separate queues** for different flows (distinguishing between different streams)

* **Ensures fair bandwidth sharing** — each flow gets an equal share of available bandwidth

* **Paces packets intelligently** — spreads packets out over time instead of sending them in bursts

* **Reduces buffer pressure** — keeps receiving end from being overwhelmed

#### FQ vs FQ_CODEL

* **FQ** (Fair Queuing): Excellent for high-throughput TCP and data transfer

* **FQ_CODEL**: Default in modern kernels (4.12+), but less optimal for sustained high-throughput transfers

For DTN and high-speed data transfer, **FQ is recommended over FQ_CODEL**.

### Rate Limiting with Token Bucket Filter (TBF)

The **Token Bucket Filter (TBF)** qdisc enforces a maximum rate limit by:

* **Accumulating tokens** at a configured rate (e.g., 2 Gbps)

* **Requiring tokens to send packets** — each packet consumes tokens equal to its size

* **Queuing packets** when no tokens are available

* **Smoothing traffic** into a predictable, controlled rate

The burst size determines how many back-to-back packets can be sent before rate limiting kicks in. Typically, we
calculate burst as 1-2ms worth of packets at the target rate.

---

## Why Packet Pacing Works: ESnet Research Results

ESnet's performance testing with Berkeley Lab and others has demonstrated significant improvements from packet pacing:

### Key Findings

1. **Reduced Packet Loss**: By preventing receiver buffer overflow

1. **Higher Sustained Throughput**: 2-4x improvements on long paths (50-80ms RTT)

1. **Better Resource Utilization**: Prevents wasted retransmissions and TCP back-off

1. **Predictable Performance**: More consistent results across different network conditions

1. **Multi-Stream Benefits**: Especially effective with 4-8 parallel streams (common with GridFTP)

### Real-World DTN Scenario

**Configuration**: 10G DTN with 4 parallel GridFTP streams to a 10G receiver

**Without Pacing**:

* Bursts of packets overwhelm receiver

* Packet loss triggers TCP retransmissions

* TCP congestion control backs off aggressively

* Throughput: ~3-5 Gbps (underutilizing available 10G)

**With Pacing at 2 Gbps per stream** (8 Gbps total from 4 streams):

* Smooth traffic reduces packet loss

* TCP can maintain higher congestion window

* Better resource utilization at receiver

* Throughput: ~8-9 Gbps (near line rate)

**Result**: 2-3x throughput improvement

---

## Recommended Pacing Rates for Common Scenarios

### Rule of Thumb: 80-90% of NIC Speed

For a DTN with **N parallel streams**, divide available bandwidth accordingly:

| Host NIC Speed | Parallel Streams | Recommended Per-Stream Rate | Command | |---|---|---|---| | 10G | 4 | 2 Gbps | `tc
qdisc add dev eth0 root fq maxrate 2gbit` | | 10G | 8 | 1 Gbps | `tc qdisc add dev eth0 root fq maxrate 1gbit` | | 40G |
4 | 8 Gbps | `tc qdisc add dev eth0 root fq maxrate 8gbit` | | 40G | 8 | 5 Gbps | `tc qdisc add dev eth0 root fq maxrate
5gbit` | | 100G | 8 | 10-12 Gbps | `tc qdisc add dev eth0 root fq maxrate 10gbit` | | 100G (to 10G paths) | Any | 2 Gbps
| `tc qdisc add dev eth0 root fq maxrate 2gbit` |

### Rationale

* **Conservative default: 2 Gbps** — Works for most 10G-to-10G transfers, prevents overwhelming typical receivers

* **Adjust based on RTT**: Longer paths benefit from slightly lower rates

* **Divide bandwidth**: With 4 parallel streams on 10G NIC, 2 Gbps/stream = 8 Gbps total (80% utilization)

* **Monitor and tune**: Use `iperf3 --fq-rate` or perfSONAR pscheduler to test your specific path

---

## Implementation: Using fasterdata-tuning.sh

The `fasterdata-tuning.sh` script includes automated packet pacing configuration for DTN nodes.

### Audit Current State

Check what pacing rates are recommended for your DTN:

```bash fasterdata-tuning.sh --mode audit --target dtn
``` text

Output shows:

* Whether packet pacing is currently applied

* Recommended default rate: 2 Gbps (2000mbps)

### Apply Packet Pacing

Apply packet pacing with default 2 Gbps rate:

```bash sudo fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing
```

Apply with custom rate (e.g., for 100G host with 8 streams):

```bash sudo fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing --packet-pacing-rate 10gbps
``` text

Supported rate units: `kbps`, `mbps`, `gbps`, `tbps`

Examples:

* `2gbps` — 2 Gigabits per second

* `10000mbps` — 10 Gigabits per second (equivalent to 10gbps)

* `2000mbps` — 2 Gigabits per second (default)

### Dry-Run Preview

Preview what would be applied without making changes:

```bash sudo fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing --dry-run
```

Output shows the exact `tc` commands that would be executed on each interface.

### Burst Size Calculation

The script automatically calculates burst size as 1 millisecond worth of packets:

* **2 Gbps** → 250 KB burst

* **5 Gbps** → 625 KB burst

* **10 Gbps** → 1.25 MB burst

Burst is clamped to safe bounds:

* **Minimum**: 1,500 bytes (typical MTU size)

* **Maximum**: 10 MB (prevents excessive buffering)

---

## Manual Configuration with `tc` Command

If you prefer to configure packet pacing manually, use the `tc` command directly:

### Check Current Qdisc

```bash tc qdisc show dev eth0
``` text

### Set Fair Queuing with Pacing

Replace `eth0` with your actual interface name:

```bash sudo tc qdisc replace dev eth0 root fq maxrate 2gbit
```

### Verify Configuration

```bash tc qdisc show dev eth0 tc qdisc stat dev eth0
``` text

### Delete Pacing (Revert to Default)

```bash sudo tc qdisc del dev eth0 root
```

### Using Token Bucket Filter (TBF) Instead

For more granular control, use TBF instead of FQ:

```bash sudo tc qdisc replace dev eth0 root tbf rate 2gbit burst 250000 latency 100ms
``` text

Where:

* `rate` = packet pacing rate (e.g., 2gbit, 5gbit)

* `burst` = maximum burst size in bytes

* `latency` = maximum queuing latency before dropping packets

---

## Testing and Validation

### Verify Pacing is Active

```bash sysctl net.core.default_qdisc

# Should show: net.core.default_qdisc = fq

tc qdisc show dev eth0

# Should show: qdisc fq 8001: root refcnt 2 limit 10000p flows 1024

```

## Test with iperf3

iperf3 supports FQ-based pacing via the `--fq-rate` option:

```bash

# Test WITH pacing (recommended)

iperf3 -c <receiver> -P 4 --time 60 --fq-rate 2gbps

# Compare to WITHOUT pacing

iperf3 -c <receiver> -P 4 --time 60
```

Expected improvement: 10-50% higher throughput with pacing on long paths.

## Test with perfSONAR pscheduler

perfSONAR's pscheduler also supports pacing. Check your perfSONAR configuration for pacing-aware tests.

---

## Common Issues and Troubleshooting

### Issue: Pacing Not Applied

**Symptom**: `tc qdisc show` shows `qdisc mq` instead of `qdisc fq`

**Solution**: Ensure `/etc/sysctl.conf` contains:


```bash net.core.default_qdisc = fq sysctl -p
``` text

Then reapply pacing with `fasterdata-tuning.sh` or `tc` command.

### Issue: Throughput Still Low After Pacing

**Causes**:

* Pacing rate too conservative — try increasing by 10-20%

* Receiver still bottlenecked — verify receiver can sustain higher rates

* Network path issue — check for packet loss with `mtr` or `iperf3`

**Debug Steps**:

1. Test between same hosts in reverse direction (verify it's not sender-specific)

1. Gradually increase pacing rate in 1-2 Gbps increments

1. Monitor `tc -s qdisc show dev eth0` for dropped/delayed packets

### Issue: Pacing Configuration Lost After Reboot

**Solution**: The `fasterdata-tuning.sh` apply mode creates a systemd service for persistence. Enable it:


```bash sudo systemctl enable ethtool-persist.service sudo systemctl start ethtool-persist.service
```

Verify:

```bash sudo systemctl status ethtool-persist.service tc qdisc show dev eth0
``` text

---

## When NOT to Use Packet Pacing

* **Low-latency, low-throughput applications** — Pacing adds latency

* **Latency-sensitive protocols** (HFT, gaming, VoIP) — Avoid pacing

* **Measurement hosts** — Pacing should not be applied to measurement/monitor hosts

* **Low-bandwidth transfers** — Pacing provides little benefit below 1G

---

## Advanced: Per-Application Pacing

If you need finer control than host-level pacing, applications can set pacing rates using the `SO_MAX_PACING_RATE`
socket option:

```c #include <sys/socket.h>

// In your application code: int pacing_rate = 2000000000;  // 2 Gbps in bytes per second setsockopt(sockfd, SOL_SOCKET,
SO_MAX_PACING_RATE, &pacing_rate, sizeof(pacing_rate));
```

**Requirements**:

* Kernel 4.13+

* Host configured with `net.core.default_qdisc = fq` or `fq_codel`

* Application code changes required

---

## References

### ESnet Fasterdata Documentation

* **DTN Tuning Guide**: <https://fasterdata.es.net/DTN/tuning/>

* **Packet Pacing Guide**: <https://fasterdata.es.net/host-tuning/linux/packet-pacing/>

* **FQ Pacing Research Results**: <https://fasterdata.es.net/assets/fasterdata/FQ-pacing-results.pdf>

### Linux Kernel Documentation

* **tc-fq man page**: `man 8 tc-fq`

* **tc-tbf man page**: `man 8 tc-tbf`

* **tc man page**: `man 8 tc`

* **LWN Article on FQ**: <https://lwn.net/Articles/564978/>

### Tools and Testing

* **iperf3**: <https://iperf.fr/> (with `--fq-rate` support)

* **perfSONAR**: <https://www.perfsonar.net/> (pscheduler with pacing)

* **mtr** (traceroute tool): `mtr <destination>`

### Related Tuning

* **SYSCTL Tuning**: See `fasterdata-tuning.sh` for buffer sizing recommendations

* **100G+ Tuning**: <https://fasterdata.es.net/host-tuning/linux/100g-tuning/>

* **BBR Congestion Control**: <https://fasterdata.es.net/host-tuning/linux/recent-tcp-enhancements/bbr-tcp/>

---

## Summary

**Packet pacing is essential for DTN nodes and high-performance data transfer** because it:

1. ✅ **Prevents receiver buffer overflow** — Smooth traffic instead of bursts

1. ✅ **Reduces packet loss** — Eliminates TCP back-off and retransmission overhead

1. ✅ **Improves throughput 2-4x** — Especially on long paths with high latency

1. ✅ **Fair bandwidth sharing** — Each flow gets equal treatment

1. ✅ **Easy to implement** — Single command or script invocation

**Recommended Configuration for 10G DTN with 4 parallel streams**:


```bash sudo fasterdata-tuning.sh --mode apply --target dtn --apply-packet-pacing --packet-pacing-rate 2gbps
``` text

**Expected Result**: Near-line-rate throughput with minimal packet loss.

---

### Last Updated: December 2025

References: ESnet Fasterdata, Linux kernel tc documentation
