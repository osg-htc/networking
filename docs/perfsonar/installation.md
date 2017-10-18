<span class="twiki-macro LINKCSS"></span>

<span class="twiki-macro SPACEOUT">Installation and Upgrade Details</span>
==========================================================================


<span class="twiki-macro STARTINCLUDE"></span>

This page documents installing or upgrading **perfSONAR** for OSG and WLCG sites. In case this is the first time you're trying to install and integrate your perfSONAR into WLCG or OSG, please consult <https://twiki.opensciencegrid.org/bin/view/Documentation/PSMotivation> for an overview of perfSONAR.

For any questions or help with WLCG perfSONAR setup, please email `wlcg-perfsonar-support 'at' cern.ch` or open GGUS ticket for [WLCG perfSONAR Monitoring Support Unit](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ). We strongly recommend anyone maintaining/using perfSONAR to join <https://lists.internet2.edu/sympa/subscribe/perfsonar-user> and <https://lists.internet2.edu/sympa/subscribe/perfsonar-announce>

Please follow the instructions for [upgrading](#UpgradeGuide) or [installing](#InstallingperfSONAR) perfSONAR as appropriate for your plans.

Updating perfSONAR
-------------------

Before updating, please read the release notes at <http://docs.perfsonar.net/manage_update.html#special-upgrade-notes>

To update please run the following:

    # yum clean all
    # yum update
    # reboot

Note, it's **very important to reboot** otherwise your update is incomplete. Please also note, that starting from v3.4 `yum` auto-updates are turned on by default. **We strongly recommend keeping them turned on**. With `yum` auto-updates in place there is a possibility that updated packages can "break" your perfSONAR install but this is viewed an acceptable risk in order to have security updates quickly applied on perfSONAR instances.

If you haven't yet added another (`non-root`) user to administer the web interface, you should run `/usr/lib/perfsonar/scripts/nptoolkit-configure.py` and do so, as suggested in `motd`. See <http://docs.perfsonar.net/manage_users.html> for detailed instructions.

Please backup your old `/etc/perfsonar/meshconfig-agent.conf` file and replace it with `/etc/perfsonar/meshconfig-agent.conf.rpmnew`.

Then please verify/reconfigure your boxes following [OSG and WLCG Configuration](#ConfigPS). For any further questions, please consult [Troubleshooting](https://twiki.opensciencegrid.org/bin/view/Documentation/TroubleFAQPS) pages, perfSONAR documentation (<http://docs.perfsonar.net>) or contact directly WLCG or OSG perfSONAR support units.

Installing perfSONAR
--------------------

perfSONAR 4.0 was released in April 2017. For sites running the previous version (3.x.y) the update should have automatically happened assuming that yum auto-updates were enabled and the `/etc/yum.repos.d/Internet2.repo` had 'enabled = 1'.

The following information details how to install perfSONAR 4.0 for WLCG and OSG. For general troubleshooting please go [here](https://twiki.opensciencegrid.org/bin/view/Documentation/TroubleFAQPS), in case you have any questions please email `wlcg-perfsonar-support 'at' cern.ch` or open GGUS ticket for [WLCG perfSONAR support unit](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ). For OSG sites that don't participate in WLCG, please contact [OSG operations](https://twiki.opensciencegrid.org/bin/view/Operations/WebHome).

The perfSONAR team has created very good documentation on the process. You can get information about your installation options at <http://docs.perfsonar.net/install_getting.html#gettingchooseinstall>

### Installation

-   For sites using perfSONAR Net Install - please follow <http://docs.perfsonar.net/install_centos_netinstall.html#step-by-step-guide>
-   For sites using perfSONAR Full Install - please follow <http://docs.perfsonar.net/install_centos_fullinstall.html#step-by-step-guide>
-   For general configuration of perfSONAR - please follow <http://docs.perfsonar.net/install_config_first_time.html>

For sites the are currently registered but not yet updated to 4.0 we would strongly recommend reinstalling using CentOS 7.x (follow either the Full Install or the Net Install above). There is no need for sites to preserve their data from the OSG/WLCG perspective, since we have already been collecting your data centrally. The primary reason for this recommendation is that the next point release of perfSONAR (version 4.1) will no longer support RHEL6/CentOS6/Scientific Linux 6 as a supported operating system.

OSG and WLCG Configuration Notes
--------------------------------

All perfSONAR instances for use in OSG and WLCG should be registered either in OIM or GOCDB. Please verify or register your instances at:

-   For OSG, follow the details in [OIM](register-ps-in-oim)
-   For Non-OSG, follow the details in [GOCDB](register-ps-in-gocdb)

Please ensure you have added or updated your administrative information: <http://docs.perfsonar.net/manage_admin_info.html>

-   Adding communities is optional, but we recommend putting in WLCG as well as your VO: `ATLAS`, `CMS`, etc. This just helps others from the community lookup your instances in the lookup service. As noted in the documentation you can select from already registered communities as appropriate.

Assuming your registration is for a **new** node or if you have changed the nodes FQDN, you will need to email `wlcg-perfsonar-support 'at' cern.ch` or open GGUS ticket for [WLCG perfSONAR support unit](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ) so that your node can be added to one or more meshes. Please indicate if you have preferences for which meshes your node should be included in.

You will need to configure your instance(s) to use the OSG/WLCG mesh-configuration. OSG provides MCA (Mesh Configuration Adminstrator) GUI (see <http://docs.perfsonar.net/mca.html> for details) to centrally define the network tests that need to be run. Each perfSONAR toolkit installation for OSG/WLCG should add the "auto" mesh URL in their `/etc/perfsonar/meshconfig-agent.conf` file:

-   Set this to `http://meshconfig.grid.iu.edu/pub/auto/<FQDN>` Replace `<FQDN>` with the fully qualified domain name of your host, e.g., `psum01.aglt2.org`.
-   Below is an example set of lines for meshconfig-agent.conf

    ```
        <mesh> 
            configuration_url http://meshconfig.grid.iu.edu/pub/auto/psum01.aglt2.org
            validate_certificate 0 
            required 1 
        </mesh> 	
        # Replace the following with suitable values for your installation 
        address psum01.aglt2.org 
        admin_email smckee@umich.edu 
        skip_redundant_tests 1 
    ```

!!! note
	Until your host is added to one or more meshes, the automesh configuration above won't be returning any tests (See above).

We **strongly recommend** configuring perfSONAR in **dual-stack mode** (both IPv4 and IPv6)

-   In case your site has IPv6 support, the only necessary step is to get both A and AAAA records for your perfSONAR DNS names (as well as ensuring the reverse is in place).
-   All existing meshes will support both IPv4 and IPv6 testing. Sites with both IPv4 and IPv6 addresses testing to sites that also have both will run **two** tests. A side effect of this is that as more sites provide IPv6 addresses, the amount of testing will increase.
-   At some future point when most sites have IPv6, we may need to adjust the testing frequency to reduce the overall amount of testing
-   For more information on IPv6 see <http://ipv6.web.cern.ch/>

#### Security Considerations

!!! warning 
	As of the release of perfSONAR 4.0 ALL perfSONAR instances need to have port 443 access to all other perfSONAR instances. This change is because of the new requirements introduced by pScheduler. If sites are unable to reach your instance on port 443, tests may not run and results may not be available.

The perfSONAR toolkit is reviewed both internally and externally for security flaws. The toolkit's purpose is to allow us to measure and diagnose network problems and we therefore need to be cautious about blocking needed functionality by site or host firewalls.

Some sites are concerned about having port 80 and/or 443 open. The working group would like to emphasize that these ports provide access to the perfSONAR web interface and are very useful to users and network administrators. **Our recommendation is to keep them open**, but for sites with strong concerns we have some rules documented below to customize iptables to block ports 80 and 443. It is **required** that either port 80 **or** port 443 be accessible from the OSG and WLCG monitoring subnets shown below. In addition port 443 **must** be accessible to all other perfSONAR instances that your node will test to. This is a new requirement as of the release of perfSONAR 4.0. 

    # Port 443 must be open 
    iptables -I INPUT 4 -p tcp --dport 443 -j ACCEPT
    # Allow port 80 for specific monitoring subnets AT A MINIMUM (we recommend opening port 80 so others can view/access your perfSONAR Toolkit web GUI) 
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


To save your changes run `/sbin/service iptables save` 


In case you have **central/campus firewall**, please ensure the following ports are opened on it for all your perfSONAR hosts: 

    # General purpose ports needed to do perfSONAR measurements 
    ICMP/type 255, NTP UDP port:123, 
    TRACEROUTE/PING UDP ports: 33434-33634 
    OWAMP TCP port:861, UDP ports: 8760-9960 
    BWCTL TCP ports: 4823, 6001-6200, 5000-5900 UDP ports: 6001-6200, 5000-5900


HTTP and/or HTTPS ports are needed to access your perfSONAR web interface and the measurement archive and to check 
availability of your instances by the infrastructure monitoring. As of the release of perfSONAR 4.0 port 443 **must** 
be accessible to all other perfSONAR instances and the WLCG monitoring subnets HTTPS port 443 open to ALL 

!!! note 
	At a minimum either port 80 **must** be open to the WLCG monitoring subnets. 

Our recommendation is to have HTTP open to allow users and network admins access to the perfSONAR web. 
HTTP port 80 - open to ALL or at least for the following source subnets 
* OSG\_NET (129.79.53.0/24)
* AGLT2\_NET (192.41.231.110/32)
* CERN\_NET (137.138.0.0/17) 

For any further questions, please consult [Troubleshooting](https://twiki.opensciencegrid.org/bin/view/Documentation/TroubleFAQPS) pages, perfSONAR documentation (<http://docs.perfsonar.net>) or contact [WLCG perfSONAR Monitoring Support Unit](https://wiki.egi.eu/wiki/GGUS:WLCG_perfSONAR_FAQ).

<span class="twiki-macro STOPINCLUDE"></span>

<span class="twiki-macro BOTTOMMATTER"></span>

-- Main.ShawnMcKee - 17-Oct-2017
