# OSG Networking Area

*Welcome to OSG Networking!* This is your entry point for networking in the *Open Science Grid (OSG)* and *World-wide
LHC Computing Grid (WLCG)*. Whether you're deploying perfSONAR, troubleshooting network issues, or exploring our
monitoring infrastructure, we've organized the documentation around common user journeys.

## Get Started

Choose the path that matches your goal:

### :rocket: Deploy perfSONAR

Quick, tested steps to deploy perfSONAR for OSG/WLCG monitoring.

Choose your deployment type:

- **Testpoint (Container)** - Lightweight, recommended for most sites
- **Toolkit (RPM)** - Full-featured with local web UI and archive

- **Time:** 30-90 minutes depending on type

- **Skill level:** Systems administrator

**→ [Quick Deploy Guide](personas/quick-deploy/landing.md)**

---

### :wrench: Troubleshoot Network Issues

Triage checklist and playbooks for diagnosing network problems.

- **Time:** Variable

- **Skill level:** Network operator/admin

**→ [Troubleshooting Guide](personas/troubleshoot/landing.md)**

---

### :telescope: Understand the System

Architecture, data pipelines, and research documentation.

- **Time:** Reading/reference

- **Skill level:** Developer/researcher

**→ [Architecture & Research](personas/research/landing.md)**

---

## About OSG/WLCG Network Monitoring

WLCG and OSG jointly operate a worldwide network of `perfSONAR` agents that provide an open platform for baselining
network performance and debugging issues. This monitoring infrastructure is critical for providing visibility into
networks and site connectivity.

**Key capabilities:**

- Automated bandwidth and latency testing between sites

- Centralized measurement storage and analytics

- Integration with WLCG/OSG dashboards and alerting

- Community-maintained test meshes

**[Learn more about perfSONAR in OSG/WLCG →](perfsonar-in-osg.md)**

## Network Services & Data

OSG operates an advanced platform to collect, store, publish and analyze network monitoring data from perfSONAR and
other sources. All measurements are available via streaming APIs and dashboards:

- **[perfSONAR Infrastructure Monitoring](perfsonar/psetf.md)** - monitors perfSONAR network health and service availability

- **[OSG Network Datastore](osg-network-services.md)** - distributed ElasticSearch datastore with JSON API (University of Chicago and University of Nebraska)

- **OSG pSConfig Web Admin** - centralized test mesh configuration (contact support for access)

- **[WLCG Dashboards](https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network?var-bin=1h&orgId=16)** - comprehensive performance dashboards combining perfSONAR, FTS, and network traffic data

- **[Analytics Platform](osg-network-analytics.md)** - ElasticSearch/Kibana/Jupyter for analyzing measurements

!!! note "MaDDash Deprecation" The legacy MaDDash instance at maddash.aglt2.org is deprecated. Use WLCG Grafana
dashboards instead.

## Support and Feedback

**For network problems:**

1. Start with the [Troubleshooting Guide](network-troubleshooting.md) or [ToolkitInfo](https://toolkitinfo.opensciencegrid.org/)

1. Contact your site's network provider

1. For OSG-specific support: [GOC ticket](https://support.opensciencegrid.org/support/home)

1. For WLCG-specific support: [GGUS ticket](https://ggus.eu/) to "WLCG Network Throughput" or "WLCG perfSONAR support"

**For perfSONAR questions:** [perfSONAR user mailing list](https://lists.internet2.edu/sympa/info/perfsonar-user)

## Quick Links

- [perfSONAR Documentation](https://docs.perfsonar.net/) | [perfSONAR Project](https://www.perfsonar.net/)

- [ESNet Fasterdata Guide](https://fasterdata.es.net/)

- [OSG/WLCG Mesh Configuration](https://psconfig.opensciencegrid.org)

- [perfSONAR Infrastructure Monitoring](https://psetf.aglt2.org/etf/check_mk/)

- [OSG Analytics Platform](https://atlas-kibana.mwt2.org/s/networking/app/kibana)

- [WLCG Grafana Dashboards](https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network?var-bin=1h&orgId=16)
