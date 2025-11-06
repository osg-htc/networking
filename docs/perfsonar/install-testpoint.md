## **1\. Prerequisites**

### **Ensure the host is up to date:**

sudo dnf update \-y

### **Install required packages:**

sudo dnf install \-y git podman docker-compose nftables iproute

* *Note*: podman is the default container engine on EL9. If you wish to use Docker instead, install it appropriately.

---

## **2\. Deploy the perfSONAR Testpoint Container**

### **Clone the repository:**

git clone https://github.com/perfsonar/perfsonar-testpoint-docker.git
cd perfsonar-testpoint-docker

### **Prepare configuration storage:**

sudo mkdir \-p /opt/testpoint/
sudo cp \-r compose/psconfig /opt/testpoint/

### **Edit the compose file as needed:**

Edit docker-compose.systemd.yml if you need to customize e.g., resource limits or volumes.

---

### **Pull and Launch the Container:**

sudo podman-compose \-f docker-compose.systemd.yml pull
sudo podman-compose \-f docker-compose.systemd.yml up \-d

*Or, if using Docker:*

sudo docker compose \-f docker-compose.systemd.yml pull
sudo docker compose \-f docker-compose.systemd.yml up \-d

---

## **3\. Configure Policy-Based Routing for Multi-Homed NICs**

Suppose:

* eth0 is for latency tests, IP \= 192.168.10.10/24, GW \= 192.168.10.1
* eth1 is for throughput tests, IP \= 10.20.30.10/24, GW \= 10.20.30.1

### **a) Add custom routing tables**

Edit /etc/iproute2/rt\_tables and add:

200  eth0table
201  eth1table

### **b) Add routes and rules (replace IPs as appropriate):**

\# Add rules for eth0 (latency)
sudo ip rule add from 192.168.10.10/32 table eth0table

sudo ip route add 192.168.10.0/24 dev eth0 scope link table eth0table
sudo ip route add default via 192.168.10.1 dev eth0 table eth0table

\# Add rules for eth1 (throughput)
sudo ip rule add from 10.20.30.10/32 table eth1table

sudo ip route add 10.20.30.0/24 dev eth1 scope link table eth1table
sudo ip route add default via 10.20.30.1 dev eth1 table eth1table

### **c) Make persistent**

For persistent configuration, add these rules and routes to a script (e.g., ./perfsonar-policy-routing.sh in your working directory) and call it from /etc/rc.local (be sure /etc/rc.d/rc.local is executable and enabled), or use NetworkManager’s connection profile route-rules and routes fields for the relevant interfaces.

Example systemd unit:

\# /etc/systemd/system/perfsonar-policy-routing.service
**\[Unit\]**
Description\=PerfSONAR Policy Routing
After\=network.target

**\[Service\]**
Type\=oneshot
ExecStart\=/path/to/your/working/dir/perfsonar-policy-routing.sh

**\[Install\]**
WantedBy\=multi-user.target

Enable it:

sudo systemctl enable \--now perfsonar-policy-routing

---

## **4\. Example NFTables Firewall Rules**

Below is a sample NFTables rule set that

* Allows required perfSONAR measurement ports (especially for testpoint: traceroute, iperf3, OWAMP, etc.)
* Restricts SSH access to trusted subnets/hosts
* Accepts ICMP/ICMPv6 and related/permitted connections

/etc/nftables.conf:

flush ruleset

table inet perfsonar {

    ```
set allowed\_protocols {
    type inet\_proto
    elements \= { icmp, icmpv6 }
}
set allowed\_interfaces {
    type ifname
    elements \= { "lo" }
}
set allowed\_tcp\_dports {
    type inet\_service
    elements \= { 22, 443, 861, 862, 9090, 123, 5201, 5001, 5000, 5101 }
}
set allowed\_udp\_ports {
    type inet\_service
    elements \= { 123, 5201, 5001, 5000, 5101 }
}
chain allow {
    ct state established,related accept
    ct state invalid drop
    meta l4proto @allowed\_protocols accept
    iifname @allowed\_interfaces accept
    tcp dport @allowed\_tcp\_dports ct state new accept
    udp dport @allowed\_udp\_ports ct state new accept
    \# traceroute and test ranges
    udp dport 33434-33634 ct state new accept
    udp dport 18760-19960 ct state new accept
    udp dport 8760-9960 ct state new accept
    tcp dport 5890-5900 ct state new accept
    \# SSH controls (add your trusted IPs/subnets)
    tcp dport 22 ip saddr 192.168.10.0/24 accept
    tcp dport 22 ip saddr 10.20.30.0/24 accept
}
chain input {
    type filter hook input priority 0; policy drop;
    jump allow
    reject with icmpx admin-prohibited
}
    ```

}

Apply and persist:

sudo nft \-f /etc/nftables.conf
sudo systemctl enable \--now nftables

---

## **5\. Optional: perfSONAR Testpoint Container Networking**

If you want the container to use a specific NIC, adjust the docker-compose.systemd.yml to use \--network host, or configure the container’s network accordingly. By default, host mode is recommended for testpoint deployments to avoid NAT and ensure direct packet timing.

---

## **6\. Confirm Operation**

Check containers:
sudo podman ps
\# or
sudo docker ps

*

Check logs:
sudo podman logs perfsonar-testpoint

*
* Test connectivity between testpoints.

---

## **7\. (Optional) Configure perfSONAR Remotes**

To register your testpoint with a central config:

sudo podman exec \-it perfsonar-testpoint psconfig remote list
sudo podman exec \-it perfsonar-testpoint psconfig remote \--configure-archives add http://psconfig.opensciencegrid.org/pub/auto/psb02-gva.cern.ch

---

## **8\. References & Further Reading**

* [perfSONAR testpoint Docker GitHub](https://github.com/perfsonar/perfsonar-testpoint-docker/)
* [perfSONAR Documentation](https://docs.perfsonar.net/)
* Red Hat Policy Routing [BROKEN-LINK: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/assembly_configuring-policy-based-routing_configuring-and-managing-networking]
* [NFTables Wiki](https://wiki.nftables.org/)

