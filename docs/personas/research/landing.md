---
title: "Researcher — Architecture & Analytics"
description: "Background, architecture, data pipeline, and analytics for OSG perfSONAR monitoring."
persona: research
owners: ["networking-team@osg-htc.org"]
status: active
tags: [architecture, research, analytics, data-pipeline]
---

# 🔭 Researcher — Architecture & Analytics

Understand the OSG/WLCG network monitoring system, access data, and explore insights.

---

## System Architecture

### High-Level Overview

**[Architecture Overview](architecture.md)** — components, responsibilities, and system design

The perfSONAR network consists of:
- **Testpoints** — distributed measurement agents at OSG/WLCG sites
- **Collection Pipeline** — HTTP-Archiver ingestion and Logstash processing
- **Data Storage** — Central Elasticsearch instances (distributed for
  resilience)
- **Configuration Services** — pSConfig for centralized test mesh management
- **Monitoring** — PSETF for infrastructure health and visibility

### Data Flow: From Measurement to Insight

1. **Measurement** (2-minute intervals)
   - perfSONAR testpoints run periodic latency, bandwidth, traceroute tests
   - Tests configured by central mesh at `psconfig.opensciencegrid.org`

2. **Collection** (near real-time)
   - Results sent to central Elasticsearch via HTTP-Archiver
   - Logstash processes and enriches measurement metadata

3. **Storage** (permanent)
   - **[OSG Network Datastore](../../osg-network-services.md)** — distributed Elasticsearch storage
   - JSON API for direct programmatic access

4. **Analysis** (on-demand)
   - **[OSG Analytics Platform](../../osg-network-analytics.md)** — Kibana dashboards + Jupyter notebooks
   - Custom queries, time-series analysis, anomaly detection

5. **Visualization** (real-time dashboards)
   - **[WLCG Dashboards](https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network)** — performance monitoring
   - Site-to-site path performance, latency trends, bandwidth utilization

---

## Accessing & Analyzing Data

### Real-Time Dashboards

**[WLCG Grafana Dashboards](https://monit-grafana-open.cern.ch/d/MwuxgogIk/wlcg-site-network?var-bin=1h&orgId=16)**
- Network performance by site and path
- Latency, bandwidth, packet loss trends
- Time-series filtering and drill-down

**[OSG PSETF Monitoring](https://psetf.aglt2.org/etf/check_mk/)**
- perfSONAR infrastructure health
- Testpoint availability and service status
- Test execution success rates

**[OSG Analytics Platform](https://atlas-kibana.mwt2.org/s/networking/app/kibana)**
- Custom Kibana queries
- Ad-hoc measurement exploration
- Jupyter notebooks for advanced analysis

### Programmatic Access

**Elasticsearch API**
- **[OSG Network Datastore](../../osg-network-services.md)** — detailed API documentation
- JSON endpoints for direct queries
- Available at: University of Chicago and University of Nebraska instances

**Example query:**
```bash
curl -X GET "elasticsearch-server:9200/perfsonar-testpoint/_search" \
  -H 'Content-Type: application/json' \
  -d '{"query": {"match": {"agent": "testpoint.example.com"}}}'
```

**Jupyter Notebooks**
- Available on analytics platform
- Pre-built examples for common analysis tasks
- Python libraries: pandas, numpy, matplotlib for data science workflows

**pSConfig API**
- **[Central Mesh Configuration](https://psconfig.opensciencegrid.org)** — test definitions and schedule
- JSON endpoints for retrieving test configurations
- Dynamic mesh membership and test parameters

---

## Analyzing Network Measurements

### Questions You Can Answer

**Performance Characterization:**
- Which network paths have persistent latency issues?
- What's the peak and sustained bandwidth between sites?
- How has network performance trended over the past month/year?
- Are there time-of-day or day-of-week patterns?

**Infrastructure Health:**
- Which perfSONAR testpoints are most active?
- What's the geographic distribution of measurement agents?
- Are there coverage gaps (missing paths)?

**Root Cause Analysis:**
- Did network performance degrade after a specific event?
- Correlate measurements with known network changes
- Identify bottlenecks in multi-hop paths

### Tools & Resources

**Data Analysis:**
- **Kibana** — query, filter, and visualize Elasticsearch data
- **Jupyter** — Python/pandas for advanced statistical analysis
- **Grafana** — time-series visualization and alerting

**Measurement Understanding:**
- **[perfSONAR Documentation](https://docs.perfsonar.net/)** — test definitions, data formats
- **[ESnet Network Tools](https://fasterdata.es.net/)** — methodology and best practices
- **Measurement Archive** — historical data storage and retrieval

**Community Resources:**
- **[perfSONAR Mailing List](https://lists.internet2.edu/sympa/info/perfsonar-user)** — research collaborations
- **[WLCG Network WG](https://twiki.cern.ch/twiki/bin/view/LCG/NetworkTransferMetrics)** — mesh governance

---

## Contributing & Development

### Adding New Measurements or Tests

Propose new tests to the **[WLCG Mesh Configuration](https://twiki.cern.ch/twiki/bin/view/LCG/NetworkTransferMetrics)**:
- Define measurement parameters and schedule
- Request inclusion in production mesh
- Community review and approval

**Or deploy local tests:**
- Add custom tests via your testpoint's pSConfig web interface
- Share configurations with the community

### Improving the Infrastructure

**Source code and development:**
- **[GitHub: osg-htc/networking](https://github.com/osg-htc/networking)** — documentation, scripts, and automation
- **[GitHub: perfsonar/perfsonar](https://github.com/perfsonar/perfsonar)** — core perfSONAR software
- **[Issues & Discussions](https://github.com/osg-htc/networking/issues)** — feature requests and bug reports

**Contributing:**
- Submit pull requests for improvements
- Report issues and propose enhancements
- Email: networking-team@osg-htc.org

### Architecture & Documentation

**Want to contribute diagrams, data pipeline notes, or architecture updates?**
- Add diagrams or notes to `personas/research/`
- Submit via GitHub PR or email networking-team@osg-htc.org
- All contributions welcome and attributed

---

## Related Topics

### Infrastructure & Services
- **[Network Services & Data](../../osg-network-services.md)** — datastore architecture and details
- **[Network Analytics](../../osg-network-analytics.md)** — analytics platform overview
- **[perfSONAR Infrastructure Monitoring](../../perfsonar/psetf.md)** — PSETF system and health checks
- **[pSConfig Web Admin](https://psconfig.opensciencegrid.org)** — centralized test configuration

### Foundational Concepts
- **[perfSONAR in OSG/WLCG](../../perfsonar-in-osg.md)** — motivation and importance
- **[Deployment Models](../../perfsonar/deployment-models.md)** — testpoint architecture
- **[Installation Guide](../../perfsonar/installation.md)** — for setting up your own measurement agent

### Tools & Technical Details
- **[Tools & Scripts](../../perfsonar/tools_scripts/README.md)** — orchestration and management tools
- **[Host Tuning](../../host-network-tuning.md)** — performance optimization for measurement hosts
- **[perfSONAR FAQ](../../perfsonar/faq.md)** — technical questions answered
