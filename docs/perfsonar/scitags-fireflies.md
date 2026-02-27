# SciTags, Fireflies, and perfSONAR

## What Are SciTags?

[SciTags](https://www.scitags.org/) is an initiative by the HEP/WLCG networking community to improve
network visibility by **tagging** network flows with metadata that identifies the experiment and activity
generating them. By embedding compact identifiers — an *experiment ID* and an *activity ID* — into every
packet of a tagged flow, network operators, site administrators, and researchers can:

- **Attribute traffic** to specific scientific experiments (ATLAS, CMS, LHCb, ALICE, Belle II, DUNE, etc.).
- **Distinguish activity types** such as production data transfers, analysis jobs, or network measurements.
- **Correlate** network metrics with application-level behavior for faster root-cause analysis.
- **Enable smarter traffic engineering** by providing information that routers, firewalls, and monitoring
  systems can act on.

The technical specification is maintained by the
[SciTags Organization](https://www.scitags.org/) and documented in the
[SciTags Technical Specification](https://docs.google.com/document/d/1x9JsZ7iTj44Ta06IHdkwpv5Q2u4U2QGLWnUeN2Zf5ts/edit).

---

## What Are Fireflies?

A **firefly** is a lightweight UDP packet that carries metadata about a network flow. When a tagged
application (or a daemon acting on its behalf) starts or stops a network transfer, it emits a firefly to a
designated collector. Each firefly contains:

| Field | Description |
|-------|-------------|
| **Experiment ID** | Numeric identifier for the experiment or project (e.g. ATLAS = 2, CMS = 3) |
| **Activity ID** | Numeric identifier for the type of activity (e.g. data transfer, network test) |
| **Source IP:port** | Origin of the network flow |
| **Destination IP:port** | Target of the network flow |
| **Protocol** | Transport protocol (TCP, UDP) |
| **State** | Flow state: *start*, *ongoing*, or *end* |

Fireflies serve two complementary purposes:

1. **Flow announcement** — Notify collectors and monitoring infrastructure that a tagged flow exists so it
   can be tracked from start to finish.
2. **Packet marking** — On hosts that support it, the same metadata can be encoded into the IPv6 Flow Label
   or IPv4 DSCP/TOS field of every packet, enabling in-network identification without deep packet
   inspection.

---

## What Is flowd-go?

[**flowd-go**](https://github.com/scitags/flowd-go) is a lightweight, high-performance daemon that
implements the SciTags flow-marking and firefly-sending infrastructure. It is written in Go and ships as a
single statically-linked binary (with embedded eBPF programs for packet marking on Linux ≥ 5.x kernels).

### Key capabilities

| Feature | Details |
|---------|---------|
| **Packet marking** | Uses eBPF to stamp the IPv6 Flow Label on egress packets matching tracked flows |
| **Firefly emission** | Sends UDP fireflies to local or remote collectors when flows start, continue, or end |
| **perfSONAR plugin** | Built-in plugin that marks *all* egress traffic with a configured experiment/activity ID — ideal for dedicated measurement hosts |
| **Low overhead** | Statically compiled Go binary; no Python, no containers, no runtime dependencies beyond `libz` and `libelf` (typically already present) |
| **RPM packaged** | Available from the SciTags repository for EL9 (`x86_64` and `aarch64`) |

### Architecture

flowd-go follows a **plugin → backend** pipeline:

```
  ┌──────────┐       ┌──────────┐
  │ Plugins  │──────▶│ Backends │
  │ (sources)│       │ (sinks)  │
  └──────────┘       └──────────┘
```

- **Plugins** detect or receive flow events (API calls, eBPF socket monitoring, perfSONAR catch-all, etc.).
- **Backends** act on those events: mark packets via eBPF, send fireflies, export Prometheus metrics.

For perfSONAR deployments the recommended configuration uses the **perfsonar** plugin (marks all egress
traffic) together with the **marker** backend (eBPF-based IPv6 Flow Label stamping).

---

## Why Use flowd-go with perfSONAR?

perfSONAR measurement hosts generate a significant amount of network traffic for latency, throughput, and
traceroute tests. Without tagging, this traffic is indistinguishable from other flows traversing the same
links. By running flowd-go alongside perfSONAR:

- **Network operators** can instantly identify perfSONAR measurement traffic on their infrastructure.
- **Experiment coordinators** can attribute network test results to specific projects.
- **Troubleshooters** can correlate measurement anomalies with flow-level metadata in packet captures or
  NetFlow/sFlow records.

The integration is intentionally lightweight:

1. Install the `flowd-go` RPM (a single package, ~5 MB).
2. Write a small YAML configuration selecting your experiment.
3. Enable and start the `flowd-go` systemd service.

The helper scripts in this repository automate all three steps.

---

## Experiment IDs

The following experiment IDs are defined in the SciTags registry. Select the one that matches your site's
primary experiment affiliation:

| ID | Experiment |
|----|------------|
| 1  | Default (no specific experiment) |
| 2  | ATLAS |
| 3  | CMS |
| 4  | LHCb |
| 5  | ALICE |
| 6  | Belle II |
| 7  | SKA |
| 8  | DUNE |
| 9  | LSST / Rubin Observatory |
| 10 | ILC |
| 11 | Auger |
| 12 | JUNO |
| 13 | NOvA |
| 14 | XENON |

Activity ID **2** (network testing / perfSONAR) is used by default for perfSONAR deployments.

---

## Configuration Reference

A minimal `/etc/flowd-go/conf.yaml` for a perfSONAR host affiliated with ATLAS:

```yaml
plugins:
  perfsonar:
    activityId: 2
    experimentId: 2

backends:
  marker:
    targetInterfaces: [ens4f0np0, ens4f1np1]
    markingStrategy: label
    forceHookRemoval: true
```

| Key | Description |
|-----|-------------|
| `plugins.perfsonar.activityId` | Activity type — use **2** for network testing |
| `plugins.perfsonar.experimentId` | Experiment affiliation (see table above) |
| `backends.marker.targetInterfaces` | List of NIC names whose egress traffic should be marked |
| `backends.marker.markingStrategy` | `label` = IPv6 Flow Label (recommended) |
| `backends.marker.forceHookRemoval` | Remove eBPF hooks cleanly on daemon stop |

For the full set of options see the
[flowd-go man page](https://github.com/scitags/flowd-go/blob/main/rpm/flowd-go.1.md) and the
[default conf.yaml](https://github.com/scitags/flowd-go/blob/main/rpm/conf.yaml).

---

## Verifying the Installation

After starting flowd-go, verify it is running and marking traffic:

```bash
# Check service status
systemctl status flowd-go

# View recent log output
journalctl -u flowd-go --no-pager -n 20

# Confirm eBPF programs are attached (should show tc/qdisc entries)
tc qdisc show dev <NIC_NAME>
```

---

## Further Reading

- [SciTags Organization](https://www.scitags.org/)
- [SciTags Technical Specification](https://docs.google.com/document/d/1x9JsZ7iTj44Ta06IHdkwpv5Q2u4U2QGLWnUeN2Zf5ts/edit)
- [flowd-go GitHub Repository](https://github.com/scitags/flowd-go)
- [flowd-go Man Page](https://github.com/scitags/flowd-go/blob/main/rpm/flowd-go.1.md)
- [perfSONAR Documentation](https://docs.perfsonar.net/)
