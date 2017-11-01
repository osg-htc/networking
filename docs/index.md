OSG Networking Area
===================

*Welcome to OSG Networking !* This is an entry point for those interested in Networking in OSG or for those OSG users experiencing network problems. It provides an overview of the networking goals, plans and various activities and subtopics underway regarding networking in the *Open Science Grid (OSG)* and *World-wide LCG Computing Grid (WLCG)*, operated as a joint project. This area started in June 2012 with initial focus on the network monitoring as monitoring is critical to provide needed visibility into existing networks and site connectivity. OSG is working to provide needed networking information and tools for users, sites and experiments/VOs.

This documentation is divided into several sub-sections, each covering a specific area of activities. 

Network Monitoring in WLCG and OSG (perfSONAR)
----------------------------------------------

WLCG and OSG jointly operate a network of `perfSONAR` agents deployed world-wide, which provides an open platform that can be used to baseline network performance and debug any potential issues. The following subsections provide details on the motivation, deployment and operations of the perfSONARs in WLCG/OSG: 

- [Motivation](perfsonar-in-osg.md) - overview, core concepts, motivation
- [Deployment Guide](perfsonar/deployment-models.md) - deployment models and options, hardware requirements
- [Installation and Administration Guide](perfsonar/installation.md) - installation, configuration and maintanance 
- [Frequently Asked Questions](perfsonar/faq.md)

Network Troubleshooting
-----------------------
Users with network issues should check the [troubleshooting link](network-troubleshooting.md) below for initial guidance on how best to get their issue resolved. In addition, you can refer to the [ESNet network performance guide](https://fasterdata.es.net/performance-testing/troubleshooting/network-troubleshooting-quick-reference-guide/) for a detailed instructions on how to identify and isolate network performance issues using perfSONAR.

Network Services 
----------------

OSG operates an advance platform to collect, store, publish and analyse the network monitoring data it gathers from perfSONAR and other locations. All measurements are collected and available via streaming or through APIs. The following services are available:

- [perfSONAR infrastructure monitoring](perfsonar/psetf.md) - monitors state of perfSONAR network and reports on availability of core services
- *OSG Network Datastore* - central datastore holding all the network measurements and providing an API to expose them via JSON. Datastore is based on [ESMOND](http://software.es.net/esmond/), which supports the following [API](http://software.es.net/esmond/perfsonar_client_rest.html) and runs at this [endpoint](http://psds.grid.iu.edu/esmond/perfsonar/archive/?format=json).
- *OSG Network Stream* - access to network measurements in near realtime is provided by the GOC RabbitMQ and CERN ActiveMQ messaging brokers.
- *OSG Mesh Configuration Interface (MCA)* - centralized configuration of the tests performed by the OSG/WLCG perfSONAR infrastructure (see [MCA](http://docs.perfsonar.net/mca.html) for details). In case you'd like to start/manage particular mesh, please contact our support channels to get access.
- [*OSG Dashboards*](http://psmad.grid.iu.edu/maddash-webui/index.cgi) - set of dashboards showing an overview of the network state as seen by the perfSONAR infrastructure 
- [*WLCG Dashboards*](http://monit-grafana-open.cern.ch/dashboard/db/home?orgId=16) - set of dashboards showing WLCG and OSG network performance by combining multiple sources of data including perfSONAR, FTS, ESNet/LHCOPN traffic, etc. 

Network Analytics
-----------------
University of Chicago has setup an [**analytics platform**](<https://twiki.cern.ch/twiki/bin/view/AtlasComputing/ATLASAnalytics>) using `ElasticSearch` and `Kibana4` as well as `Jupyter` that can be used to access and analyse all the existing network measurements.

Support and Feedback
--------------------
If you suspect a network problem and wish to follow up on it, please open a ticket with the appropriate support unit: For `OSG` sites please open a ticket with [GOC](http://ticket.grid.iu.edu/submit); For `WLCG` sites please open a [GGUS](https://ggus.eu/) ticket to `WLCG Network Throughput` support unit. If you'd like to get help in setting up or debugging perfSONAR instance please open a ticket with [GOC](http://ticket.grid.iu.edu/submit) or via [GGUS](https://ggus.eu/) to WLCG perfSONAR support. For any other requests please contact [GOC](http://ticket.grid.iu.edu/submit).


References
----------
- ESNet network performance tuning and debugging <https://fasterdata.es.net/>
- [perfSONAR](http://docs.perfsonar.net/) toolkit is part of the [perfSONAR](http://www.perfsonar.net/) project. 
- **OSG/WLCG mesh configuration interface** is available at http://meshconfig.grid.iu.edu 
- Information on **ESmond** is available at <http://software.es.net/esmond/>
- Information on querying the perfSONAR data from ESmond is at <http://software.es.net/esmond/perfsonar_client_rest.html>
- Access to a JSON view of the **OSG network datastore** is available at <http://psds.grid.iu.edu/esmond/perfsonar/archive/?format=json>
- **OSG dashboard instance** <http://psmad.grid.iu.edu/maddash-webui/index.cgi>
- **OSG perfSONAR infrastructure monitoring** <https://psetf.grid.iu.edu/etf/check_mk/>
- **OSG Analytics platform** <http://atlas-kibana.mwt2.org:5601/app/kibana#/dashboard/Default?_g=()>
- **WLCG dashboards** http://monit-grafana-open.cern.ch/dashboard/db/home?orgId=16
- **PuNDIT** (an OSG Satellite project) focusing on analyzing perfSONAR data to alert on problems: <http://pundit.gatech.edu/>
- **MadAlert** which analyzes **MaDDash** meshes to identify network problems: <http://madalert.aglt2.org/madalert/>


