OSG Networking Area
===================

*Welcome to OSG Networking !* This is an entry point for those interested in Networking
in OSG/WLCG or for those OSG/WLCG users experiencing network problems. It provides an
overview of the networking goals, plans and various activities and subtopics underway
regarding networking in the *Open Science Grid (OSG)* and *World-wide LHC Computing Grid (WLCG)*,
operated as a joint project. This area started in June 2012 with initial focus on the network
monitoring as monitoring is critical to provide needed visibility into existing networks and site
connectivity. OSG is working to provide needed networking information and tools for users, sites
and experiments/VOs.

This documentation is divided into several sub-sections, each covering a specific area of activities.

Network Monitoring in WLCG and OSG (perfSONAR)
-----------------------------------------------

WLCG and OSG jointly operate a network of `perfSONAR` agents deployed world-wide, which provides an
open platform that can be used to baseline network performance and debug any potential issues. The
following subsections provide details on the motivation, deployment and operations of the perfSONARs
in WLCG/OSG:

- [Motivation](perfsonar-in-osg.md) - overview, core concepts, motivation
- [Deployment Guide](perfsonar/deployment-models.md) - deployment models and options, hardware requirements
- [Installation and Administration Guide](perfsonar/installation.md) - installation, configuration and maintanance
- [Frequently Asked Questions](perfsonar/faq.md)

Network Troubleshooting
-----------------------

Users with network issues should check the [troubleshooting link](network-troubleshooting.md) below
for initial guidance on how best to get their issue resolved. In addition, you can refer to the
[ESNet network performance guide](https://fasterdata.es.net/performance-testing/troubleshooting/network-troubleshooting-quick-reference-guide/)
for a detailed instructions on how to identify and isolate network performance issues using perfSONAR.

Host and Network Tuning
-----------------------

- [Fasterdata-aligned host/network tuning (EL9)](host-network-tuning.md) — summarizes ESnet guidance and includes an audit/apply script.

Network Services
----------------

OSG operates an advanced platform to collect, store, publish and analyse the network monitoring data it gathers from perfSONAR and other locations. All measurements are collected and available via streaming or through APIs. The following services are available:

- [perfSONAR infrastructure monitoring](perfsonar/psetf.md) - monitors state of perfSONAR network and reports on availability of core services
- [*OSG Distributed Network Datastore*](https://atlas-kibana.mwt2.org/s/networking/app/kibana#/dashboards?notFound=dashboard&_g=()) - distributed datastore based on ElasticSearch holding all the network measurements and providing an API to expose them via JSON is available at two locations (University of Chicago and University of Nebraska).
- *OSG pSConfig Web Admin (PWA)* - centralized configuration of the tests performed by the OSG/WLCG perfSONAR infrastructure . In case you'd like to start/manage particular mesh, please contact our support channels to get access.
- *OSG Dashboards* [http://maddash.aglt2.org](https://maddash.aglt2.org) - set of dashboards showing an overview of the network state as seen by the perfSONAR infrastructure (NOTE: this instance is being deprecated and we plan to introduce dashboards that will replace MaDDash over the coming 2023-2024 year).
- [*WLCG Dashboards*](https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network?var-bin=1h&orgId=16)) - set of dashboards showing WLCG and OSG network performance by combining multiple sources of data including perfSONAR, FTS, ESNet/LHCOPN traffic, etc.

Network Analytics
-----------------

University of Chicago has set up an [**analytics platform**](<https://twiki.cern.ch/twiki/bin/view/AtlasComputing/ATLASAnalytics>) using `ElasticSearch` and `Kibana4` as well as `Jupyter` that can be used to access and analyse all the existing network measurements.

Support and Feedback
--------------------

If you suspect a network problem and wish to follow up on it, we have a number of tools
available. We have a [ToolkitInfo](https://toolkitinfo.opensciencegrid.org/) page that can
help you find resources to identify and explore problems. In general, networks problems are
best resolved by opening a ticket with your site's network provider (see
<https://osg-htc.org/networking/network-troubleshooting/>). If you want WLCG/OSG specific
support, please open a ticket with the appropriate support unit: For `OSG` sites please open
a ticket with [GOC](https://support.opensciencegrid.org/support/home); For `WLCG` sites
please open a [GGUS](https://ggus.eu/) ticket to `WLCG Network Throughput` support unit. If
you'd like to get help in setting up a WLCG/OSG perfSONAR instance please open a ticket with
[GOC](https://support.opensciencegrid.org/support/home) or via [GGUS](https://ggus.eu/) to
WLCG perfSONAR support. If you have problems or questions specific to perfSONAR, please email
the perfSONAR user [mailing list](https://lists.internet2.edu/sympa/info/perfsonar-user). For
any other requests or to provide feedback, please open a ticket at [GGUS](https://ggus.eu/)
and mention OSG networking.

References
----------

- ESNet network performance tuning and debugging <https://fasterdata.es.net/>
- [perfSONAR](http://docs.perfsonar.net/) toolkit is part of the [perfSONAR](https://www.perfsonar.net/) project.
- **OSG/WLCG mesh configuration interface** is available at <https://psconfig.opensciencegrid.org>
- **OSG dashboard instance** <https://maddash.aglt2.org> (NOTE: deprecated replacement)
- **OSG perfSONAR infrastructure monitoring** <https://psetf.aglt2.org/etf/check_mk/>
- **OSG Analytics platform** <https://atlas-kibana.mwt2.org/s/networking/app/kibana>
- **WLCG dashboards** <https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network?var-bin=1h&orgId=16>
