### Frequently Asked Questions 

Here we will provide details on troubleshooting perfSONAR installations for OSG and WLCG as well as some additional configuration options and a FAQ.

A good overview of existing tools provided by perfSONAR toolkit and examples how to use them to identify and isolate network problems can be found at https://fasterdata.es.net/performance-testing/troubleshooting/network-troubleshooting-quick-reference-guide/

We are maintaining a [Network Troubleshooting](network-troubleshooting.md) page to guide users in identifying and following up on network problems.

#### Network Troubleshooting

* I suspect there is a network performance issue impacting my site

For OSG sites, please open a ticket with GOC. Otherwise please open a GGUS ticket (or assign an existing) one to WLCG Network Throughput support unit.

#### Infrastructure Monitoring (check\_mk metrics)

* **perfSONAR services: versions** metric is failing.

This metrics checks if your sonar is at the most recent version. Please check if you have automatic yum updates enabled, this is strongly recommended due to security issues we have seen in the past. In case you're still running an older version (3.3-3.5), please update and reconfigure as soon as possible following [Installation Guide](installation.md) 

* **perfSONAR configuration: contacts or location** metrics are failing 

Please check if you have added the administrative information as detailed [here](http://docs.perfsonar.net/install_config_first_time.html#updating-your-administrative-information)

* **perfSONAR services: bwctl/owamp/pscheduler** metrics are failing

This means that we're unable to connect to controller ports of the respective services, please ensure you have correct firewall settings (especially white listed subnets allowed) as described in the [Installation Guide](installation.md) . This can also indicate failures of service daemons, please check <http://www.perfsonar.net/about/faq> for additional details.

* **perfSONAR services: esmond** metric is failing

This means that your measurement archive is not accessible or failing, there can be many possible causes (disk full, httpd not running or inaccessible, etc.), you can ask for help by opening a GGUS ticket to WLCG perfSONAR support. 

* **perfSONAR json summary** is failing
    -   This means the toolkit's homepage is inaccessible, which is required to check many additional services, so in turn all the other metrics will likely be in unknown or critical state. Please check for usual causes (disk full, httpd not running or blocked), we need to be able to access your homepage via HTTP or HTTPS 
    
* **perfSONAR configuration: meshes** metric is failing

This indicates that you're missing the recommended mesh configuration. Please follow mesh configuration as detailed in the [installation guide](installation.md). Also, please REMOVE any old mesh configuration, this metric will also fail in case you have both the new mesh config and the old mesh URLs 

* **perfSONAR services: ntp** is failing

This indicates that NTP service is not running correctly on your sonar, please note that NTP is critical service. Please refer to <http://www.perfsonar.net/about/faq/>

* **perfSONAR services: regular testing/pscheduler** is failing

This indicates that pscheduler is not working correctly. As this is the core daemon please contact WLCG perfSONAR support unit for help.

* There are **many tests failing** for given sonar, where should I start

Please update and reconfigure your sonar following [Installation Guide](installation.md). Please ensure firewall doesn't block access from the whitelisted subnets that are required for the infrastructure monitoring to work. 

* **Where can I get support on managing WLCG perfSONAR** ?

You can open ticket in GGUS to WLCG perfSONAR support unit or contact directly wlcg-perfsonar-support (at cern.ch) 

* **perfSONAR esmond freshness Latency/Bandwidth Direct** is failing or gives warning

This metric checks freshness of the local measurement archive, in particular it checks if it contains fresh results for all the configured tests. This metric is needed to determine if we're able to consistently get results from perfSONAR boxes in WLCG. Currently it's a non-critical test, you can ignore it. 

* **perfSONAR services ndt/npad** is failing

Both metrics check if you have disabled NDT and NPAD. As both NDT and NPAD have been dropped starting with 4.0, this metrics should stay green in most of the cases. 

* **perfSONAR hardware check** is failing

Please consult the minimum and recommended [hardware requirements](deployment-models.md). 
