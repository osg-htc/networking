# perfSONAR Deployment Options

The primary motivation for perfSONAR deployment is to test isolation, i.e. only one end-to-end test should run on a host
at a time. This ensures that the test results are not impacted by the other tests. Otherwise it is much more difficult
to interpret test results, which may vary due to host effects rather then network effects. Taking this into account it
means that perfSONAR measurement tools are much more accurate running on a dedicated hardware and while it may be useful
to run them on other hosts such as Data Transfer Nodes the current recommendation is to have specific measurement
machine. In addition, as bandwidth testing could impact latency testing, we recommend to deploy two different nodes,
each focused on specific set of tests. The following deployment options are currently available:

* **Bare metal** - preffered option in one of two possible configurations:

```text

* Two bare metal servers, one for latency node, one for bandwidth node

* One bare metal server running both latency and bandwidth node together provided that there are two NICs available, please refer to [dual NIC](#multiple-nic-network-interface-card-guidance) section for more details on this.


```

* **Virtual Machine** - if bare metal is not available then it is also possible to run perfSONAR on a VM, however there are a set of additional requirements to fulfill:

```text

* Full-node VM is strongly preferred, having 2 VMs (latency/bandwidth node) on a single bare metal. Mixing perfSONAR VM(s) with others might have an impact on the measurements and is therefore not recommended.

* VM needs to be configured to have SR-IOV to NIC(s) as well as pinned CPUs to ensure bandwidth tests are not impacted (by hypervisor switching CPUs during the test)

* Succesfull full speed local bandwidth test is highly recommended prior to putting the VM into production


```

* **Container** - perfSONAR has supported containers from version 4.1 (Q1 2018) and is documented at <https://docs.perfsonar.net/install_docker.html> but is not typically used in the same way as a full toolkit installation.

```text

* Docker perfSONAR test instance can however still be used by sites that run multiple perfSONAR instances on site for their internal testing as this deployment model allows to flexibly deploy a testpoint which can send results to a local measurement archive running on the perfSONAR toolkit node.


```

## perfSONAR Toolkit vs Testpoint

The perfSONAR team has documented the types of installations supported at
<https://docs.perfsonar.net/install_options.html>.   With the release of version 5, OSG/WLCG sites have a new option:
instead of installing the full Toolkit sites can choose to install the Testpoint bundle.

* Pros

```text

* Simpler deployment when a local web interface is not needed and a central measurement archive is available.

* Less resource intensive for both memory and I/O capacity.


```

* Cons

```text

* Measurements are not stored locally

* No web interface to use for configuration or adding local tests

* Unable to show results in MaDDash


```

While sites are free to choose whatever deployment method they want, we would like to strongly recommend the use of
perfSONAR's containerized testpoint. This method was chosen as a "best practice" recommendation because of the reduced
resource constraints, less components and easier management.

## perfSONAR Hardware Requirements

There are two different nodes participating in the network testing, latency node and bandwidth node, while both are
running on the exact same perfSONAR toolkit, they have very different requirements. Bandwidth node measures available
(or peak) throughput with low test frequency and will thus require NIC with high capacity (1/10/40/100G are supported)
as well as enough memory and CPU to support high bandwidth testing. Our recommendation is to match bandwidth node NIC
speed with the one installed on the storage nodes as this would provide us with the best match when there are issues to
investigate. In case you'd like to deploy high speed (100G) bandwidth node, please consult [ESNet tuning
guide](https://fasterdata.es.net/host-tuning/100g-tuning/) and [100G tuning
presentation](https://www.es.net/assets/Uploads/100G-Tuning-TechEx2016.tierney.pdf). Latency node on the other hand runs
low bandwidth, but high frequency tests, sending a continuous stream of packets to measure delay and corresponding
packet loss, packet reordering, etc. This means that while it doesn't require high capacity NIC, 1G is usually
sufficient, it can impose significant load on the IO to disk as well as CPU as many tests run in parallel and need to
continuously store its results into local measurement archive. The minimum hardware requirements to run perfSONAR
toolkit are documented [here](http://docs.perfsonar.net/install_hardware_details.html). For WLCG/OSG deployment and
taking into account the amount of testing that we perform, we recommend at least the following for perfSONAR 5.0+:

* NIC for bandwidth node matching the capacity of the site storage nodes(10/25/40/100G), 1G NIC for latency node (for higher NIC capacities, 40/100G, please check [ESNet tuning guide](https://fasterdata.es.net/host-tuning/100g-tuning/))

* High clock speede CPU (3.0 Ghz+), fwere cores OK, with at least 32GB+ of RAM (8GB+ if using a Testpoint install)

* NVMe or SSD disk (128GB should be sufficient) if using full Toolkit install with Opensearch.

## Multiple NIC (Network Interface Card) Guidance

Many sites would prefer **not** to have to deploy two servers for cost, space and power reasons.  Since perfSONAR 3.5+
there is a way to install both latency and bandwidth measurement services on a single node, as long as it has at least
two NICs (one per 'flavor' of measurement) and sufficient processing power and memory. There are few additional steps
required in order to configure the node with multiple network cards:

* Please setup source routing as described in the [official documentation](http://docs.perfsonar.net/manage_dual_xface.html).

* You'll need to register two hostnames in [OIM](installation.md)/[GOCDB](installation.md) (and have two reverse DNS entries) as you would normally for two separate nodes.

* Instead of configuring just one auto-URL in for the remote URL, please add both, so you'll end up having something like this:

``` bash psconfig remote add "<https://psconfig.opensciencegrid.org/pub/auto/<FQDN_latency>"> psconfig remote add
"https://psconfig.opensciencegrid.org/pub/auto/<FQDN_throughput>" ...
``` text
