### perfSONAR Deployment Options

The primary motivation for perfSONAR deployment is to test isolation, i.e. only one end-to-end test should run on a host at a time. This ensures that the test results are not impacted by the other tests. Otherwise it is much more difficult to interpret test results, which may vary due to host effects rather then network effects. Taking this into account it means that perfSONAR measurement tools are much more accurate running on a dedicated hardware and while it may be useful to run them on other hosts such as Data Transfer Nodes the current recommendation is to have specific measurement machine. In addition, as bandwidth testing could impact latency testing, we recommend to deploy two different nodes, each focused on specific set of tests. The following deployment options are currently available: 

* **Bare metal** - preffered option in one of two possible configurations:
    * Two bare metal servers, one for latency node, one for bandwidth node
    * One bare metal server running both latency and bandwidth node together provided that there are two NICs available, please refer to [dual NIC](#multiple-nic-network-interface-card-guidance) section for more details on this.
* **Virtual Machine** - if bare metal is not available then it is also possible to run perfSONAR on a VM, however there are a set of additional requirements to fulfill:
    * Full-node VM is strongly preffered, having 2 VMs (latency/bandwidth node) on a single bare metal. Mixing perfSONAR VM(s) with others might have an impact on the measurements and is therefore not recommended. 
    * VM needs to be configured to have SR-IOV to NIC(s) as well as pinned CPUs to ensure bandwidth tests are not impacted (by hypervisor switching CPUs during the test)
    * Succesfull full speed local bandwidth test is highly recommended prior to putting the VM into production 
* **Container** - this is currently planned to be fully supported from version 4.1 (Q1 2018), but the main focus is on perfSONAR test point, which does not replace full toolkit installation as it doesn't include a local measurement archive and is therefore not recommeneded for WLCG/OSG use cases:
    * Docker perfSONAR test instance can however still be used by sites that run multiple perfSONAR instances on site for their internal testing as this deployment model allows to flexibly deploy a test-point which can send results to a local measurement archive running on the perfSONAR toolkit node. 
   
### perfSONAR Hardware Requirements

There are two different nodes participating in the network testing, latency node and bandwidth node, while both are running on the exact same perfSONAR toolkit, they have very different requirements. Bandwidth node measures available (or peak) throughput with low test frequency and will thus require NIC with high capacity (1/10/40/100G are supported) as well as enough memory and CPU to support high bandwidth testing. Our recommendation is to match bandwidth node NIC speed with the one installed on the storage nodes as this would provide us with the best match when there are issues to investigate. In case you'd like to deploy high speed (100G) bandwidth node, please consult [ESNet tuning guide](https://fasterdata.es.net/host-tuning/100g-tuning/) and [100G tuning presentation](https://www.es.net/assets/Uploads/100G-Tuning-TechEx2016.tierney.pdf). Latency node on the other hand runs low bandwidth, but high frequency tests, sending a continuous stream of packets to measure delay and corresponding packet loss, packet reordering, etc. This means that while it doesn't require high capacity NIC, 1G is usually sufficient, it can impose significant load on the IO to disk as well as CPU as many tests run in parallel and need to continuously store its results into local measurement archive. The minimum hardware requirements to run perfSONAR toolkit are documented [here](http://docs.perfsonar.net/install_hardware_details.html). For WLCG/OSG deployment and taking into account the amount of testing that we perform, we recommend at least the following for perfSONAR 4.0+:

- 10G NIC for bandwidth node (or matching capacity of the storage nodes), 1G NIC for latency node (for higher NIC capacities, 40/100G, please check [ESNet tuning guide](https://fasterdata.es.net/host-tuning/100g-tuning/))
- 4-core x86_64 CPU (2.7 Ghz+) with at least 8GB of RAM (if both latency and bandwidth are on a single node then 16GB)
- SSD disk (128GB should be sufficient)

### Multiple NIC (Network Interface Card) Guidance

Many sites would prefer **not** to have to deploy two servers for cost, space and power reasons.  Since perfSONAR 3.5+ there is a way to install both latency and bandwidth measurement services on a single node, as long as it has at least two NICs (one per 'flavor' of measurement) and sufficient processing power and memory. There are few additional steps required in order to configure the node with multiple network cards:

- Please setup source routing as described in the [official documentation](http://docs.perfsonar.net/manage_dual_xface.html).
- You'll need to register two hostnames in [OIM](installation.md)/[GOCDB](installation.md) (and have two reverse DNS entries) as you would normally for two separate nodes.
- Instead of configuring just one auto-URL in the `/etc/perfsonar/meshconfig-agent.conf`, please add both, so you'll end up having something like this:
```
<mesh>
    configuration_url http://meshconfig.opensciencegrid.org/pub/auto/<hostname_nic1>
    validate_certificate 0
    required 1
</mesh>
<mesh>
    configuration_url http://meshconfig.opensciencegrid.org/pub/auto/<hostname_nic2>
    validate_certificate 0
    required 1
</mesh>
...
```
