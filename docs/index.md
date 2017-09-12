OSG Networking Area
===================

Welcome to the home page of the OSG Networking Team documentation area! This is currently a work in progress as we migrate our TWiki documentation to GitHub. If you are looking for our full documentation, please visit the [TWiki](https://twiki.opensciencegrid.org/bin/view/Documentation/NetworkingInOSG).

<span class="twiki-macro ICON">hand</span> \*Welcome to OSG Networking\* This is the entry point for those interested in Networking in OSG or for those OSG users experiencing network problems. It provides an overview of the networking goals, plans and various activities and subtopics underway regarding networking in the Open Science Grid. This area for OSG started in June 2012 and initially focused on network monitoring. Monitoring is critical to provide needed visibility into existing networks and site connectivity. OSG is working to provide needed networking information and tools for OSG users, sites and VOs.

Users with network issues should check the [troubleshooting link](network-troubleshooting) below for guidance on how best to get their issue resolved.

perfSONAR Deployment Details for WLCG and OSG
---------------------------------------------

We have created a set of pages to guide the deployment of perfSONAR for use by WLCG and OSG. Please refer to DeployperfSONAR to find details about installing updating and user perfSONAR in these communities.

OSG Networking Components
-------------------------

The plans for OSG networking include activity in these areas related to network monitoring:

-   The perfSONAR toolkit: development, packaging, configuring and supporting the toolkit in the context of OSG but potentially applicable to a diverse set of users and VOs.
-   The OSG Network Service: targeting the development, packaging, deployment and maintenance of a network service which collects, aggregates, displays and provides network related metrics from the perfSONAR toolkit deployments at OSG and WLCG sites.
-   [Network problem solving documentation](https://twiki.opensciencegrid.org/bin/view/Documentation/NetworkingTroubleShooting): Updating and augmenting OSG documentation related to network problem troubleshooting using OSG distributed tools, software and services.

Other Useful Networking References
----------------------------------

OSG supports a number of services for networking including a **central ESmond datastore** which hosts all the OSG/WLCG perfSONAR data.

-   Information on ESmond is available at <http://software.es.net/esmond/>
-   Information on querying the perfSONAR data from ESmond is at <http://software.es.net/esmond/perfsonar_client_rest.html>
-   Access to a JSON view of the OSG network datastore is available at <http://psds.grid.iu.edu/esmond/perfsonar/archive/?format=json>

We can monitor the OSG network metrics using **MaDDash** (ESnet's Monitoring and Diagnostic Dashboard)

-   OSG **MaDDash** instance <http://psmad.grid.iu.edu/maddash-webui/index.cgi>

The **basic service checking** to track and monitor all our perfSONAR services uses `OMD/Check_mk`. NOTE: You need an x.509 credential in your browser to view this

-   `OSG OMD/Check_MK` service monitoring <https://psomd.grid.iu.edu/WLCGperfSONAR/check_mk/>

The [perfSONAR](http://docs.perfsonar.net/) toolkit is part of the [perfSONAR](http://www.perfsonar.net/) project. The current perfSONAR-PS toolkit is [available for download](http://docs.perfsonar.net/install_getting.html)

Ilija Vukotic/University of Chicago has setup an **analytics platform** (<https://twiki.cern.ch/twiki/bin/view/AtlasComputing/ATLASAnalytics>) using `Elastic Search` and `Kibana4`.

-    Here is the `Kibana4` web interface <http://cl-analytics.mwt2.org:5601/>

ESnet maintains an excellent set of pages about networking, end-system tuning, tools and techniques at <https://fasterdata.es.net/>

The are two related projects for OSG Networking

-   **PuNDIT** (an OSG Satellite project) focusing on analyzing perfSONAR data to alert on problems: <http://pundit.gatech.edu/>
-   **MadAlert** which analyzes **MaDDash** meshes to identify network problems: <http://madalert.aglt2.org/madalert/>

**Comments**
------------

<span class="twiki-macro COMMENT" type="tableappend"></span>

-- Main.ShawnMcKee - 09 Sep 2012

