# Host and Network Tuning (EL9)

This guide distills ESnet Fasterdata recommendations for high-throughput hosts (perfSONAR/DTN-style) on Enterprise Linux 9. Primary sources:

- https://fasterdata.es.net/host-tuning/
- https://fasterdata.es.net/network-tuning/
- https://fasterdata.es.net/DTN/

Use the provided audit/apply script to check your host against these recommendations and optionally enforce them. Read the cautions before applying.

## What this covers

- Kernel networking sysctls: buffers, congestion control, qdisc, MTU probing
- Tuned profile: `network-throughput`
- Per-interface checks: ring buffers, GRO/GSO/TSO on, LRO off, checksum on, txqueuelen, fq qdisc
- Congestion control: prefer `bbr` (fallback to `cubic` if unavailable)

## When to use this

- perfSONAR testpoints, DTNs, and other dedicated measurement/transfer hosts on EL9
- Fresh installs or periodic compliance checks against Fasterdata guidance
- Not for multi-tenant or latency-sensitive hosts without review

## Script: `fasterdata-tuning.sh`

Path: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

Modes:
- `audit` (default): show current settings vs recommendations, no changes
- `apply`: set recommended values (requires root)

### Examples

Audit everything (auto-detected interfaces):
```bash
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit
```

Apply recommendations (writes `/etc/sysctl.d/90-fasterdata.conf`, tunes NICs):
```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply
```

Limit to specific NICs:
```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --ifaces "eth0,eth1"
```

### What the script does

- Sysctl: sets larger rmem/wmem, netdev backlog, `default_qdisc=fq`, `tcp_mtu_probing=1`, TCP r/w mem, timestamps/SACK on, low_latency off; prefers `bbr` if available
- Tuned: ensures `network-throughput` profile if `tuned-adm` is present
- Interfaces (per NIC):
  - set `txqueuelen` to ≥ 10000
  - set RX/TX rings to driver max (if reported)
  - enable GRO/GSO/TSO and checksums; disable LRO
  - replace qdisc with `fq`

### Cautions

- Apply mode changes the running system and writes sysctl to `/etc/sysctl.d/90-fasterdata.conf`.
- NIC ethtool settings are immediate but not persistent across reboots. If you need persistence, run this script at boot (e.g., via a systemd service) or mirror settings in your network manager.
- The script assumes EL9 userland (`sysctl`, `ethtool`, `tc`, `tuned-adm`). It skips steps if tools are missing.
- If `bbr` is not available, it falls back to `cubic` live but keeps `bbr` in the config for future kernels.
- Always validate after applying: check `podman ps`/services, run a quick throughput test, and review `dmesg`/`journal` for NIC or driver warnings.

## Manual checklist (summary of recommendations)

- Sysctl
  - `net.core.rmem_max`/`wmem_max`: 536,870,912
  - `net.core.rmem_default`/`wmem_default`: 134,217,728
  - `net.core.netdev_max_backlog`: 250,000
  - `net.core.default_qdisc`: `fq`
  - `net.ipv4.tcp_rmem`: `4096 87380 536870912`
  - `net.ipv4.tcp_wmem`: `4096 65536 536870912`
  - `net.ipv4.tcp_congestion_control`: `bbr` (or `cubic` if `bbr` absent)
  - `net.ipv4.tcp_mtu_probing`: `1`
  - `net.ipv4.tcp_window_scaling`: `1`
  - `net.ipv4.tcp_timestamps`: `1`
  - `net.ipv4.tcp_sack`: `1`
  - `net.ipv4.tcp_low_latency`: `0`
- Tuned: `tuned-adm profile network-throughput`
- Interfaces
  - `txqueuelen` ≥ 10000
  - RX/TX rings at driver max (`ethtool -g` / `-G`)
  - GRO/GSO/TSO on; checksums on; LRO off
  - qdisc `fq` (root)

## Verification after tuning

- `sysctl -a | egrep "(rmem|wmem|max_backlog|default_qdisc|tcp_congestion_control|tcp_mtu_probing)"`
- `tuned-adm active`
- For each NIC: `ethtool -k <iface>`, `ethtool -g <iface>`, `tc qdisc show dev <iface>`, `cat /sys/class/net/<iface>/tx_queue_len`
- Run a representative throughput test (e.g., `iperf3`) end-to-end.

## Persistence notes

- Sysctl settings persist via `/etc/sysctl.d/90-fasterdata.conf`
- NIC ethtool changes do not persist by default; consider:
  - running this script from a boot-time systemd unit, or
  - translating the settings into your network manager configuration

