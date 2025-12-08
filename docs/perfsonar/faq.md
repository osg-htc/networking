# Frequently Asked Questions

Here we will provide details on troubleshooting perfSONAR installations for OSG and WLCG as well as some additional
configuration options and a FAQ.

A good overview of existing tools provided by perfSONAR toolkit and examples how to use them to identify and isolate
network problems can be found at:

<https://fasterdata.es.net/performance-testing/troubleshooting/network-troubleshooting-quick-reference-guide/>

We are maintaining a [Network Troubleshooting](../network-troubleshooting.md) page to guide users in identifying and
following up on network problems.

## Installing a certificate

**What is the recommended way to install a certificate on my perfSONAR host?**

[We recommend using Let's Encrypt](https://letsencrypt.org). There is a tutorial that users may find helpful at [Secure
Apache with Lets Encrypt](https://www.tecmint.com/secure-apache-with-lets-encrypt-ssl-certificate-on-centos-8/).

<!-- markdownlint-disable MD033 --> <details>

```text
<summary>A quick set of steps is shown here:</summary>
<p>0. Install certbot with yum, dnf, or snap:  **yum install certbot python3-certbot-apache**</p>
<p>1. Certbot needs port 80/443 so stop anything blocking it or using it:  **systemctl stop firewalld  systemctl stop httpd**</p>
<p>2. Test with dry-run:  **certbot certonly --standalone --preferred-challenges http --dry-run**</p>
<p>3. Get the certificate:  **certbot certonly --standalone --preferred-challenges http**</p>
<p>4. Restart httpd:  **systemctl start firewalld  systemctl start httpd**</p>
<p>5. Note certificate is installed under  /etc/letsencrypt/</p>
<p>6. Tell http where your certificate is:  Edit /etc/httpd/conf.d/ssl.conf</p>
    <p>1. Set **SSLCertificateFile** to /etc/letsencrypt/live/FQDN/cert.pem</p>
    <p>2. Set **SSLCertificateKeyFile** to /etc/letsencrypt/live/FQDN/privkey.pem</p>
    <p>3. Set **SSLCertificateChainFile** to /etc/letsencrypt/live/FQDN/fullchain.pem</p>
<p>7. Renew your certficate: **certbot renew --dry-run certbot renew**</p>
<p>8. Make a donation :)</p>
```

</details> <!-- markdownlint-enable MD033 -->

Thanks to Raul Lopes for these details!

## Network Troubleshooting

* I suspect there is a network performance issue impacting my site

For OSG sites, please open a ticket with GOC. Otherwise please open a GGUS ticket (or assign an existing) one to WLCG
Network Throughput support unit.

## Service Registration

**I got an email after registering with lots of information in it...what do I do?**

This is part of the process. If you are a new site you will need to attend the next OSG operations meeting. If you are
an existing site and have just registered perfSONAR instances you don't have to do anything but feel free to attend the
next operations meeting if you have questions or concerns.

**Once I registered, new tickets were opened concerning perfSONAR...What do I do?**

This is standard operating procedure and the tickets are to ensure that OSG operations properly gets your new perfSONAR
instances registered. You don't have to do anything and the tickets will be closed by OSG operations staff.

## Infrastructure Monitoring (check\_mk metrics)

* **perfSONAR services: versions** metric is failing.

This metrics checks if your sonar is at the most recent version. Please check if you have automatic yum updates enabled,
this is strongly recommended due to security issues we have seen in the past. In case you're still running an older
version (3.3-3.5), please update and reconfigure as soon as possible following [Installation Guide](installation.md)

* **perfSONAR configuration: contacts or location** metrics are failing

Please check if you have added the administrative information as detailed
[here](http://docs.perfsonar.net/install_config_first_time.html#updating-your-administrative-information)

* **perfSONAR services: bwctl/owamp/pscheduler** metrics are failing

This means that we're unable to connect to controller ports of the respective services, please ensure you have correct
firewall settings (especially white listed subnets allowed) as described in the [Installation Guide](installation.md) .
This can also indicate failures of service daemons, please check <http://docs.perfsonar.net/FAQ.html> for additional
details.

* **perfSONAR services: esmond** metric is failing

This means that your measurement archive is not accessible or failing, there can be many possible causes (disk full,
httpd not running or inaccessible, etc.), you can ask for help by opening a GGUS ticket to WLCG perfSONAR support.

* **perfSONAR json summary** is failing

```text

* This means the toolkit's homepage is inaccessible, which is required to check many additional services, so in turn all the other metrics will likely be in unknown or critical state. Please check for usual causes (disk full, httpd not running or blocked), we need to be able to access your homepage via HTTP or HTTPS

```

* **perfSONAR configuration: meshes** metric is failing

This indicates that you're missing the recommended mesh configuration. Please follow mesh configuration as detailed in
the [installation guide](installation.md). Also, please REMOVE any old mesh configuration, this metric will also fail in
case you have both the new mesh config and the old mesh URLs

* **perfSONAR services: ntp** is failing

This indicates that NTP service is not running correctly on your toolkit instance, **please note that NTP is critical
service**. Some things to check include your [perfSONAR NTP configuration](http://docs.perfsonar.net/manage_ntp.html).
If NTP is correctly configured, it is possible you could have a firewall issue:  **port 123 UDP must be open**.   There
is NTP debugging information available on Google (e.g., <https://support.ntp.org/bin/view/Support/TroubleshootingNTP>).
If you still have problems, please open a support ticket (see below).

* **perfSONAR services: regular testing/pscheduler** is failing

This indicates that pscheduler is not working correctly. As this is the core daemon please contact WLCG perfSONAR
support unit for help.

* There are **many tests failing** for given sonar, where should I start

Please update and reconfigure your sonar following [Installation Guide](installation.md). Please ensure firewall doesn't
block access from the whitelisted subnets that are required for the infrastructure monitoring to work.

* **Where can I get support on managing WLCG perfSONAR** ?

You can open ticket in GGUS to WLCG perfSONAR support unit or contact directly wlcg-perfsonar-support (at cern.ch)

* **perfSONAR esmond freshness Latency/Bandwidth Direct** is failing or gives warning

This metric checks freshness of the local measurement archive, in particular it checks if it contains fresh results for
all the configured tests. This metric is needed to determine if we're able to consistently get results from perfSONAR
boxes in WLCG. Currently it's a non-critical test, you can ignore it.

* **perfSONAR services ndt/npad** is failing

Both metrics check if you have disabled NDT and NPAD. As both NDT and NPAD have been dropped starting with 4.0, this
metrics should stay green in most of the cases.

* **perfSONAR hardware check** is failing

Please consult the minimum and recommended [hardware requirements](deployment-models.md).
