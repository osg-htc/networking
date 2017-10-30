OSG Networking Area
===================

*Welcome to OSG Networking !* This is an entry point for those interested in Networking in OSG or for those OSG users experiencing network problems. It provides an overview of the networking goals, plans and various activities and subtopics underway regarding networking in the Open Science Grid (OSG) and World-wide LCG Computing Grid (WLCG), operated as a joint project. This area started in June 2012 with initial focus on the network monitoring as monitoring is critical to provide needed visibility into existing networks and site connectivity. OSG is working to provide needed networking information and tools for users, sites and experiments/VOs.

This documentation is divided into several sub-sections, each covering a specific area of activities. 

Network Monitoring in WLCG and OSG (perfSONAR)
----------------------------------------------

WLCG and OSG jointly operate a network of perfSONAR agents deployed world-wide, which provides an open platform that can be used to baseline network performance and debug any potential issues. The following subsections provide details on the motivation, deployment and operations of the perfSONARs in WLCG/OSG: 
- [Motivation](perfsonar-in-osg.md)
- [Deployment Guide](perfsonar/deployment-models.md) - deployment models and options, hardware requirements
- [Installation and Administration Guide](perfsonar/installation.md) - installation, configuration and maintanance 
- [Frequently Asked Questions](perfsonar/faq.md)

Network Troubleshooting
-----------------------
Users with network issues should check the [troubleshooting link](network-troubleshooting.md) below for initial guidance on how best to get their issue resolved. In addition, you can refer to the [ESNet network performance guide](https://fasterdata.es.net/performance-testing/troubleshooting/network-troubleshooting-quick-reference-guide/) for a detailed instructions on how to identify and isolate network performance issues using perfSONAR.

OSG Network Service 
-------------------

OSG operates an advance platform to collect, store, publish and analyse the network monitoring data it gathers from perfSONAR and other locations. All measurements are collected and available via streaming or through APIs. The following services are available:
- [perfSONAR infrastructure monitoring](perfsonar/psetf.md) - collects data on existing perfSONAR network, monitors its state and reports on availability of core services
- *OSG Network Datastore* - central datastore holding all the network measurements and providing an API to expose them via JSON. Datastore is based on [ESMOND](http://software.es.net/esmond/), which supports the following [API](http://software.es.net/esmond/perfsonar_client_rest.html) and runs at this [endpoint](http://psds.grid.iu.edu/esmond/perfsonar/archive/?format=json).
- *OSG Network Stream* - access to network measurements in near realtime is provided by the GOC RabbitMQ and CERN ActiveMQ messaging brokers.
- *OSG Dashboards* - set of dashboards showing an overview of the network state as seen by the perfSONAR infrastructure (http://psmad.grid.iu.edu/maddash-webui/index.cgi)
- *WLCG Dashboards* - set of dashboards showing WLCG and OSG network performance by combining multiple sources of data including perfSONAR, FTS, ESNet/LHCOPN traffic, etc. (http://monit-grafana-open.cern.ch/dashboard/db/home?orgId=16)

Network Analytics
-----------------
TBA

Networking References
---------------------
The [perfSONAR](http://docs.perfsonar.net/) toolkit is part of the [perfSONAR](http://www.perfsonar.net/) project. The current perfSONAR-PS toolkit is [available for download](http://docs.perfsonar.net/install_getting.html). 

OSG supports a number of services for networking including a **central datastore** which hosts all the OSG/WLCG perfSONAR data.

-   Information on ESmond is available at <http://software.es.net/esmond/>
-   Information on querying the perfSONAR data from ESmond is at <http://software.es.net/esmond/perfsonar_client_rest.html>
-   Access to a JSON view of the OSG network datastore is available at <http://psds.grid.iu.edu/esmond/perfsonar/archive/?format=json>

We can monitor the OSG network metrics using **MaDDash** (ESnet's Monitoring and Diagnostic Dashboard)

-   OSG **MaDDash** instance <http://psmad.grid.iu.edu/maddash-webui/index.cgi>

The **basic service checking** to track and monitor all our perfSONAR services uses `OMD/Check_mk`. NOTE: You need an x.509 credential in your browser to view this

-   `OSG OMD/Check_MK` service monitoring <https://psetf.grid.iu.edu/etf/check_mk/>

Ilija Vukotic/University of Chicago has setup an **analytics platform** (<https://twiki.cern.ch/twiki/bin/view/AtlasComputing/ATLASAnalytics>) using `Elastic Search` and `Kibana4`.

-    Here is the `Kibana4` web interface <http://atlas-kibana.mwt2.org:5601/app/kibana#/dashboard/Default?_g=()>

ESnet maintains an excellent set of pages about networking, end-system tuning, tools and techniques at <https://fasterdata.es.net/>

The are two related projects for OSG Networking

-   **PuNDIT** (an OSG Satellite project) focusing on analyzing perfSONAR data to alert on problems: <http://pundit.gatech.edu/>
-   **MadAlert** which analyzes **MaDDash** meshes to identify network problems: <http://madalert.aglt2.org/madalert/>


