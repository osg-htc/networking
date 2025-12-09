# perfSONAR Testpoint Installation (EL9)

## 1. Prerequisites

### Bootstrap the perfSONAR testpoint and tools (recommended)

Use the bootstrap script to clone the perfSONAR testpoint repo and install helper scripts under /opt/perfsonar-
tp/tools_scripts.

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
    -o /tmp/install_tools_scripts.sh
chmod 0755 /tmp/install_tools_scripts.sh
/tmp/install_tools_scripts.sh /opt/perfsonar-tp
```

### Ensure the host is up to date

```bash
dnf update -y
```

### Install required packages

```bash
dnf install -y git podman podman-compose nftables iproute
```

Note: Podman is the default container engine on EL9. If you wish to use Docker instead, install it appropriately.

---

## 2. Deploy the perfSONAR Testpoint Container

### Obtain a compose file

You can use a ready-to-run compose file maintained in the osg-htc/networking repository:

```bash
mkdir -p /opt/perfsonar-tp
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

### Prepare configuration storage

```bash
mkdir -p /opt/perfsonar-tp/psconfig
```

### Edit the compose file as needed

Edit /opt/perfsonar-tp/docker-compose.yml if you need to customize resource limits or volumes.

### Launch the container

```bash
(cd /opt/perfsonar-tp; podman-compose up -d)
```

Or, if using Docker:

```bash
(cd /opt/perfsonar-tp; docker-compose up -d)
```

### Enable automatic container restart on boot

To ensure containers restart automatically after a host reboot, install and enable the systemd service:

```bash
# Using the helper script (recommended)
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-service.sh \
    -o /tmp/install-systemd-service.sh
chmod +x /tmp/install-systemd-service.sh
sudo /tmp/install-systemd-service.sh /opt/perfsonar-tp
```

Or manually create the service file:

```bash
sudo tee /etc/systemd/system/perfsonar-testpoint.service > /dev/null << 'EOF'
[Unit]
Description=perfSONAR Testpoint Container Service
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/opt/perfsonar-tp

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/perfsonar-tp
ExecStart=/usr/bin/podman-compose up -d
ExecStop=/usr/bin/podman-compose down
TimeoutStartSec=300
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable perfsonar-testpoint.service
```

Useful commands:

- Start service: `systemctl start perfsonar-testpoint`

- Stop service: `systemctl stop perfsonar-testpoint`

- Restart service: `systemctl restart perfsonar-testpoint`

- Check status: `systemctl status perfsonar-testpoint`

- View logs: `journalctl -u perfsonar-testpoint -f`

---

## 3. Configure Policy-Based Routing for Multi-Homed NICs

Recommended: use the helper script to generate and apply NetworkManager profiles and routing rules for multi-NIC hosts.

1. Preview generation (no changes):

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-debug

    ```

1. Generate the config file automatically:

    ```bash

    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto

    ```

Note: The auto-generator intentionally skips NICs that have neither an IPv4 nor an IPv6 gateway (e.g., management-only
NICs) to avoid writing non-functional NetworkManager profiles. To include such a NIC in the configuration, set an
explicit gateway or mark it as `DEFAULT_ROUTE_NIC` in `/etc/perfSONAR-multi-nic-config.conf`.

Review and adjust /etc/perfSONAR-multi-nic-config.conf if needed.

1. Dry run the apply step:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --dry-run --debug

    ```

