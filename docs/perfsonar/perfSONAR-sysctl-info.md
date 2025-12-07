# Key sysctl settings for perfSONAR

For optimal performance, the perfSONAR Toolkit applies system tuning settings by default upon installation by using the
`perfsonar-toolkit-sysctl` package. These settings are based on the ESnet "fasterdata" knowledge base for high-
performance test and measurement hosts and are sufficient for most use cases. However, you can manually verify or
adjustthe settings in `/etc/sysctl.conf` for specific needs.

## TCP buffer sizing

These settings increase the maximum TCP buffer sizes to support high throughput, especially on high-speed (e.g., 10
Gbpsand faster) networks over long distances.

* `net.core.rmem_max`: The maximum receive socket buffer size in bytes.

* `net.core.wmem_max`: The maximum send socket buffer size in bytes.

* `net.ipv4.tcp_rmem`: The minimum, default, and maximum receive buffer sizes for TCP.

* `net.ipv4.tcp_wmem`: The minimum, default, and maximum send buffer sizes for TCP.

Example settings for a 10G or 40G host with up to 100ms round-trip time (RTT):

net.core.rmem\_max \= 67108864 net.core.wmem\_max \= 67108864 net.ipv4.tcp\_rmem \= 4096 87380 33554432
net.ipv4.tcp\_wmem \= 4096 65536 33554432

For 100G or higher speeds, you may need to increase these values even further.

## Queue management and packet processing

These settings help prevent packet loss and improve network efficiency.

* `net.core.netdev_max_backlog`: Increases the maximum length of the input packet queue for the network device. A higher value can prevent dropped packets during bursts of traffic.

* `net.core.default_qdisc`: Sets the default queuing discipline. Fair Queuing (fq) or Fair Queuing with CoDel (fq\_codel) is recommended for its "fairness" in distributing bandwidth and kernel-level packet pacing.

## Multipath and routing

If you are running perfSONAR on a host with multiple network interfaces on the same subnet, specific `sysctl`
settingsare needed to prevent Address Resolution Protocol (ARP) conflicts.

net.ipv4.conf.all.arp\_ignore=1 net.ipv4.conf.all.arp\_announce=2 net.ipv4.conf.default.arp\_filter=1
net.ipv4.conf.all.arp\_filter=1

## TCP optimizations

For specific use cases, you might adjust other TCP settings:

* `net.ipv4.tcp_timestamps`: While often suggested for improving CPU utilization, be aware of the implications. The `fasterdata` guide suggests disabling it for older kernels, but modern kernels handle timestamps more efficiently.

## How to apply the settings

1. Edit the configuration file: Add the desired settings to `/etc/sysctl.conf` or a new file in `/etc/sysctl.d/` (e.g., `/etc/sysctl.d/99-perfsonar.conf`).

1. Load the settings: Run `sysctl -p` to load the changes from the configuration file.

1. Verify the settings: Use `sysctl [parameter]` to confirm the new values are in effect.

Automatic tuning with the perfSONAR Toolkit

For installations using the perfSONAR Toolkit, the included `perfsonar-toolkit-sysctl` package handles most
tuningautomatically. If you change an interface speed, you can re-run the tuning script to apply appropriate settings:

/usr/lib/perfsonar/scripts/configure\_sysctl
