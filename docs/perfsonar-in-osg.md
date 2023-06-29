### Overview of perfSONAR

For those not familiar with `perfSONAR`, this page provides a quick overview of what it is and why we recommend its deployment at OSG and WLCG sites.

OSG is working to support the scientific networking needs of it's constituents and collaborators. To do this, we are recommending all sites deploy perfSONAR so we can measure, monitor and diagnose the OSG (and WLCG) networks.

### Motivation
Distributed scientific computing relies upon networks to interconnect resources and make them usable for scientific workflows. This dependency upon the network means that issues in our networks can significantly impact the behavior of all the various cyber-infrastructure components that rely upon it. Compounding the problem is that networks, by their nature, are distributed and typically involve many different "owners" and administrators. When a problem arises somewhere along a network path, it can be very difficult to identify and localize.

This was the context for the formation of the [perfSONAR collaboration](https://www.perfsonar.net/about/mission-statement). This collaboration is focused on developing and deploying the `perfSONAR` software suite in support of network monitoring across the global set of research and education (R&E) networks. The **Open Science Grid** (**OSG**) has chosen to base the core of its network monitoring framework on `perfSONAR` because of both the capabilities of the toolkit for measuring our networks and its global acceptance as the defacto network monitoring infrastructure of first choice.

The <https://www.perfsonar.net/about/what-is-perfsonar/> provides a succinct summary: *perfSONAR is a network measurement toolkit designed to provide federated coverage of paths, 
and help to establish end-to-end usage expectations. There are 1000s of perfSONAR instances deployed world wide, many of which are available for open testing of key measures of network 
performance. This global infrastructure helps to identify and isolate problems as they happen, making the role of supporting network users easier for engineering teams, and increasing 
productivity when utilizing network resources.*

**How can OSG/WLCG members and collaborators understand, maintain and effectively utilize the networks that form the basis of their distributed collaborations?**

Our answer starts by providing visibility into our networks by the deployment of `perfSONAR`. perfSONAR allows us to regularly and consistently measure a set of network metrics that we can use to understand how our networks are operating. When problems arise, the data, along with access to the `perfSONAR` tools, can be used to diagnose and localize problems. The presence of perfSONAR toolkit deployments across our sites and networks makes identifying and fixing network problems feasible.

We strongly recommend that all OSG (and WLCG) sites deploy `perfSONAR` toolkit instances as described in our [installation guide](perfsonar/installation.md). Before installing you should consult the [requirements](perfsonar/deployment-models.md) along with the guidance on [deployment models](perfsonar/deployment-models.md). 

!!! note
	Installing perfSONAR not only benefits users at a site but will enable network engineers and OSG staff to much more effectively support those sites if network issues are suspected.

All OSG and WLCG sites should deploy **two** `perfSONAR` instances: one to measure latency/packet loss and one to measure bandwidth. 
It is possible to install both versions on a single host with at least two NICs by following the instructions at [multiple NIC guidance page](perfsonar/deployment-models.md). 

!!! warning
	It is **very important** that the perfSONAR instances be located in the same subnet as the primary storage for the site. 
	This is to ensure that we are measuring as much of the network path involved with data transfer as possible.

The [WLCG Network Throughput Working Group](https://twiki.cern.ch/twiki/bin/view/LCG/NetworkTransferMetrics) is responsible for monitoring the WLCG/OSG instances and for defining and maintaining the mesh-configurations that we use to control perfSONAR testing. Please contact us if you have questions or suggestions related to perfSONAR testing amongst WLCG sites.

For anyone maintaining/using perfSONAR we suggest to join either/both of the following mailing lists:

-   **User's Mailing List** The perfSONAR project maintains a mailing list for communication on matters of installation, configuration, bug reports, or general performance discussions: <https://lists.internet2.edu/sympa/subscribe/perfsonar-user>
-   **Announcement Mailing List** The perfSONAR project also maintains a low volume mailing list used for announcements related to software updates and vulnerabilities: <https://lists.internet2.edu/sympa/subscribe/perfsonar-announce>

#### Changes for perfSONAR 5.0

The first release of [perfSONAR 5.0.0](https://www.perfsonar.net/releasenotes-2023-04-17-5-0-0.html) was available on April 17, 2023, followed by a version supporting EL8/EL9 on June 21, 2023 ([version 5.0.3](https://www.perfsonar.net/releasenotes-2023-06-16-5-0-3.html)). All sites following our recommendation of having auto-updates enabled should have upgraded during within 1-2 days after the releases.   Version 5 marks a transition for the OSG/WLCG perfSONAR deployment, enabling us to migrate to a new network data pipeline where perfSONAR hosts directly send their measurement data to our central Elasticsearch instance via an HTTP-Archiver and Logstash. 

Highlights include:

-   Use of Opensearch for the measurement archive, replacing ESmond
-   Support for new OSes, include EL8 and EL9.
-   No longer supports ISO install option.
-   Significant number of bug fixes and new features.

For a more complete list of changes, see the full release notes at <https://www.perfsonar.net/docs_releasenotes.html>

