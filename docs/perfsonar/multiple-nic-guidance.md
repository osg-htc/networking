### Multiple NIC (Network Interface Card) Guidance

The OSG and WLCG recommendation is to deploy two flavors of perfSONAR measurement nodes: 1) a latency instance which
continuously measures packet delay and lost and 2) a bandwidth instance measuring the achievable bandwidth.  That
implies sites must purchase, deploy and maintain two systems.  **Why can't we just run both latency and bandwidth
services on a single instance?** The problem is that running both latency and bandwidth services on a single node /
single NIC may cause interence between the various measurements and introduce "false-positive" indications of network
problems.

Many sites would prefer **not** to have to deploy two servers for cost, space and power reasons.  Fortunately the
perfSONAR developers have provided a way to install both latency and bandwidth measurements services on a single node,
as long as it has at least two NICs (one per 'flavor' of measurement) and sufficient processing and memory.  See
[manage-dual-xface](http://docs.perfsonar.net/manage_dual_xface.html) for details on configuring this.

### Lookup Service registration on hosts with several perfSONAR NICs

A host that runs perfSONAR on more than one public NIC (for example a latency and a bandwidth interface, or an extra
100G interface) usually has one DNS name per NIC, and pSConfig enrollment already uses one URL per name
(`/pub/auto/<FQDN>` for each). The Lookup Service registration does not follow that by default:

- `lsregistrationdaemon.conf` ships with one `<host>` block set to `autodiscover`. The daemon then picks **one**
  primary address and registers one host record under that address and its name. Its services (pscheduler, owamp,
  twamp) also advertise only that address.
- The other NICs and names are never registered. Which NIC is picked can change after a restart, so the registered
  name can move between your FQDNs over time.
- Tools that read the Lookup Service, such as the OSG/WLCG pSConfig Web Admin (`psconfig.opensciencegrid.org`), see
  only one of your hosts, and the others show up as stale.

To register every perfSONAR NIC as its own host, run the `multi-nic` command of
`perfSONAR-update-lsregistration.sh` (version 1.1.0 or later) as root on the host:

```bash
# preview the change, then apply it (restarts the daemon in the testpoint container)
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh multi-nic --dry-run
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh multi-nic
# RPM toolkit installs: add --local
```

It reads `/etc/perfSONAR-multi-nic-config.conf` (written by `perfSONAR-pbr-nm.sh`) and writes one `<host>` per public
NIC, starting with the default-route NIC. Each host gets:

- `host_name` set to the NIC's IPv4 address and its DNS name, in that order;
- only its own interface (`autodiscover_interfaces 0` plus one `<interface>` block);
- the same services as before, with explicit addresses (the name, IPv4 and IPv6 of that NIC).

Private (RFC 1918) addresses are skipped unless `--allow-internal 1` is given. Every public NIC needs a reverse-DNS
name that resolves back to its IPv4 address; the command stops if one does not. All other settings in the file (site,
location, administrator, `ls_instance`) are kept.

All the host records still share the daemon's one `client-uuid`. Consumers must therefore treat each host record
(`service-host`) as a separate host. PWA 5.2.6 keys hosts by `client-uuid` and would merge them back into one; a
patch that keys on `service-host` instead is being tested for the OSG/WLCG pSConfig Web Admin.

Deployed on psum01.aglt2.org on 2026-11-20 (three public NICs: psum01, psum02, psum02-100g) and checked in the
production Lookup Service: three host records, each with its own interface and pscheduler/owamp/twamp services.

The next major perfSONAR toolkit release replaces `lsregistrationdaemon` with a new Python client that registers
one consolidated record per host (all interfaces and pScheduler URLs in one record). This section applies to
hosts running `lsregistrationdaemon` (perfSONAR 5.x).

!!! warning "Container testpoints: the change does not survive a container re-create"

    In the standard testpoint compose files `lsregistrationdaemon.conf` lives inside the container, not on the host.
    A container re-create (for example by the auto-updater pulling a new image) restores the image default, and with
    it the single autodiscovered host. Until the compose files bind-mount the file, re-run the `multi-nic` command
    after each update. Any change made with `perfSONAR-update-lsregistration.sh update` (site, location,
    administrator) is affected the same way.

    Planned fix: bind-mount `/opt/perfsonar-tp/conf/lsregistrationdaemon.conf` to
    `/etc/perfsonar/lsregistrationdaemon.conf`. On existing hosts the seed step must copy the file **from the running
    container**, not from the image, so site settings already made inside the container are kept.
