# Infrastructure Monitoring

WLCG/OSG is operating more than 200 perfSONAR agents world-wide. A typical perfSONAR deployment has many services
thatneed to function correctly for the the system to work.  As we scale-up to many perfSONAR deployments across many
sites it can be difficult to verify everything is working correctly. perfSONAR monitoring instance [BROKEN-LINK:
<https://psetf.opensciencegrid.org/etf/check_mk/index.py?start_url=%2Fetf%2Fcheck_mk%2Fdashboard.py>] actively
monitorsthe state of the infrastructure for both remote perfSONAR installation as well as central services. The instance
is based on ETF [BROKEN-LINK: <http://etf.cern.ch/docs/latest/>], which is an open source measurement middleware
forfunctional/availability testing of the resources. In order to access the page you'll need to have x509 grid
certificate loaded in the browser.

A sample initial dashboard is shown below:

![Initial perfSONAR dashboard](../../img/etf.png)

You can use quicksearch in the left pane to search for hostnames, domains or tests. The tests performed can be
dividedinto four categories:

1. *Configuration tests* (`perfSONAR configuration:`) tests if the contact, organisation and meshes were set following

our [installation guide](installation.md).

1. *Service tests* (`perfSONAR services:`) check if different perfSONAR toolkit services are up and running correctly as

well as if ports are reachable from OSG subnets.

1. *Hardware test* (`perfSONAR hardware`) checks if the node conforms to the minimal hardware requirements (see

[Requirements](deployment-models.md) for details)

1. *Freshness tests* (`perfSONAR freshness`) is a high level test that checks what tests are available in the local
   measurement archive and compares this with the tests configured. There can be many different reasons why certain
   testsare stale, such as disfunctional remote perfSONAR nodes, network connectivity issues as well as local issues
   with measurement archive or scheduling, therefore this test is informative and never reaches critical state. A
   special kindof freshness tests are OSG datastore freshness tests, which account for what fraction of tests results
   are stored centrally as compared to local measurement archive. It mainly reflects on the efficiency of the central
   OSG collectorand doesn't provide any information on the on the local services.

This is sample snapshost showing all metrics for particular perfSONAR instance (latency node in this case):
![SampleSnapshot of all metrics for a perfSONAR instance](../../img/etf_page.png)
 For any issues/questions concerning the monitoring pages and tests, please consult the [FAQ](faq.md) Central
servicesare also monitored with the same tool and their status can be seen by following Business Intelligence/All
Aggregations on the left pane. It shows the aggregated status of both production and pre-production services including
meshconfiguration interface, central datastore and infrastructure monitoring.
