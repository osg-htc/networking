### perfSONAR Deployment Options

The primary motivation for perfSONAR deployment is to test isolation, i.e. only one test should run on the host at a time. This ensures that test results are not impacted by other tests. Otherwise it is much more difficult to interpret test results, which may vary due to host effects rather then network effects. Taking this into account this means that perfSONAR measurement tools are much more accurate running on a dedicated hardware and while it may be useful to run them on other hosts such as Data Transfer Nodes the current recommendation is to have specific measurement machine. Thus the following deployment options are available: 

- **Bare metal** - is a preffered option in two possible configurations:
   - Two bare metal servers, one for latency node, one for bandwidth node
   - One bare metal server running both latency and bandwidth node together, please refer to 
- **Virtual Machine** - if bare metal is not available then it is also possible to run perfSONAR on a VM, however there are a set of additional requirements
   - Full-node VM is strongly preffered, so having 2 VMs (latency/bandwidth node) on a single bare metal. Mixing perfSONAR VM(s) with other might have an impact on the measuremenets and is therefore not recommended.
   - VM needs to be configured to have SR-IOV to NIC as well as pinned CPUs to ensure bandwidth tests are not impacted (by switching CPUs)
   - Succesfull full speed local bandwidth test should be conducted prior to putting the VM into production 
- **Container** - this is currently planned to be fully supported from 4.1 (Q1 2018), but the main focus is on perfSONAR test point, which does not replace full toolkit installation and is therefore not recommeneded for WLCG/OSG use cases
   - Docker perfSONAR test instance can still be used by sites to run tests and send results to local measurement archive, which could replace some of the on-site test instances
   

### perfSONAR Hardware Requirements

There two different nodes participating in the network testing, latency node and bandwidth node, while both are running on the exact same perfSONAR toolkit, they have very different requirements. Bandwidth node measures available (or peak) throughput with low test frequency and will thus require NIC with high capacity (1/10/40/100G are supported, 10G is recommended) as well as enough memory to support high bandwidth testing. Latency node on the other hand runs low bandwidth, but high frequency test, sending a continous stream of packets to measure delay and corresponding packet loss, packet reordering, etc. This means that while it doesn't require high capacity NIC, 1G is usually sufficient, it can impose significant load on the IO to disk as well as CPU as many tests run in parallel and need to continously store its results into local MA. The official hardware requirements are documented at http://docs.perfsonar.net/install_hardware_details.html. For WLCG/OSG deployment, we recommend at least the following for perfSONAR 4.0+:

- 10G NIC for bandwidth node, 1G NIC for latency node (for higher NIC capacities please check what CPU/RAM, PCIe lanes are needed to achieve max throughput)
- 4core x86_66 CPU (2.7 Ghz+) with at least 8GB of RAM (if both latency and bandwidth on a single node than 16GB)
- SSD disk (128GB should be sufficient)
