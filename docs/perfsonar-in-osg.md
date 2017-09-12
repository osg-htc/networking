<span class="twiki-macro LINKCSS"></span>

<span class="twiki-macro SPACEOUT">Overview of perfSONAR</span>
===============================================================


<span class="twiki-macro STARTINCLUDE"></span> 
For those not familiar with `perfSONAR`, this page provides a quick overview of what it is and why we recommend its deployment at OSG and WLCG sites.

OSG is working to support the scientific networking needs of it's constituents and collaborators. To do this, we are recommending all sites deploy perfSONAR 
so we can measure, monitor and diagnose the OSG (and WLCG) networks.

### The Challenge 
Distributed scientific computing relies upon networks to interconnect resources and make them usable for scientific workflows. This dependency upon the network means that issues in 
our networks can significantly impact the behavior of all the various cyber-infrastructure components that rely upon it. Compounding the problem is that networks, by their nature, are 
distributed and typically involve many different "owners" and administrators. When a problem arises somewhere along a network path, it can be very difficult to identify and localize.

This was the context for the formation of the perfSONAR collaboration (see <https://www.perfsonar.net/about/mission-statement>). This collaboration is focused on developing and 
deploying the `perfSONAR` software suite in support of network monitoring across the global set of research and education (R&E) networks. The **Open Science Grid** (**OSG**) has chosen to 
base the core of its network monitoring framework on `perfSONAR` because of both the capabilities of the toolkit for measuring our networks and its global acceptance as the defacto 
network monitoring infrastructure of first choice.

The <https://www.perfsonar.net.about/what-is-perfsonar/> provides a succinct summary: ``*perfSONAR is a network measurement toolkit designed to provide federated coverage of paths, 
and help to establish end-to-end usage expectations. There are 1000s of perfSONAR instances deployed world wide, many of which are available for open testing of key measures of network 
performance. This global infrastructure helps to identify and isolate problems as they happen, making the role of supporting network users easier for engineering teams, and increasing 
productivity when utilizing network resources.*''

### OSG Networking

**How can OSG members and collaborators understand, maintain and effectively utilize the networks that form the basis of their distributed collaborations?**

Our answer starts by providing visibility into our networks by the deployment of `perfSONAR`. perfSONAR allows us to regularly and consistently measure a set of network metrics that we 
can use to understand how our networks are operating. When problems arise, the data, along with access to the `perfSONAR` tools, can be used to diagnose and localize problems. The 
presence of perfSONAR toolkit deployments across our sites and networks makes identifying and fixing network problems feasible.

We strongly recommend that all OSG (and WLCG) sites deploy `perfSONAR` toolkit instances as described in our [installation guide](perfsonar/installation). Before installing you should consult 
the [requirements](perfsonar/requirements) along with the guidance on [deployment models](perfsonar/deployment-models). 

!!! note
	Installing perfSONAR not only benefits users at a site but will enable network engineers and OSG staff to much more effectively support those sites if network issues are suspected.

All OSG and WLCG sites should deploy **two** `perfSONAR` instances: one to measure latency/packet loss and one to measure bandwidth. 
It is possible to install both versions on a single host with at least two NICs by following the instructions at <http://docs.perfsonar.net/manage_dual_xface.html> but you should 
read the [multiple NIC guidance page](persfonar/multiple-nic-guidance). 

!!! warning
	It is **very important** that the perfSONAR instances be located in the same subnet as the primary storage for the site. 
	This is to ensure that we are measuring as much of the network path involved with data transfer as possible.


Our **strong recommendation** for anyone maintaining/using perfSONAR is that they join either/both of the following mailing lists:

-   **User's Mailing List** The perfSONAR project maintains a mailing list for communication on matters of installation, configuration, bug reports, or general performance discussions: <https://lists.internet2.edu/sympa/subscribe/perfsonar-user>
-   **Announcement Mailing List** The perfSONAR project also maintains a low volume mailing list used for announcements related to software updates and vulnerabilities: <https://lists.internet2.edu/sympa/subscribe/perfsonar-announce>

#### Changes for perfSONAR 4.0

The final release of perfSONAR 4.0 was put into the perfSONAR repository on April 17, 2017. All sites following our recommendation of having auto-updates enabled should have upgraded during within 1-2 days of that date. This release incorporates possibly the largest single change in perfSONAR’s 15-year history, and the developers spent considerable time making sure it was right.

Highlights include:

-   New scheduling software called pScheduler that provides increased visibility, extensibility and control in the measurement process.
-   CentOS 7 support
-   Debian perfsonar-toolkit bundle support
-   Updated graphs
-   Support for email alerting in MaDDash

For a more complete list of changes, see the full release notes at: <http://www.perfsonar.net/release-notes/version-4-0/>

The [WLCG Network Throughput Working Group](https://twiki.cern.ch/twiki/bin/view/LCG/NetworkTransferMetrics) is responsible for monitoring the WLCG/OSG instances and for defining and maintaining the mesh-configurations that we use to control perfSONAR testing. Please contact them if you have questions or suggestions related to perfSONAR testing amongst WLCG sites.

<span class="twiki-macro STOPINCLUDE"></span>

<span class="twiki-macro BOTTOMMATTER"></span>

-- Main.ShawnMcKee - 12 Sep 2017