1. Apply changes:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes

    ```

The script backs up current NetworkManager profiles and logs actions to /var/log/perfSONAR-multi-nic-config.log.

If you prefer to configure rules manually, see the example below.

### Manual example

Suppose:

- eth0 is for latency tests, IP \= 192.168.10.10/24, GW \= 192.168.10.1

- eth1 is for throughput tests, IP \= 10.20.30.10/24, GW \= 10.20.30.1

#### a) Add custom routing tables

Edit /etc/iproute2/rt\_tables and add:

200  eth0table 201  eth1table

#### b) Add routes and rules (replace IPs as appropriate)

\# Add rules for eth0 (latency) ip rule add from 192.168.10.10/32 table eth0table

ip route add 192.168.10.0/24 dev eth0 scope link table eth0table ip route add default via 192.168.10.1 dev eth0 table
eth0table

\# Add rules for eth1 (throughput) ip rule add from 10.20.30.10/32 table eth1table

ip route add 10.20.30.0/24 dev eth1 scope link table eth1table ip route add default via 10.20.30.1 dev eth1 table
eth1table

#### c) Make persistent

For persistent configuration, add these rules and routes to a script (e.g., ./perfsonar-policy-routing.sh in your
working directory) and call it from /etc/rc.local (be sure /etc/rc.d/rc.local is executable and enabled), or use
NetworkManager’s connection profile route-rules and routes fields for the relevant interfaces.

Example systemd unit:

\# /etc/systemd/system/perfsonar-policy-routing.service **\[Unit\]** Description\=PerfSONAR Policy Routing
After\=network.target

**\[Service\]** Type\=oneshot ExecStart\=/path/to/your/working/dir/perfsonar-policy-routing.sh

**\[Install\]** WantedBy\=multi-user.target

Enable it:

systemctl enable \--now perfsonar-policy-routing

---

## 4. Firewall and security

Recommended: configure nftables (and optionally SELinux and Fail2Ban) using the helper script.

1. Run with options:

```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes
```

1. Preview rules only:

```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --print-rules
```

The script writes rules to /etc/nftables.d/perfsonar.nft and logs to /var/log/perfSONAR-install-nftables.log.

### Manual nftables example (optional)

Below is a sample NFTables rule set that

- Allows required perfSONAR measurement ports (especially for testpoint: traceroute, iperf3, OWAMP, etc.)

- Restricts SSH access to trusted subnets/hosts

- Accepts ICMP/ICMPv6 and related/permitted connections

 /etc/nftables.conf:

```nft
flush ruleset

table inet perfsonar {

set allowed_protocols { type inet_proto elements = { icmp, icmpv6 } }
set allowed_interfaces { type ifname elements = { "lo" } }
set allowed_tcp_dports { type inet_service elements = { 22, 443, 861, 862, 9090, 123, 5201, 5001, 5000, 5101 } }
set allowed_udp_ports { type inet_service elements = { 123, 5201, 5001, 5000, 5101 } }
chain allow {
    ct state established,related accept
    ct state invalid drop
    meta l4proto @allowed_protocols accept
    iifname @allowed_interfaces accept
    tcp dport @allowed_tcp_dports ct state new accept
    udp dport @allowed_udp_ports ct state new accept
    # traceroute and test ranges
    udp dport 33434-33634 ct state new accept
    udp dport 18760-19960 ct state new accept
    udp dport 8760-9960 ct state new accept
    tcp dport 5890-5900 ct state new accept
    # SSH controls (add your trusted IPs/subnets)
    tcp dport 22 ip saddr 192.168.10.0/24 accept
    tcp dport 22 ip saddr 10.20.30.0/24 accept
}
chain input {
    type filter hook input priority 0; policy drop;
    jump allow
    reject with icmpx admin-prohibited
}

```

Apply and persist:

nft -f /etc/nftables.conf
systemctl enable --now nftables

---

## 5. Optional: perfSONAR Testpoint Container Networking

If you want the container to use a specific NIC, adjust the docker-compose.systemd.yml to use \--network host, or configure the container’s network accordingly. By default, host mode is recommended for testpoint deployments to avoid NAT and ensure direct packet timing.

---

## 6. Confirm Operation

Check containers:

```bash
podman ps

# or

docker ps
```

Check logs:

```bash
podman logs perfsonar-testpoint
```

Test connectivity between testpoints.

---

## 7. (Optional) Configure perfSONAR Remotes

To register your testpoint with a central config:

```bash
podman exec -it perfsonar-testpoint psconfig remote list
podman exec -it perfsonar-testpoint psconfig remote --configure-archives add "https://psconfig.opensciencegrid.org/pub/auto/psb02-gva.cern.ch"
--configure-archives add "<https://psconfig.opensciencegrid.org/pub/auto/psb02-gva.cern.ch>"

```bash

---

## 8. References & Further Reading

- [perfSONAR testpoint Docker GitHub](https://github.com/perfsonar/perfsonar-testpoint-docker/)
- [perfSONAR Documentation](https://docs.perfsonar.net/)
- Red Hat Policy Routing [BROKEN-LINK: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/assembly_configuring-policy-based-routing_configuring-and-managing-networking]
- [NFTables Wiki](https://wiki.nftables.org/)
