### Multiple NIC (Network Interface Card) Guidance

The OSG and WLCG recommendation is to deploy two flavors of perfSONAR measurement nodes: 1) a latency instance which
continuously measures packet delay and lost and 2) a bandwidth instance measuring the achievable bandwidth.  That
implies sites must purchase, deploy and maintain two systems.  **Why can't we just run both latency and bandwidth
services on a single instance?** The problem is that running both latency and bandwidth services on a single node /
single NIC may cause interence between the various measurements and introduce "false-positive" indications of network
problems.

Many sites would prefer **not** to have to deploy two servers for cost, space and power reasons.  Fortunately the
perfSONAR developers have provided a way to install both latency and bandwidth measurements services on a single node,
as long as it has at least two NICs (one per 'flavor' of measurement) and sufficient processing and memory.  See
[manage-dual-xface](http://docs.perfsonar.net/manage_dual_xface.html) for details on configuring this.
