# perfSONAR use of Policy Based Routing and rp\_filter on EL9

In a multihome setup on EL9, `sysctl rp_filter` and policy-based routing (PBR) address two different layers of network
traffic handling and can conflict with each other. PBR determines the outbound path for traffic based on criteria, while
`rp_filter` is a security feature that validates the source address of inbound traffic. If not configured properly,
strict `rp_filter` can block legitimate traffic in a PBR setup.

## `sysctl rp_filter` overview

The Reverse Path Filtering (`rp_filter`) kernel parameter is a security measure designed to prevent IP spoofing, often
associated with Denial of Service (DoS) attacks. When enabled, it checks the source IP address of an incoming packet to
ensure the return path for a response would exit through the same interface that received the packet. It can be
configured with three values:

* `0`: **Disabled.** No source validation is performed. This is required for asymmetric routing setups.

* `1`: **Strict mode.** The kernel performs a reverse-path lookup. If the best return path for the packet's source address is not the interface on which the packet was received, the packet is dropped.

* `2`: **Loose mode.** The kernel only validates that the source IP is routable via *any* interface, not necessarily the one it arrived on.

## Policy-based routing (PBR) overview

PBR is a technique for overriding the standard Linux routing behavior, which is typically based solely on the
destination IP address. It allows administrators to route traffic based on other criteria, such as the source IP
address, application, protocol, or firewall marks (`fwmark`). A PBR setup involves these key steps:

1. **Create custom routing tables.** Additional tables beyond the main routing table are defined, often in `/etc/iproute2/rt_tables`.

1. **Define rules.** The `ip rule` command is used to add rules that select a specific routing table. Rules are matched against packets based on criteria like source address or firewall mark.

1. **Add routes to custom tables.** Use the `ip route` command to add routes to the new tables.

## The conflict and solution

The conflict arises when using **strict `rp_filter` (value 1\)** in a multihomed network configured with PBR.

1. A server is configured with PBR to send traffic from a specific service (e.g., source IP A1) out through network interface `eth0`.

1. The server's PBR rules also dictate that another service (e.g., source IP A2) sends traffic out through interface `eth1`.

1. An external client sends a packet to the service on source IP A2.

1. The server's PBR rules correctly select the route on `eth1` to send the response.

1. However, if strict `rp_filter` is enabled, the kernel checks the incoming packet's source address and performs a reverse-path lookup. This lookup would likely find the best return path is through `eth0` (the primary default gateway) rather than the `eth1` interface where the packet arrived.

1. The kernel drops the packet because of the `rp_filter` check, even though the PBR configuration would have correctly handled the outbound response.

## **Solution for EL9 multihome:**

To enable asymmetric routing with PBR, you must relax the `rp_filter` setting, as strict mode will cause legitimate
packets to be dropped.

The best practice is to use a value of `2` (loose mode) or `0` (disabled). The loose mode is safer as it still provides
some protection against spoofing, while `0` completely disables the check.

You can configure this persistently by editing a file in `/etc/sysctl.d/`, for example `/etc/sysctl.d/99-network.conf`:

\# Disable strict reverse path filtering for asymmetric routing net.ipv4.conf.all.rp\_filter=2

After saving the file, apply the changes with `sysctl -p`.

## Summary of differences

| Feature  | `sysctl rp_filter` | Policy-Based Routing (PBR) | | ----- | ----- | ----- | | **Purpose** | Security
mechanism to prevent IP spoofing by checking inbound packet source addresses. | Advanced routing method to control
outbound traffic path based on policies. | | **Traffic direction** | Checks incoming traffic. | Explicitly directs
outgoing traffic. | | **Mechanism** | A single kernel parameter with three states (`0`, `1`, `2`) that applies globally
or per-interface. | Uses multiple routing tables and rules (`ip rule`) to select the appropriate table for a given
packet. | | **Compatibility** | Strict mode (`1`) conflicts with multihome setups involving asymmetric routing. | Is
designed for multihome setups but requires loosening or disabling `rp_filter` to function correctly |
