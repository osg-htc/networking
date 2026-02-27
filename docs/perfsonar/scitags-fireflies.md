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
| **fireflyp plugin** | Listens for incoming firefly UDP datagrams and relays them verbatim to one or more upstream collectors (global or regional) before processing them locally — requires flowd-go ≥ 2.5.0 |
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

- **Plugins** detect or receive flow events (API calls, eBPF socket monitoring, perfSONAR catch-all,
  incoming firefly datagrams, etc.).
- **Backends** act on those events: mark packets via eBPF, send fireflies, export Prometheus metrics.

For perfSONAR deployments the full pipeline is:

```
  perfSONAR tests
       │
       ▼
  ┌──────────────┐   all flows    ┌──────────────────────┐
  │ perfsonar    │──────────────▶ │ marker backend       │
  │ plugin       │                │ (eBPF IPv6 label)    │
  └──────────────┘                └──────────────────────┘

  Local applications
  (pScheduler etc.)
       │ UDP firefly
       ▼
  ┌──────────────┐   forward      ┌──────────────────────┐
  │ fireflyp     │──────────────▶ │ global.scitags.org   │
  │ plugin       │                │ (UDP collector)      │
  └──────────────┘                └──────────────────────┘
```

For perfSONAR deployments the recommended configuration uses the **perfsonar** plugin (marks all egress
traffic) together with the **marker** backend (eBPF-based IPv6 Flow Label stamping) and the **fireflyp**
plugin (forwarding firefly announcements to regional or global collectors).

---

## Firefly Collectors

A **firefly collector** is a UDP service that receives firefly datagrams and uses them to build a real-time
view of active flows across the network. Collectors can be operated at site, regional, or global scope.

### ESnet Stardust — the global SciTags monitoring platform

Firefly datagrams sent to `global.scitags.org` are ingested by the
**[ESnet Stardust](https://stardust.es.net/)** platform, which provides a
[Scientific Network Tags dashboard](https://dashboard.stardust.es.net/goto/dfejd22wk1k3kb?orgId=2)
showing real-time and historical flow counts broken down by experiment and activity across all
participating sites.

> **The `fireflyp` plugin is the only mechanism by which perfSONAR measurement flows appear in
> Stardust.** eBPF packet marking alone (the `marker` backend) stamps packets in-flight but does
> *not* notify any collector. Only when flowd-go also runs the `fireflyp` plugin — forwarding
> locally-emitted firefly datagrams to `global.scitags.org` — will the flows be visible in the
> Stardust monitoring system.

### DNS Aliases for Collectors

The SciTags community maintains DNS aliases that abstract the physical location of collectors:

| DNS Name | Scope | Notes |
|----------|-------|-------|
| `global.scitags.org` | Global | Authoritative collector; **default for new deployments** |
| Regional aliases | Regional | Future DNS aliases (e.g. `us-east.scitags.org`) for lower-latency forwarding |

Using DNS aliases rather than hard-coded IPs allows seamless collector migrations and regional
redirection without reconfiguring every participating host.

**Default recommendation**: configure `global.scitags.org` as the firefly receiver. When regional
collectors are operational they will be announced as new DNS aliases; updating a single configuration
key is all that will be required to switch.

---

## Why Use flowd-go with perfSONAR?

perfSONAR measurement hosts generate a significant amount of network traffic for latency, throughput, and
traceroute tests. Without tagging, this traffic is indistinguishable from other flows traversing the same
links. By running flowd-go alongside perfSONAR:

- **Network operators** can instantly identify perfSONAR measurement traffic on their infrastructure.
- **Experiment coordinators** can attribute network test results to specific projects.
- **Troubleshooters** can correlate measurement anomalies with flow-level metadata in packet captures or
  NetFlow/sFlow records.
- **ESnet Stardust** will display perfSONAR measurement flows in its
  [SciTags dashboard](https://dashboard.stardust.es.net/goto/dfejd22wk1k3kb?orgId=2)
  — but **only if the fireflyp plugin is configured and forwarding to `global.scitags.org`**.

The integration is intentionally lightweight:

1. Install the `flowd-go` RPM (a single package, ~5 MB).
2. Write a small YAML configuration selecting your experiment.
3. Enable and start the `flowd-go` systemd service.

The helper scripts in this repository automate all three steps and configure the `fireflyp` plugin with
`global.scitags.org` as the firefly collector by default.

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

### Current configuration (flowd-go ≤ 2.4.x)

A minimal `/etc/flowd-go/conf.yaml` for a perfSONAR host affiliated with ATLAS using the current
released RPM:

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

### Recommended configuration (flowd-go ≥ 2.5.0, after scitags/flowd-go#49)

Once the updated RPM is available, the preferred configuration adds the **`fireflyp`** plugin so that
locally-emitted firefly datagrams (from perfSONAR tools, pScheduler, or any application) are forwarded
to the global SciTags collector:

```yaml
plugins:
  perfsonar:
    activityId: 2
    experimentId: 2
  fireflyp:
    bindAddress: "127.0.0.1"
    bindPort: 10514
    fireflyReceivers:
      - address: "global.scitags.org"
        port: 10514

backends:
  marker:
    targetInterfaces: [ens4f0np0, ens4f1np1]
    markingStrategy: label
    forceHookRemoval: true
```

For a regional collector instead of the global one, replace the `address` value with the relevant
regional DNS alias.

### Configuration key reference

```yaml
plugins:
  perfsonar:
    activityId: 2
    experimentId: 2
  fireflyp:
    bindAddress: "127.0.0.1"
    bindPort: 10514
    fireflyReceivers:
      - address: "global.scitags.org"
        port: 10514

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
| `plugins.fireflyp.bindAddress` | Address the firefly listener binds to (`127.0.0.1` for local-only) |
| `plugins.fireflyp.bindPort` | UDP port flowd-go listens on for incoming fireflies (default: 10514) |
| `plugins.fireflyp.fireflyReceivers` | List of upstream collectors to forward fireflies to |
| `plugins.fireflyp.fireflyReceivers[].address` | Collector hostname or IP (use `global.scitags.org` for the default global collector) |
| `plugins.fireflyp.fireflyReceivers[].port` | Collector UDP port (default: 10514) |
| `backends.marker.targetInterfaces` | List of NIC names whose egress traffic should be marked |
| `backends.marker.markingStrategy` | `label` = IPv6 Flow Label (recommended) |
| `backends.marker.forceHookRemoval` | Remove eBPF hooks cleanly on daemon stop |

> **Note**: The `fireflyp.fireflyReceivers` key requires **flowd-go ≥ 2.5.0**.
> The `perfSONAR-install-flowd-go.sh` helper script automatically includes this stanza
> and defaults to `global.scitags.org`. Pass `--no-firefly-receiver` when using an
> older RPM.

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
- [fireflyp plugin PR — configurable UDP forwarding](https://github.com/scitags/flowd-go/pull/49)
- [ESnet Stardust Platform](https://stardust.es.net/)
- [ESnet Stardust SciTags Dashboard](https://dashboard.stardust.es.net/goto/dfejd22wk1k3kb?orgId=2)
- [perfSONAR Documentation](https://docs.perfsonar.net/)
