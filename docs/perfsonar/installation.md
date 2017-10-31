## perfSONAR Installation Guide 

This page documents installing/upgrading **perfSONAR** for OSG and WLCG sites. In case this is the first time you're trying to install and integrate your perfSONAR into WLCG or OSG, please consult an [overview](perfsonar-in-osg.md) and possible [deployment options](perfsonar/deployment-models.md) before installing. For troubleshooting an existing installation please consult [FAQ](perfsonar/faq.md).

For any questions or help with WLCG perfSONAR setup, please contact [GGUS](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ) WLCG perfSONAR support unit or OSG [GOC](). We strongly recommend anyone maintaining/using perfSONAR to join [perfsonar-user](https://lists.internet2.edu/sympa/subscribe/perfsonar-user) and [perfsonar-announce](https://lists.internet2.edu/sympa/subscribe/perfsonar-announce) mailing lists.

### Installation

Prior to installing please consult the [release notes](http://docs.perfsonar.net/manage_update.html#special-upgrade-notes). In case you have already an instance running and wish to update it then please consult our recommendations:

* For sites the are currently registered but not yet updated to 4.0 we would strongly recommend reinstalling using CentOS 7. The primary reason for this recommendation is that the next point release of perfSONAR (4.1) will no longer support RHEL6/CentOS6/Scientific Linux 6.
* perfSONAR team provides support for Debian9 and Ubuntu as well, but we recommend to use CentOS7 as this is the most common and best understood deployment.
* Please backup `/etc/perfsonar/meshconfig-agent.conf`, which contains the current configuration
* Local measurement archive backup is not needed as OSG/WLCG stores all ,easurements centrally. In case you'd like to perform the backup  anyway please follow the [migration guide](http://docs.perfsonar.net/install_migrate_centos7.html).

There are two options to install perfSONAR toolkit, you can either use meta-package/bundle installation on an existing Centos7 or use an image. For bundle installation please follow the [bundle installation guide](http://docs.perfsonar.net/install_centos.html), for ISO image installation please follow the [toolkit full install guide](http://docs.perfsonar.net/install_centos_fullinstall.html) or [net install guide](http://docs.perfsonar.net/install_centos_netinstall.html). 

!!! note
In all cases, we **strongly recommend to enable auto-updates** during the installation process to keep the node up to date and reboot it after critical kernel updates are announced. With `yum` auto-updates in place there is a possibility that updated packages can "break" your perfSONAR install but this is viewed an acceptable risk in order to have security updates quickly applied on perfSONAR instances. 

The following additional steps are needed to configure the toolkit to be used in OSG/WLCG in addition to the steps described in the official guide:

1. Please register your nodes in GOCDB/OIM. For OSG sites, follow the details in [OIM](register-ps-in-oim). For non-OSG sites, follow the details in [GOCDB](register-ps-in-gocdb)
2. Please ensure you have added or updated your [administrative information](http://docs.perfsonar.net/manage_admin_info.html)
3. Adding communities is optional, but we recommend putting in WLCG as well as your VO: `ATLAS`, `CMS`, etc. This just helps others from the community lookup your instances in the lookup service. As noted in the documentation you can select from already registered communities as appropriate.
4. You will need to configure your instance(s) to use the OSG/WLCG mesh-configuration. If this is a re-installation you can just revert from backup the file `/etc/perfsonar/meshconfig-agent.conf`. Otherwise please set it to contain the following: 
   * Add a mesh section with configuration_url pointing to `http://meshconfig.grid.iu.edu/pub/auto/<FQDN>` Replace `<FQDN>` with the fully qualified domain name of your host, e.g., `psum01.aglt2.org`.
   * Below is an example set of lines for meshconfig-agent.conf
    ```
       <mesh> 
        configuration_url http://meshconfig.grid.iu.edu/pub/auto/psum01.aglt2.org
        validate_certificate 0 
        required 1 
      </mesh> 	
     ```
5. If this is a **new instance** or you have changed the nodes FQDN, you will need to notify `wlcg-perfsonar-support 'at' cern.ch` to add the node in one or more test meshes, which will then auto-configure the tests. You could also add any additional local tests via web interface or local mesh. Please indicate if you have preferences for which meshes your node should be included in (USATLAS, USCMS, ATLAS, CMS, LHCb, Alice, BelleII, HNSciCloud, etc.).
     !!! note
	Until your host is added (on http://meshconfig.grid.iu.edu ) to one or more meshes by a mesh-config administrator, the automesh configuration above won't be returning any tests (See registration information above).
6. We **recommend** configuring perfSONAR in **dual-stack mode** (both IPv4 and IPv6). In case your site has IPv6 support, the only necessary step is to get both A and AAAA records for your perfSONAR DNS names (as well as ensuring the reverse DNS is in place).
7. Please check that both local and campus firewall has the necessary [ports open](#security_considerations)
8. Once installation is finished, please **reboot** the node.

For any further questions, please consult [FAQ](perfsonar/faq.md) pages, perfSONAR documentation (<http://docs.perfsonar.net>) or contact directly WLCG or OSG perfSONAR support units.

### Security Considerations

!!! warning 
	As of the release of perfSONAR 4.0 ALL perfSONAR instances need to have port 443 access to all other perfSONAR instances. This change is because of the new requirements introduced by pScheduler. If sites are unable to reach your instance on port 443, tests may not run and results may not be available.

The perfSONAR toolkit is reviewed both internally and externally for security flaws. The toolkit's purpose is to allow us to measure and diagnose network problems and we therefore need to be cautious about blocking needed functionality by site or host firewalls.

For sites that are concerned about having port 443 open, there is a possiblity to get a list of hosts to/from which the tests will be initiated. However implementing the corresponding firewall rules would need to be done both locally and on the campus firewall. It's important to emphasize that port 443 provides access to the perfSONAR web interface and serves as a controller port for scheduling the tests, which is very useful to users and network administrators to debug network issues. Sites can optionally allow port 80, which could be restricted to a limited set of subnets, as shown in the rules below: 
```
    # Port 443 must be open 
    iptables -I INPUT 4 -p tcp --dport 443 -j ACCEPT
    # Allow port 80 for specific monitoring subnets
    # OSG monitoring subnet 
    iptables -I INPUT 4 -p tcp --dport 80 -s 129.79.53.0/24 -j ACCEPT 
    # CERN subnet 
    iptables -I INPUT 4 -p tcp --dport 80 -s 137.138.0.0/17 -j ACCEPT 
    # Infrastructure monitoring (hosted at AGLT2) 
    iptables -I INPUT 4 -p tcp --dport 80 -s 192.41.231.110/32 -j ACCEPT 
    # Replace <LOCAL\_SUBNET> appropriately to allow access from your local systems 
    iptables -I INPUT 4 -p tcp --dport 80 -s <LOCAL\_SUBNET> -j ACCEPT 
    # Reject ONLY if your site policy requires this 
    #iptables -I INPUT 5 -p tcp --dport 80 -j REJECT
```

To save your changes run `/sbin/service iptables save` 

!!! warning
	In case you have **central/campus firewall**, please check the required port openings in the [perfSONAR security documentation](http://docs.perfsonar.net/manage_security.html).  

