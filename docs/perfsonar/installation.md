# perfSONAR Installation Guide

!!! warning "Legacy Documentation - Modern Approach Available"

This page contains **legacy instructions** for traditional Toolkit installations. As of October 2025, the **recommended
approach** is containerized testpoint deployment.

**👉 For new installations, use the [Quick Deploy Guide](../personas/quick-deploy/install-perfsonar-testpoint.md)

instead.**

This legacy guide is maintained for existing Toolkit installations and special cases requiring the full web interface.

This page documents installing/upgrading **perfSONAR** for OSG and WLCG sites. In case this is the first time you're
trying to install and integrate your perfSONAR into WLCG or OSG, please consult our [overview](../perfsonar-in-osg.md)
and possible [deployment options](deployment-models.md) before installing. For troubleshooting an existing installation
please consult official [Troubleshooting Guide](http://docs.perfsonar.net/troubleshooting_overview.html),
[FAQ](http://docs.perfsonar.net/FAQ.html) as well as WLCG/OSG specific [FAQ](faq.md).

For any questions or help with WLCG perfSONAR setup, please contact
[GGUS](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ) WLCG perfSONAR support unit or OSG
[GOC](http://support.opensciencegrid.org). We strongly recommend anyone maintaining/using perfSONAR to join [perfsonar-
user](https://lists.internet2.edu/sympa/subscribe/perfsonar-user) and [perfsonar-
announce](https://lists.internet2.edu/sympa/subscribe/perfsonar-announce) mailing lists.

## Installation or Upgrade

Prior to installing please consult the [release notes](https://www.perfsonar.net/docs_releasenotes.html)) for the latest
available release. In case you have already an instance running and wish to re-install/update it then please follow our
recommendations:

* Upgrades: We recommend *reinstalling* using an EL9 (RHEL,Rocky,Alma) OS for all sites already running a registered instance or planning new installation. The primary reason for this recommendation is to provide a long-term supported OS and to benefit from a 5.x kernel.

* perfSONAR team provides support for Debian9 and Ubuntu as well, but we recommend to use EL9 to have a common, well understood deployment.

* *Local measurement archive backup is not needed* as OSG/WLCG stores all measurements centrally.

* In case you plan to deploy a single bare metal node with multiple NICs, please consult [Multiple NIC Guidance](deployment-models.md)

First, install your chosen EL9 operating system on your host after saving you local configuration if you are "updating".

The following options are then recommended to install perfSONAR for OSG/WLCG:

| Installation method              | Link |
|----------------------------------|----------------------------------------------------------------------------------|
| Toolkit bundle installation      | [Toolkit Installation Quick
Start](https://docs.perfsonar.net/install_quick_start.html) | | Testpoint bundle installation    | Follow quick start
above but do `dnf install perfsonar-testpoint` instead of toolkit |

You can see more details about EL supported installs at <https://docs.perfsonar.net/install_el.html>

!!! note

```text In all cases, we strongly recommend keeping auto-updates enabled. With yum auto-updates there is a possibility
that updated packages can "break" your perfSONAR install but this risk is accepted in order to have security updates
quickly applied.
``` text

The following *additional* steps are needed to configure the toolkit to be used in OSG/WLCG in addition to the steps
described in the official guide:

* Please register your nodes in GOCDB/OIM. For OSG sites, follow the details in OSG Topology below. For non-OSG sites, follow the details in [GOCDB](#register-perfsonar-service-in-gocdb)

* Please ensure you have added or updated your [administrative information](http://docs.perfsonar.net/manage_admin_info.html)

* You will need to configure your instance(s) to use the OSG/WLCG mesh-configuration. Please follow the steps below:


```

* For toolkit versions 5.0 and higher run: `psconfig remote add https://psconfig.opensciencegrid.org/pub/auto/<FQDN>` replacing `<FQDN>` with your host (e.g. `psum01.aglt2.org`). Verify with `psconfig remote list`.


``` text

```json === pScheduler Agent === [ { "url" : "<https://psconfig.opensciencegrid.org/pub/auto/psum01.aglt2.org">
"configure-archives" : true } ]
```

* Please remove any old/stale URLs using `psconfig remote delete <URL>`

* If this is a **new instance** or you have changed the node's FQDN, you will need to notify `wlcg-perfsonar-support 'at' cern.ch` to add/update the hostname in one or more test meshes, which will then auto-configure the tests. Please indicate if you have preferences for which meshes your node should be included in (USATLAS, USCMS, ATLAS, CMS, LHCb, Alice, BelleII, etc.). You could also add any additional local tests  via web interface (see [Configuring regular tests](http://docs.perfsonar.net/manage_regular_tests.html) for details). Please check which tests are auto-added via central meshes before adding any custom tests to avoid duplication.

!!! note

```text Until your host is added on <https://psconfig.opensciencegrid.org> to one or more meshes by an administrator the
automesh configuration above will not return any tests.
``` text

* We **strongly recommend** configuring perfSONAR in **dual-stack mode** (both IPv4 and IPv6). In case your site has IPv6 support, the only necessary step is to get both A and AAAA records for your perfSONAR DNS names (as well as ensuring the reverse DNS is in place).

* Adding *communities* is optional, but if you do, we recommend putting in WLCG as well as your VO: `ATLAS`, `CMS`, etc. This just helps others from the community lookup your instances in the public lookup service. As noted in the documentation you can select from already registered communities as appropriate.

* Please check that both **local and campus firewall** has the necessary [port openings](#security-considerations). Local iptables are configured automatically, but there are ways how to tune the existing set, please see the official [firewall](http://docs.perfsonar.net/manage_security.html#adding-your-own-firewall-rules) guide for details.

* Once installation is finished, please **reboot** the node.

For any further questions, please consult official [Troubleshooting
Guide](http://docs.perfsonar.net/troubleshooting_overview.html), [FAQ](http://docs.perfsonar.net/FAQ.html) as well as
WLCG/OSG specific [FAQ](faq.md) or contact directly WLCG or OSG perfSONAR support units.

### Maintenance

Provided that you have enabled auto-updates, the only thing that remains is to follow up on any kernel security issues
and either patch the node as soon as possible or reboot once the patched kernel is released.

In case you'd like to manually update the node please follow the official
[guide](http://docs.perfsonar.net/manage_update.html).

Using automated configuration tools (such as Chef, Puppet, etc) for managing perfSONAR are not officially supported, but
there are some community driven projects that could be helpful, such as [HEP-Puppet](<http://github.com/HEP-
Puppet/perfsonar>). As perfSONAR manages most of its configuration automatically via packages and there is very little
initial configuration needed, we suggest to keep automated configuration to the minimum necessary to avoid unncessary
interventions after auto-updates.

### Security Considerations

The perfSONAR toolkit is reviewed both internally and externally for security flaws and the official documentation
provides a lot of information on what security software is available and what firewall ports need to be opened, please
see [Manage Security](http://docs.perfsonar.net/manage_security.html) for details. The toolkit's purpose is to allow us
to measure and diagnose network problems and we therefore need to be cautious about blocking needed functionality by
site or host firewalls.   An overview of perfSONAR security is available at
<https://www.perfsonar.net/deployment_security.html>

!!! warning

```text All perfSONAR instances must have port 443 accessible to other perfSONAR instances. Port 443 is used by
pScheduler to schedule tests. If unreachable, tests may not run and results may be missing.
```

For sites that are concerned about having port 443 open, there is a possiblity to get a list of hosts to/from which the
tests will be initiated. However as this list is dynamic, implementing the corresponding firewall rules would need to be
done both locally and on the central/campus firewall in a way that would ensure dynamic updates. It's important to
emphasize that port 443 provides access to the perfSONAR web interface as well, which is very useful to users and
network administrators to debug network issues.

!!! warning

```text If you have a central/campus firewall verify required port openings in the perfSONAR security documentation.
``` text

### Enabling SNMP plugins

Starting from release 4.0.2, perfSONAR toolkit allows to configure passive SNMP traffic from the local routers to be
captured and stored in the local measurement archive. This is currently a [beta
feature](http://www.perfsonar.net/release-notes/version-4-0-2/) that needs further testing and we're looking for
volunteers willing to test, please let us know in case you would be interested.

### Register perfSONAR Service in GOCDB

This section describes how to register the perfSONAR service in GOCDB.

In order to register you perfSONAR services in GOCDB, you should access the proper section of GOC for adding a Service
Endpoint

* <https://goc.egi.eu/portal/index.php?Page_Type=New_Service_Endpoint>

You might not be able to access the page if you are not properly registered in GOC, so a snapshot can be found below. In
filling the information please follow those simple guidelines:

* There are two service types for perfSONAR: net.perfSONAR.Bandwidth and net.perfSONAR.Latency. This is because we suggest t install two perfSONAR boxes at the site (one for latency tests and one for bandwidth tests) and therefore two distinct service endpoints should be published with two distinct service types. If the site can not afford sufficient hardware for the proposed setup, it can install a unique perfSONAR box, but still should publish both services types (with the same host in the "host name" field of the form).

* For each form (service type) fill at least:


```

* Hosting Site

* Service Type

* Host Name

* Host IP (optional)

* Description (optional label used in MaDDash; keep short and unique)


``` text

* Check "N" when asked "Is it a beta service"

* Check "Y" when asked "Is this service in production"

* Check "Y" when asked "Is this service monitored"

<!-- -->

* GOCDB screen shot for creating a Service Endpoint:

![GOCDB screen shot for creating a Service Endpoint](../../img/Screen_shot_2013-02-19_at_15.26.52.png)

### Register perfSONAR in OSG Topology

Each *OSG site* should have two perfSONAR instances (one for Latency and one for Bandwidth) installed to enable network
monitoring. These instances should be located as "close" (in a network-sense) as possible to the site's storage. If a
logical site is comprised of more than one physical site, each physical site should be instrumented with perfSONAR
instances.

To add hosts to OSG Topology, please follow the instructions at <<https://osg-htc.org/docs/common/registration/>>

If you have problems or questions please consult our [FAQ](faq.md) or alternatively open a ticket with GOC.
