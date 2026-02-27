# Installing a perfSONAR Toolkit for WLCG/OSG
<!-- markdownlint-disable MD040 -->

This guide walks WLCG/OSG site administrators through end-to-end installation, configuration, and validation of a
perfSONAR Toolkit on Enterprise Linux 9 (EL9) using RPM packages. The Toolkit provides a full-featured perfSONAR
installation with a local web interface for configuration and monitoring, plus a local measurement archive for data
storage.

For upstream RPM installation documentation, see: <https://docs.perfsonar.net/install_el.html>

---

## Choosing Between Toolkit and Testpoint

### Use perfSONAR Toolkit (this guide) if you need

- **Local web interface** for configuration, monitoring, and viewing measurement results
- **Local measurement archive** to store test data on-site with your own retention policies
- **Full-featured installation** with all perfSONAR capabilities
- **Site-specific data retention** requirements or regulatory compliance needs
- **On-site troubleshooting** access to historical measurement data without external dependencies

### Use perfSONAR Testpoint instead if you prefer

- **Lightweight container-based** deployment with minimal local resources
- **Central archiving** where measurements are stored at a remote archive (WLCG/OSG central infrastructure)
- **Simplified updates** via container image pulls rather than RPM package management
- **Reduced local storage** requirements (no local measurement archive)

See [Installing a perfSONAR Testpoint](install-perfsonar-testpoint.md) for the container-based deployment guide.

---

## Prerequisites and Planning

Before you begin, it may be helpful to gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage locations.

- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN
  information.

- **Operational contacts:** site admin email, OSG facility/site name, latitude/longitude.

## Existing perfSONAR configuration

If replacing an existing instance, you may want to back up `/etc/perfsonar/` files, especially
`lsregistrationdaemon.conf`, and any container volumes. We have a script named`perfSONAR-update-lsregistration.sh` to
extract/save/restore registration config that you may want to use.

??? info "Quick capture of existing lsregistration config (if you have a src)"
    
    Download a temp copy:   
    ```bash
    curl -fsSL \
      https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh \
      -o /tmp/update-lsreg.sh
    chmod 0755 /tmp/update-lsreg.sh
    ```
    Use the downloaded tool to extract a restore script:
    ```bash
    /tmp/update-lsreg.sh extract --output /root/restore-lsreg.sh --local
    ```
    Note: Repository clone instructions are in Step 2.
    **Note:** All shell commands assume an interactive root shell.
    
---

## Step 1 – Install and Harden EL9

1. **Provision EL9:** Install AlmaLinux, Rocky Linux, or RHEL 9 with the *Minimal* profile.

1. **Set the hostname and time sync:** Pick the NIC that will own the default route for the hostname.

    ```bash
    hostnamectl set-hostname <testpoint-hostname>
    systemctl enable --now chronyd
    timedatectl set-timezone <Region/City>
    ```

1. **Disable unused services:**

    ```bash
    systemctl disable --now firewalld NetworkManager-wait-online

    Keep `NetworkManager` running. The command above disables only the `NetworkManager-wait-online` unit to prevent
    long boot delays while services start. If your environment depends on `network-online.target` for storage or
    bonded/uplink bring-up, leave `NetworkManager-wait-online` enabled.
    dnf remove -y rsyslog
    ```

    ??? info "Why disable unused services?"
        
        We recommend disabling unused services during initial provisioning to reduce complexity and avoid unexpected
        interference with network and container setup. Services such as `firewalld`, `NetworkManager-wait-online`, and `rsyslog`
        can alter networking state, hold boot or network events, or conflict with the automated nftables/NetworkManager changes
        performed by the helper scripts. Disabling non-essential services makes the install deterministic, reduces the host
        attack surface, and avoids delays or race conditions while configuring policy-based routing, nftables rules, and        
        container networking.
        
1. **Update the system:**

    ```bash
    dnf -y update
     ```

1. **Record NIC names:** Document interface mappings for later PBR configuration.

    ```bash
    nmcli device status
    ip -br addr
    ```

---

## Step 2 – Install perfSONAR Toolkit via RPM

After completing Step 1 (minimal OS hardening), install the perfSONAR Toolkit bundle using RPM packages.

### Step 2.1 – Configure DNF Repositories

Configure DNF to access EPEL, CRB (CodeReady Builder), and perfSONAR repositories:

```bash
# Install EPEL repository
dnf install -y epel-release

# Non-RHEL Enable CRB (CodeReady Builder) repository
dnf config-manager --set-enabled crb  
# --OR--
# For RHEL Enable access to codeready-builder. 
# NOTE auto-install script from perfSONAR doesn't set this (tries "crb" above which fails for RHEL)
subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms

# Install perfSONAR repository for EL9
dnf install -y http://software.internet2.edu/rpms/el9/x86_64/latest/packages/perfsonar-repo-0.11-1.noarch.rpm

# Refresh DNF cache
dnf clean all
```

??? info "What these repositories provide"
    
    - **EPEL** (Extra Packages for Enterprise Linux): Community packages not in base EL9
    - **CRB** (CodeReady Builder): Additional development and build tools
    - **perfSONAR repo**: Official perfSONAR packages maintained by Internet2

### Step 2.2 – Install perfSONAR Toolkit Bundle

Install the complete toolkit bundle:

```bash
dnf install -y perfsonar-toolkit
```

This bundle automatically includes:

- Core perfSONAR measurement tools (pScheduler, OWAMP, traceroute, throughput tests)
- **perfsonar-toolkit-security**: Firewall rules (nftables) and fail2ban configuration
- **perfsonar-toolkit-sysctl**: Network tuning parameters optimized for measurements
- **perfsonar-toolkit-systemenv-testpoint**: Automatic updates and logging configuration
- **Web interface**: Local UI at `https://<hostname>/toolkit`
- **Measurement archive**: Local OpenSearch and Logstash for storing test results

Installation takes approximately 5-10 minutes depending on network speed.

??? info "Alternative automated installation"
    
    perfSONAR provides a one-line automated installer script:
    ```bash
    curl -s https://downloads.perfsonar.net/install | sh -s - toolkit
    ```
    
    This script performs the same steps as above (configure repos + install bundle).

### Step 2.3 – Run Post-Install Configuration Scripts

The toolkit bundle includes configuration scripts that must be run after installation:

```bash
# Configure system tuning parameters (sysctl)
/usr/lib/perfsonar/scripts/configure_sysctl

# Configure firewall rules
/usr/lib/perfsonar/scripts/configure_firewall install
```

??? info "What these scripts configure"
    
    **`configure_sysctl`**:
    - TCP congestion control algorithm (htcp instead of reno)
    - Maximum TCP buffer sizes for high-bandwidth paths
    - Network stack tuning for measurement workloads
    - Creates `/etc/sysctl.d/perfsonar-sysctl.conf`
    
    **`configure_firewall`**:
    - Opens required ports for perfSONAR services (pScheduler, OWAMP, HTTP/HTTPS)
    - Configures nftables rules (compatible with existing rules)
    - Enables fail2ban with perfSONAR jails
    - Creates `/etc/nftables.d/perfsonar.nft`

### Step 2.4 – Install Helper Scripts for PBR and Management

Install OSG/WLCG helper scripts for policy-based routing and advanced configuration:

```bash
# Install base packages for helper scripts
dnf -y install jq curl tar gzip rsync bind-utils \
    python3 iproute iputils procps-ng sed grep gawk

# Bootstrap helper scripts
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
    -o /tmp/install_tools_scripts.sh

chmod 0755 /tmp/install_tools_scripts.sh

/tmp/install_tools_scripts.sh /opt/perfsonar-toolkit
```

**Verify bootstrap completed successfully:**

```bash
# Check that all helper scripts were downloaded
ls -1 /opt/perfsonar-toolkit/tools_scripts/*.sh | wc -l
# Should show 17 shell scripts

# Verify key scripts are present and executable
ls -l /opt/perfsonar-toolkit/tools_scripts/{perfSONAR-pbr-nm.sh,perfSONAR-install-nftables.sh,check-perfsonar-dns.sh,fasterdata-tuning.sh}
```

??? info "Why install helper scripts?"
    
    The OSG/WLCG helper scripts provide automation for:
    - Multi-NIC policy-based routing configuration
    - DNS forward/reverse validation
    - Registration information management
    - Custom nftables rules integrated with PBR
    
    These scripts are optional but highly recommended for sites with multiple network interfaces or
    complex routing requirements.

---

## Step 3 – Configure Policy-Based Routing (PBR)

The script `/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh` automates NetworkManager profiles and routing rule
setup. It fills out and consumes the network configuration in `/etc/perfSONAR-multi-nic-config.conf`.
    
??? info "Modes of operation"

    By default the script now performs an **in-place apply** that adjusts routes, rules, and NetworkManager connection
    properties **without deleting existing connections or flushing all system routes**. This minimizes disruption and
    usually avoids the need for a reboot.

    An optional destructive mode `--rebuild-all` performs the original full workflow: backup existing profiles, flush all
    routes and rules, remove every NetworkManager connection, then recreate connections from scratch. Use this only for
    initial deployments or when you must completely reset inconsistent legacy state.

    | Mode | Flag | Disruption | When to use |
    |------|------|------------|-------------|
    | In-place (default) | (none) or `--apply-inplace` | Low (interfaces stay up; rules adjusted) | Routine updates, gateway changes, add routes |
    | Full rebuild | `--rebuild-all` | High (connections removed; brief connectivity drop) | First-time setup, severe misconfiguration |

### Safety Enhancements

- Detects active SSH session interface and avoids extra disruption to that NIC in in-place mode.
- Prompts are still skipped with `--yes`.
- Dry-run preview supported via `--dry-run` (combine with `--debug` for verbose output).
- Reboot is **no longer generally required**; only consider one if NetworkManager fails to apply the new rules cleanly.

### Generate config file automatically (or preview)

!!! warning "Gateways required for addresses"
        
    Any NIC with an IPv4 address must also have an IPv4 gateway, and any NIC with an IPv6 address must have an IPv6 gateway.
    If the generator cannot detect a gateway, it adds a WARNING block to the generated file listing affected NICs. Edit
    `NIC_IPV4_GWS`/`NIC_IPV6_GWS` accordingly before applying changes.
        
??? note "Gateway prompts"
        
    During generation, the script attempts to detect gateways per-NIC. If a NIC has an IP address but no gateway could be
    determined, it will prompt you interactively to enter an IPv4 and/or IPv6 gateway (or `-` to skip). Prompts are skipped
    in non-interactive sessions or when you use `--yes`. Note, NICs without gateways are assumed to NOT be used for perfSONAR.
        
Preview generation (**no changes**):
        
```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-debug    
```

Generate and **write** the config file:
        
```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto 
```

The script writes the config file to `/etc/perfSONAR-multi-nic-config.conf`. Edit to adjust site-specific values (e.g.,
confirm `DEFAULT_ROUTE_NIC`, add `NIC_IPV4_ADDROUTE` entries) and verify the entries. Include every NIC/subnet that should
retain SSH access; the nftables helper derives allow-lists from this file.

Example: adding a management network alongside the data VLAN

```bash
NIC_NAMES=(
    "bond0.2900"
    "bond0"
)

NIC_IPV4_ADDRS=(
    "192.41.236.32"
    "10.10.128.32"
)

NIC_IPV4_PREFIXES=(
    "/23"
    "/20"
)

NIC_IPV4_GWS=(
    "192.41.236.1"
    "10.10.128.1"
)

NIC_IPV4_ADDROUTE=(
    "-"
    "10.10.0.0/22"
)

NIC_IPV6_ADDRS=(
    "2001:48a8:68f7:8001:192:41:236:32"
)

NIC_IPV6_PREFIXES=(
    "/64"
)

NIC_IPV6_GWS=(
    "2001:48a8:68f7:8001::1"
)

DEFAULT_ROUTE_NIC="bond0.2900"
```

Use plain ASCII quotes and keep array lengths aligned across sections.
        
### Apply changes (in-place default)

!!! warning "Connect via console for network changes"
        
    When applying network changes across an ssh connection, your session may be interrupted.   Please try to run the
    perfSONAR-pbr-nm.sh script when connected either directly to the console or by using 'nohup' in front of the script
    invocation.

#### In-place apply (recommended)

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --yes
```
        
??? info "If SSH connection drops during network reconfiguration:"
        
    1. Access via BMC/iLO/iDRAC console or physical console
    1. Review `/var/log/perfSONAR-multi-nic-config.log` for errors
    1. Check network state with `nmcli connection show` and `ip addr`
    1. Restore from backup if needed: backups are in `/var/backups/nm-connections-<timestamp>/`
    1. Reapply config after corrections: `/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --yes`


#### Full rebuild (destructive – removes all NM connections first)

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --rebuild-all --yes
```

The policy based routing script logs to `/var/log/perfSONAR-multi-nic-config.log`. After an in-place apply, a reboot is typically
unnecessary. If connectivity or rules appear inconsistent (`ip rule show` / `ip route` mismatch), consider a manual
NetworkManager restart:

```bash
systemctl restart NetworkManager

```

### DNS: forward and reverse entries (required)

All IP addresses that will be used for perfSONAR testing MUST have DNS entries: a forward (A/AAAA) record and a matching
reverse (PTR) record. This is required so remote test tools and site operators can reliably reach and identify your
host, and because some measurement infrastructure and registration systems perform forward/reverse consistency checks.

- For single-stack IPv4-only hosts: ensure A and PTR are present and consistent.
- For single-stack IPv6-only hosts: ensure AAAA and PTR are present and consistent.
- For dual-stack hosts: both IPv4 and IPv6 addresses used for testing must have matching forward and reverse records (A+PTR and AAAA+PTR).

??? info "Run the DNS checker"

    
    To validate forward/reverse DNS for addresses in `/etc/perfSONAR-multi-nic-config.conf` you can run a script:
    ```bash
    /opt/perfsonar-toolkit/tools_scripts/check-perfsonar-dns.sh
    ```
    **Notes and automation tips:**
    
    - The script above uses `dig` (bind-utils package) which is commonly available; you can adapt it
      to use `host` if preferred.
    - Run the check as part of your provisioning CI or as a pre-flight check before enabling measurement registration.
    - For large sites or many addresses, parallelize the checks (xargs -P) or use a small Python
      script that leverages `dns.resolver` for async checks.
    - If your PTR returns a hostname with a trailing dot, the script strips it before the forward check.

    If any addresses fail these checks, correct the DNS zone (forward and/or reverse) and allow DNS propagation before
    proceeding with registration and testing.

**Verify the routing policy:**

    

```bash
nmcli connection show
ip rule show
ip route show table <table-id>

```

Confirm that non-default interfaces have their own routing tables and that the default interface owns the system default
route.

---

## Step 4 – Configure nftables, SELinux, and Fail2Ban

!!! info "Toolkit automatic security hardening"
    
    The **perfsonar-toolkit** bundle automatically configured security during installation (Step 2):
    
    - **nftables rules** via `/usr/lib/perfsonar/scripts/configure_firewall`
    - **fail2ban** with perfSONAR jails for SSH and service protection
    - **SELinux policies** (if enforcing mode is enabled)
    
    This step is **optional** and only needed if you want to:
    
    - Customize firewall rules beyond the toolkit defaults
    - Integrate with OSG helper scripts for PBR-derived SSH access control
    - Add site-specific security policies

### Optional: Customize Security with Helper Scripts

Use `/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-nftables.sh` to configure additional hardened nftables rules
integrated with your PBR configuration. This script can derive SSH allow-lists from your multi-NIC configuration.

**Prerequisites:**

- nftables, fail2ban, and SELinux tools are already installed by the perfsonar-toolkit bundle
- Multi-NIC configuration file at `/etc/perfSONAR-multi-nic-config.conf` (from Step 3)

### Install/configure additional custom options

You can use the install script to install the options you want (selinux, fail2ban).

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes
```

    - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the
      summary and answer manually).

    - Add `--dry-run` for a rehearsal that only prints the planned actions.

The script writes nftables rules for perfSONAR services, derives SSH allow-lists from `/etc/perfSONAR-multi-nic-
config.conf`, optionally adjusts SELinux, and enables Fail2ban jails—only if those components are already installed.

??? info "SSH allow-lists and validation"
        
    - **Auto-detects current SSH clients:** The script captures the IP address of your current SSH connection (via `$SSH_CONNECTION`) and active SSH connections (via `ss`) to ensure your SSH access is not interrupted when the firewall is applied.
    - **Derives allow-lists from config:** In addition to auto-detection, derives SSH allow-lists from `/etc/perfSONAR-multi-nic-config.conf` (CIDR prefixes and addresses).
    - **Prevents lockout:** By combining auto-detected clients with configured subnets, the script prevents accidental SSH lockout during deployment on multi-NIC systems.
    - **Validates nftables rules** before writing.
    - **Outputs:** rules to `/etc/nftables.d/perfsonar.nft`, log to `/var/log/perfSONAR-install-nftables.log`, backups to `/var/backups/`.
    - **Check logs:** Review `/var/log/perfSONAR-install-nftables.log` to see the derived SSH allow-lists and confirm your current session was included.

??? tip "Preview nftables rules before applying"
    
    You can preview the fully rendered nftables rules (no changes are made):
    
    ```bash
    /opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-nftables.sh --print-rules
    ```
    
??? tip "Manually add extra management hosts/subnets"
        
    If you need to allow additional SSH sources not represented by your NIC-derived prefixes, edit
    `/etc/nftables.d/perfsonar.nft` and add entries to the appropriate sets. Example:
        
    ```nft
    set ssh_access_ip4_subnets {
        type ipv4_addr
        flags interval
        elements = { 192.0.2.0/24, 198.51.100.0/25 }
    }

    set ssh_access_ip4_hosts {
        type ipv4_addr
        elements = { 203.0.113.10, 203.0.113.11 }
    }

    set ssh_access_ip6_subnets {
        type ipv6_addr
        flags interval
        elements = { 2001:db8:1::/64 }
    }

    set ssh_access_ip6_hosts {
        type ipv6_addr
        elements = { 2001:db8::10 }
    }
    ```
        
    Then validate and reload (root shell):
        
    ```bash
    nft -c -f /etc/nftables.d/perfsonar.nft
    systemctl reload nftables || systemctl restart nftables
    ```
        
### Confirm nftables state and security services

??? info "Verification commands"
        
    ```bash
    nft list ruleset
    sestatus
    systemctl status fail2ban
    ```
        
You may want to document any site-specific exceptions (e.g., additional allowed management hosts) in your change log.
        
---

## Step 5 – Start and Configure perfSONAR Services

The perfSONAR Toolkit installation automatically enables and starts all required services. This step verifies service
health and completes first-time web interface configuration.

### Step 5.1 – Verify perfSONAR Services

Check that all perfSONAR services are running:


```bash
systemctl status pscheduler-scheduler
systemctl status pscheduler-runner
systemctl status pscheduler-archiver
systemctl status pscheduler-ticker
systemctl status psconfig-pscheduler-agent
systemctl status owamp-server
systemctl status perfsonar-lsregistrationdaemon
```

All services should show `active (running)` status. If any service is not running, start it:


```bash
systemctl start <service-name>
```

??? info "What each service does"
    
    - **pscheduler-scheduler**: Schedules measurement tests
    - **pscheduler-runner**: Executes scheduled tests
    - **pscheduler-archiver**: Archives measurement results to local and remote stores
    - **pscheduler-ticker**: Manages periodic tasks and cleanup
    - **psconfig-pscheduler-agent**: Processes pSConfig templates and creates scheduled tests
    - **owamp-server**: One-Way Active Measurement Protocol (latency/loss measurements)
    - **perfsonar-lsregistrationdaemon**: Registers this host with the global Lookup Service

??? info "Additional services (measurement archive)"
    
    The toolkit also runs OpenSearch and Logstash for local measurement archive:
    ```bash
    systemctl status opensearch
    systemctl status logstash
    ```
    
    These services store measurement results locally for web UI display and historical analysis.

All services are configured to start automatically on boot via systemd.

### Step 5.2 – Access the Web Interface

The perfSONAR Toolkit provides a comprehensive web interface for configuration and monitoring.

**Access the web UI:**

1. Open a browser and navigate to: `https://<your-hostname>/toolkit`

1. **First-time setup wizard:**
   
    On first access, you'll be guided through initial configuration:
   
   - **Create administrator account**: Set username and password for web UI access
   - **Administrative information**: Site name, location, contact details
   - **Host information**: Verify hostname, addresses, and network interfaces
   - **Test configuration**: Review default test settings (typically defaults are appropriate)
   - **Archive settings**: Configure local and/or remote archiving

1. **Complete the wizard** to enable full functionality

??? tip "Web UI features"
    
    The web interface provides:
    
    - **Dashboard**: Real-time and historical measurement results with graphs
    - **Test Configuration**: Schedule on-demand or regular tests to remote endpoints
    - **Administrative Info**: Update site information, contacts, and registration details
    - **Service Health**: Monitor perfSONAR service status and system resources
    - **Archive Configuration**: Manage local archive retention and remote archive destinations
    - **Host Details**: View network interfaces, routes, and system information

??? info "Accessing web UI remotely"
    
    If you need to access the web UI from outside your local network:
    
    - Ensure firewall allows HTTPS (port 443) from your management networks
    - Consider using SSH port forwarding for secure remote access:
      ```bash
      ssh -L 8443:localhost:443 root@<perfsonar-host>
      ```
      Then access: `https://localhost:8443/toolkit`

**Web UI URL:** `https://<your-hostname>/toolkit`

For detailed web UI documentation, see: <https://docs.perfsonar.net/manage_admin_info.html>

### Step 5.3 – Configure Automatic Updates

The perfSONAR Toolkit enables automatic updates by default using `dnf-automatic`.

**Verify automatic updates are enabled:**

```bash
systemctl status dnf-automatic.timer
```

The timer should show `active` and run daily to check for and install perfSONAR package updates.

**Manual update check:**

```bash
dnf check-update perfsonar\*
```

**Apply updates manually** (if needed):

```bash
dnf update perfsonar\*

# Restart affected services after updates
systemctl restart pscheduler-scheduler pscheduler-runner pscheduler-archiver pscheduler-ticker psconfig-pscheduler-agent
```

??? info "How automatic updates work"
    
    - **dnf-automatic** runs daily (configured in `/etc/dnf/automatic.conf`)
    - Updates are downloaded and installed automatically
    - Security updates are prioritized
    - Services are restarted as needed by RPM post-install scripts
    - Update logs: `/var/log/dnf.log` and `journalctl -u dnf-automatic`

??? warning "Update behavior"
    
    By default, the toolkit applies updates automatically. If you prefer manual control:
    
    ```bash
    # Disable automatic updates
    systemctl disable dnf-automatic.timer
    
    # Re-enable later if desired
    systemctl enable --now dnf-automatic.timer
    ```
    
    Manual updates require regular monitoring to ensure security patches are applied promptly.

---

## Step 6 – Install and Configure Let's Encrypt SSL Certificates (Optional but Recommended)

The perfSONAR Toolkit web interface uses HTTPS with self-signed certificates by default. For production deployments,
replacing these with Let's Encrypt certificates provides:

- **Browser trust**: No certificate warnings when accessing the web UI
- **Security**: Industry-standard encryption with automatic renewals
- **Compliance**: Meets security requirements for production infrastructure

This step is optional but highly recommended for production sites.

### Step 6.1 – Prerequisites for Let's Encrypt

Before obtaining Let's Encrypt certificates, ensure:

1. **DNS is configured correctly:**
   
   Your hostname must have valid forward (A/AAAA) and reverse (PTR) DNS records that are publicly resolvable.
   Verify this with the DNS checker:
   
   ```bash
   /opt/perfsonar-toolkit/tools_scripts/check-perfsonar-dns.sh
   ```

2. **Port 80 is accessible:**
   
   Let's Encrypt uses HTTP-01 challenge which requires port 80 to be open from the internet. Update your firewall:
   
   ```bash
   # Add HTTP port to nftables (in addition to existing HTTPS)
   /opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-nftables.sh --ports=80,443 --yes
   ```

3. **Apache is not listening on port 80:**
   
   The perfSONAR Toolkit Apache server should only listen on port 443 (HTTPS). Verify this:
   
   ```bash
   # Check Apache is only listening on 443, not 80
   ss -tlnp | grep :80
   ss -tlnp | grep :443
   
   # Should show port 443 with httpd, but port 80 should be free
   ```

??? warning "If Apache is listening on port 80"
    
    The Toolkit's Apache configuration should not bind to port 80. If it is, check `/etc/httpd/conf/httpd.conf` and
    `/etc/httpd/conf.d/*.conf` for `Listen 80` directives and comment them out:
    
    ```bash
    # Find Listen directives
    grep -r "^Listen 80" /etc/httpd/
    
    # Edit the file(s) and comment out or change to Listen 443
    vi /etc/httpd/conf/httpd.conf
    
    # Restart Apache
    systemctl restart httpd
    ```

### Step 6.2 – Install Certbot

Install certbot using snapd (recommended method) or EPEL packages:

**Option A: Install via Snap (Recommended)**

```bash
# Install snapd
dnf install -y snapd
systemctl enable --now snapd.socket

# Wait for snapd to initialize
sleep 10

# Create symlink for classic snap support
ln -sf /var/lib/snapd/snap /snap

# Install certbot
snap install --classic certbot

# Create symlink for certbot command
ln -sf /snap/bin/certbot /usr/bin/certbot
```

**Option B: Install via DNF (Alternative)**

```bash
# Install certbot from EPEL
dnf install -y certbot

# Verify installation
certbot --version
```

??? info "Why use snap for certbot?"
    
    The Certbot developers recommend snap installation because:
    - Always provides the latest certbot version
    - Automatic updates via snap refresh
    - Consistent across distributions
    - Includes all necessary dependencies
    
    EPEL packages work but may lag behind upstream releases.

### Step 6.3 – Obtain Let's Encrypt Certificate

Use certbot in standalone mode to obtain your certificate. Replace `<your-fqdn>` with your host's fully-qualified domain name
and `<admin-email>` with your email address (used for renewal notifications).

**Obtain certificate (interactive):**

```bash
# Stop Apache temporarily to free port 80
systemctl stop httpd

# Obtain certificate using standalone mode
certbot certonly --standalone \
    -d <your-fqdn> \
    -m <admin-email> \
    --agree-tos

# Restart Apache
systemctl start httpd
```

**Example:**

```bash
certbot certonly --standalone \
    -d ps-toolkit.example.org \
    -m psadmin@example.org \
    --agree-tos
```

**Non-interactive (for automation):**

```bash
systemctl stop httpd

certbot certonly --standalone \
    -d <your-fqdn> \
    -m <admin-email> \
    --agree-tos \
    --non-interactive

systemctl start httpd
```

??? info "Certificate file locations"
    
    After successful issuance, certificates are stored at:
    
    - Full chain: `/etc/letsencrypt/live/<your-fqdn>/fullchain.pem`
    - Private key: `/etc/letsencrypt/live/<your-fqdn>/privkey.pem`
    - Chain only: `/etc/letsencrypt/live/<your-fqdn>/chain.pem`
    - Certificate only: `/etc/letsencrypt/live/<your-fqdn>/cert.pem`
    
    The actual certificate files are in `/etc/letsencrypt/archive/<your-fqdn>/` and the `live/` directory contains
    symlinks to the latest versions.

### Step 6.4 – Configure Apache to Use Let's Encrypt Certificate

Use the helper script to update Apache SSL configuration:

```bash
/opt/perfsonar-toolkit/tools_scripts/configure-toolkit-letsencrypt.sh <your-fqdn>
```

**Example:**

```bash
/opt/perfsonar-toolkit/tools_scripts/configure-toolkit-letsencrypt.sh ps-toolkit.example.org
```

This script:

- Backs up the original Apache SSL configuration
- Updates `SSLCertificateFile` to point to Let's Encrypt fullchain
- Updates `SSLCertificateKeyFile` to point to Let's Encrypt private key
- Adds or updates `SSLCertificateChainFile`

**Verify Apache configuration syntax:**

```bash
apachectl configtest
```

**Reload Apache to apply changes:**

```bash
systemctl reload httpd
```

**Verify the certificate is in use:**

```bash
# Check certificate via OpenSSL
echo | openssl s_client -connect <your-fqdn>:443 -servername <your-fqdn> 2>/dev/null | openssl x509 -noout -issuer -dates

# Should show:
# issuer=C=US, O=Let's Encrypt, CN=...
# notBefore=...
# notAfter=...
```

**Test in browser:**

Navigate to `https://<your-fqdn>/toolkit` and verify:

- No certificate warnings
- Certificate is issued by "Let's Encrypt"
- Certificate is valid (green padlock icon)

### Step 6.5 – Configure Automatic Certificate Renewal

Let's Encrypt certificates expire after 90 days. Configure automatic renewal to avoid expiration.

**Test renewal process (dry run):**

```bash
# Perform a test renewal without actually renewing
certbot renew --dry-run --pre-hook "systemctl stop httpd" --post-hook "systemctl start httpd"
```

If the dry run succeeds, configure automatic renewal:

**Option A: Using Certbot Timer (Recommended)**

Certbot automatically installs a systemd timer for renewals when installed via snap:

```bash
# Check timer status
systemctl list-timers | grep certbot

# If not present, enable it
systemctl enable --now snap.certbot.renew.timer

# Or for EPEL installation:
systemctl enable --now certbot-renew.timer
```

**Option B: Using Cron (Alternative)**

Add a cron job for automatic renewal:

```bash
# Create renewal script
cat > /usr/local/bin/certbot-renew.sh << 'EOF'
#!/bin/bash
# Renew Let's Encrypt certificates and reload Apache

certbot renew \
    --pre-hook "systemctl stop httpd" \
    --post-hook "systemctl start httpd" \
    --quiet

exit 0
EOF

chmod 0755 /usr/local/bin/certbot-renew.sh

# Add cron job (runs twice daily at 3:30 AM and 3:30 PM)
cat > /etc/cron.d/certbot-renew << 'EOF'
30 3,15 * * * root /usr/local/bin/certbot-renew.sh
EOF
```

??? info "Renewal frequency and timing"
    
    - Certbot automatically checks certificates and only renews those expiring within 30 days
    - Running renewal checks twice daily ensures timely renewal even if one attempt fails
    - The `--quiet` flag suppresses output unless there's an error
    - Pre/post hooks stop and start Apache to free port 80 for the standalone authenticator

**Verify automatic renewal is configured:**

```bash
# For snap installation
systemctl status snap.certbot.renew.timer

# For EPEL installation
systemctl status certbot-renew.timer

# For cron-based renewal
crontab -l | grep certbot
# or
cat /etc/cron.d/certbot-renew
```

### Step 6.6 – Monitor Certificate Expiration

Even with automatic renewal, monitor certificate expiration to catch renewal failures:

**Check certificate expiration date:**

```bash
# Check all certificates
certbot certificates

# Check specific certificate via OpenSSL
echo | openssl s_client -connect <your-fqdn>:443 -servername <your-fqdn> 2>/dev/null | openssl x509 -noout -dates
```

**Set up expiration monitoring (optional):**

??? tip "Email alerts for expiration"
    
    Let's Encrypt sends expiration warning emails to the address provided during certificate issuance. Ensure this email
    address is monitored:
    
    ```bash
    # Check configured email
    grep email /etc/letsencrypt/renewal/<your-fqdn>.conf
    ```
    
    You can also set up local monitoring using nagios, icinga, or a simple script:
    
    ```bash
    #!/bin/bash
    # check-cert-expiry.sh - Alert if certificate expires within 14 days
    
    DOMAIN="<your-fqdn>"
    WARN_DAYS=14
    
    EXPIRY=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | \
             openssl x509 -noout -enddate | cut -d= -f2)
    
    EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -lt $WARN_DAYS ]; then
        echo "WARNING: Certificate for ${DOMAIN} expires in ${DAYS_LEFT} days!"
        # Send alert via email, Slack, etc.
    else
        echo "OK: Certificate valid for ${DAYS_LEFT} more days"
    fi
    ```

### Troubleshooting Let's Encrypt

??? failure "Certificate issuance fails with 'Connection refused'"
    
    **Symptoms:** Certbot fails with "Failed to authenticate" or "Connection refused" errors during HTTP-01 challenge.
    
    **Diagnostic steps:**
    
    ```bash
    # Verify port 80 is open in firewall
    nft list ruleset | grep "dport 80"
    
    # Test port 80 accessibility from external host
    curl -v http://<your-fqdn>/
    
    # Check nothing is listening on port 80
    ss -tlnp | grep :80
    ```
    
    **Solutions:**
    
    - Add port 80 to nftables: `/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-nftables.sh --ports=80,443 --yes`
    - Ensure Apache is not listening on port 80 (should only listen on 443)
    - Verify DNS resolves correctly from public internet
    - Check network firewall/router allows inbound port 80

??? failure "Certificate renewal fails"
    
    **Symptoms:** Certificate expires or renewal fails with errors in logs.
    
    **Diagnostic steps:**
    
    ```bash
    # Check renewal logs
    journalctl -u snap.certbot.renew.timer -n 50
    # or
    grep certbot /var/log/syslog | tail -50
    
    # Test renewal manually
    certbot renew --dry-run --pre-hook "systemctl stop httpd" --post-hook "systemctl start httpd" -vvv
    
    # Check certificate status
    certbot certificates
    ```
    
    **Common causes:**
    
    - Port 80 blocked: Verify firewall allows HTTP during renewal
    - Apache failed to stop/start: Check Apache service status
    - DNS changes: Verify hostname still resolves correctly
    - Rate limiting: Let's Encrypt has rate limits (5 renewals per 7 days per domain)
    
    **Solutions:**
    
    - Fix firewall or DNS issues
    - Manually renew: `certbot renew --force-renewal`
    - If rate limited, wait 7 days before retrying

??? failure "Browser shows old certificate after renewal"
    
    **Symptoms:** Certificate renewed successfully but browser still shows old/expired certificate.
    
    **Diagnostic steps:**
    
    ```bash
    # Check certificate files are updated
    ls -la /etc/letsencrypt/live/<your-fqdn>/
    
    # Verify Apache configuration points to correct files
    grep SSLCertificate /etc/httpd/conf.d/ssl.conf
    
    # Check Apache loaded the new certificate
    systemctl status httpd
    ```
    
    **Solutions:**
    
    - Reload or restart Apache: `systemctl restart httpd`
    - Clear browser cache and hard refresh (Ctrl+Shift+R)
    - Verify SSL configuration: `apachectl -t -D DUMP_VHOSTS`

---

## Step 7 – Configure and Enroll in pSConfig

Enroll your toolkit host with the OSG/WLCG pSConfig service so tests are auto-configured. Use the "auto URL" for each FQDN
you expose for perfSONAR (one or two depending on whether you split latency/throughput by hostname).

### Option A: Web UI Configuration (Recommended)

The easiest way to configure pSConfig is via the web interface:

1. Navigate to: `https://<your-hostname>/toolkit/admin?view=psconfig`
1. Click "Add Remote Configuration"
1. Enter the auto URL: `https://psconfig.opensciencegrid.org/pub/auto/<your-fqdn>`
1. Enable "Configure Archives" to automatically set up result archiving
1. Save and restart the pSConfig agent

### Option B: Command Line Configuration

Basic enrollment via command line:


```bash
# Add auto URLs (configures archives too) and show configured remotes
psconfig remote --configure-archives add \
    "https://psconfig.opensciencegrid.org/pub/auto/ps-lat-example.my.edu"

psconfig remote list
```

If there are any stale/old/incorrect entries, you can remove them:


```bash
psconfig remote delete "<old-url>"
```

### Option C: Automated Enrollment Script


Automation tip: derive FQDNs from your configured IPs (PTR lookup) and enroll automatically. Review the list before applying.

**For RPM Toolkit installs (non-container):**

```bash
# Dry run only (show planned URLs):
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-auto-enroll-psconfig.sh --local -n

# Apply enrollment:
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-auto-enroll-psconfig.sh --local -v

# Verify configured remotes
psconfig remote list
```

**For container-based installs:**

```bash
# Dry run only (show planned URLs):
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -n

# Apply enrollment:
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -v

# Verify configured remotes
podman exec -it perfsonar-testpoint psconfig remote list
```

??? note "The auto enroll psconfig script details"
    
    - Parses IP lists from `/etc/perfSONAR-multi-nic-config.conf`  (`NIC_IPV4_ADDRS` / `NIC_IPV6_ADDRS`).
    - Performs reverse DNS lookups (getent/dig) to derive FQDNs.
    - Deduplicates while preserving discovery order.
    - Adds each `https://psconfig.opensciencegrid.org/pub/auto/<FQDN>` with `--configure-archives`.
    - Lists configured remotes and returns non-zero if any enrollment fails.

    Integrate into provisioning CI by running with `-n` (dry-run) for approval and then `-y` once approved.

---

## Step 8 – Register and Configure with WLCG/OSG

1. **OSG/WLCG registration workflow:**

    ??? info "Registration steps and portals"
        
        - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
        - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
        - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint
                `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

1. **Document memberships:**

    Update your site wiki or change log with assigned mesh names, feed  URLs, and support contacts.

1. **Update Lookup Service registration:**

    **Option A: Web UI (Recommended)**
    
    The easiest way to configure registration information is via the Toolkit web interface:
    
    1. Navigate to: `https://<your-hostname>/toolkit/admin?view=host`
    1. Fill in administrative information:
        - Site name, organization, location (city, state, country, zip code)
        - Latitude and longitude (for map display)
        - Administrator name and email
        - Projects (WLCG, OSG, etc.)
    1. Save changes - the lsregistrationdaemon restarts automatically
    
    **Option B: Command Line**
    
    Edit `/etc/perfsonar/lsregistrationdaemon.conf` directly and restart the service:
    
    ```bash
    vi /etc/perfsonar/lsregistrationdaemon.conf
    
    # After editing, restart the registration daemon
    systemctl restart perfsonar-lsregistrationdaemon
    ```
    
    **Option C: Helper Script**
    

    Use the helper script to update registration. For RPM Toolkit installs, use the `--local` flag:

    **For RPM Toolkit installs (non-container):**
    ```bash
    # Preview changes only
    /opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh update --local \
        --dry-run --site-name "Acme Co." --project WLCG \
        --admin-email admin@example.org --admin-name "pS Admin"

    # Apply new settings and restart the daemon
    /opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh create --local \
        --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
        --city Berkeley --region CA --country US --zip 94720 \
        --latitude 37.5 --longitude -121.7469 \
        --admin-name "pS Admin" --admin-email admin@example.org

    # Save current config (raw conf file)
    /opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh save --output my-lsreg.conf --local

    # Or produce a self-contained executable restore script
    /opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh extract --output /root/restore-lsreg.sh --local
    ```

1. **Automatic updates**

    The perfSONAR Toolkit uses `dnf-automatic` for automatic updates (already configured in Step 5).

---

## Step 9 – SELinux Troubleshooting (If Enabled)

If you've enabled SELinux in enforcing mode, certain perfSONAR operations may generate audit log alerts. This section explains common issues and their fixes.

### SELinux Basics for perfSONAR

SELinux enforces mandatory access controls based on file labels and process contexts. perfSONAR services run under specific contexts (e.g., `lsregistrationdaemon_t`, `httpd_t`), and accessed files must have compatible labels.

**Check SELinux status:**

```bash
sestatus
# Expected output: "SELinux status:  enabled" and "Current mode:  enforcing"
```

### Common SELinux Issues and Fixes

#### Issue 1: `/etc/perfsonar/lsregistrationdaemon.conf` Has Wrong Label

**Symptom:** Audit log shows:
```
SELinux is preventing /usr/bin/perl from getattr access on the file /etc/perfsonar/lsregistrationdaemon.conf.
```

**Root cause:** The configuration file was created or modified (e.g., via restore or manual edit) and has an incorrect SELinux label. The file should be labeled `lsregistrationdaemon_etc_t` but may be labeled `admin_home_t` or have no label.

**Fix: Apply `restorecon` to relabel the file:**

```bash
# Restore the default SELinux context for the file
sudo /sbin/restorecon -v /etc/perfsonar/lsregistrationdaemon.conf

# Verify the label is now correct
ls -Z /etc/perfsonar/lsregistrationdaemon.conf
# Expected: system_u:object_r:lsregistrationdaemon_etc_t:s0
```

**Automatic fix during restore:**

Our `perfSONAR-update-lsregistration.sh` helper attempts to automatically apply `restorecon` after writing the configuration file. If `restorecon` is available on your system, it runs without user intervention:

```bash
# Use the helper to restore config (with automatic restorecon attempt)
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh restore --local \
    --input ./my-lsreg.conf

# Or extract and run a self-contained restore script
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-update-lsregistration.sh extract --local \
    --output ./restore-lsreg.sh
./restore-lsreg.sh  # This script includes a restorecon attempt
```

**Preventing the issue:**

- Always use the helper script (`perfSONAR-update-lsregistration.sh`) for configuration changes, as it handles `restorecon` automatically.
- After any manual edits to `/etc/perfsonar/lsregistrationdaemon.conf`, explicitly run `restorecon`:
  ```bash
  sudo vi /etc/perfsonar/lsregistrationdaemon.conf
  sudo /sbin/restorecon -v /etc/perfsonar/lsregistrationdaemon.conf  # Fix labels immediately
  sudo systemctl restart perfsonar-lsregistrationdaemon
  ```

#### Issue 2: Other Services (ethtool, df, python3, postgresql, collect2) Generating Audit Alerts

**Symptoms:** Audit log shows alerts for various tools running in unexpected SELinux contexts:
```
SELinux is preventing /usr/sbin/ethtool from setopt access on netlink_generic_socket labeled httpd_t.
SELinux is preventing /usr/bin/df from getattr access on the directory /var/cache/openafs.
SELinux is preventing /usr/bin/python3.9 from execute access on the file ldconfig.
SELinux is preventing /usr/libexec/gcc/x86_64-redhat-linux/11/collect2 from search access on the directory snapd.
```

**Root cause:** These alerts typically stem from:
- Tools invoked from web interfaces or services running in different SELinux contexts (e.g., `httpd_t`, `postgresql_t`)
- Third-party or system utilities that lack complete SELinux policy coverage
- Legitimate operations conflicting with default policy rules
- Build/compilation tools invoked during package installation (usually transient)

**Assessment and diagnosis:**

1. **Check if the alert is related to perfSONAR functionality:**
   
   ```bash
   # View recent audit alerts
   tail -100 /var/log/audit/audit.log
   
   # Filter by command name to see context
   grep "ethtool\|df\|python\|collect2\|ldconfig" /var/log/audit/audit.log | head -20
   
   # Count alert types to identify patterns
   ausearch -m AVC | awk -F'avc:' '{print $2}' | sort | uniq -c | sort -rn | head -10
   ```

2. **Determine the source process and context:**
   
   - Alerts mentioning `httpd_t` usually indicate the web UI triggered the operation (typically safe to allow)
   - Alerts from `postgresql_t` indicate database tools being invoked (context boundary may not be required)
   - Alerts from `lsregistrationdaemon_t` indicate the registration daemon needs access (fix labels first, not policies)
   - Alerts from `gcc/collect2` during package install are usually transient (monitor periodically)

3. **Create a local SELinux policy module** (if operation is verified as safe)
   
   ```bash
   # Generate policy module for a specific alert (example: ethtool)
   sudo ausearch -c 'ethtool' --raw | audit2allow -M my-ethtool
   
   # Review the generated module to ensure it's safe
   cat my-ethtool.te
   
   # Install the module (if approved and safe)
   sudo semodule -i my-ethtool.pp
   
   # Verify installation
   semodule -l | grep my-ethtool
   ```

**Specific service fixes:**

**ethtool netlink access (from httpd_t or lsregistrationdaemon_t):**
   - **Operation:** Checking NIC link status, speed, duplex (safe)
   - **Source:** Web UI health checks or daemon monitoring
   - **Fix:**
     ```bash
     sudo ausearch -c 'ethtool' --raw | audit2allow -M my-ethtool
     sudo semodule -i my-ethtool.pp
     ```

**df/stat on /var/cache/openafs (from lsregistrationdaemon_t):**
   - **Operation:** Checking available disk space (safe)
   - **Source:** Registration daemon system health queries
   - **Fix:**
     ```bash
     sudo ausearch -c 'df' --raw | audit2allow -M my-df
     sudo semodule -i my-df.pp
     ```

**python3/postgresql context issues (collect2, ldconfig):**
   - **Operation:** Build tools, library checks during package installation (usually transient)
   - **Assessment:** These are typically safe but may be ephemeral
   - **Fix (if persistent):**
     ```bash
     # For postgresql-related alerts
     sudo ausearch -c 'validate-config' --raw | audit2allow -M my-postgresql
     sudo semodule -i my-postgresql.pp
     ```

**Audit log monitoring (prevents future surprises):**

```bash
# Check for recent AVC denials
sudo ausearch -m AVC -ts recent | tail -50

# Create a daily monitoring script
cat > /usr/local/bin/check-selinux-alerts.sh << 'EOF'
#!/bin/bash
# Check for recent SELinux audit alerts

RECENT_ALERTS=$(ausearch -m AVC -ts recent 2>/dev/null | wc -l)

if [ $RECENT_ALERTS -gt 0 ]; then
    echo "WARNING: Found $RECENT_ALERTS recent SELinux alerts:"
    ausearch -m AVC -ts recent | tail -20
else
    echo "OK: No recent SELinux audit alerts"
fi
EOF

chmod 0755 /usr/local/bin/check-selinux-alerts.sh

# Add to cron (runs daily at 9 AM)
echo "0 9 * * * root /usr/local/bin/check-selinux-alerts.sh" | sudo tee /etc/cron.d/selinux-alert-check
```

**Best practice for handling alerts:**

1. Log all alerts for 1-2 weeks to establish a baseline
2. Review and categorize (safe vs. unsafe operations)
3. Create local policy modules only for verified, safe operations
4. Document each module in your change log
5. Monitor weekly for new or unexpected alerts


#### Issue 3: Audit Log Flooding

**Symptom:** Audit log grows very large due to repeated identical alerts.

**Mitigation:**

```bash
# View count of each AVC alert type
ausearch -m AVC | awk -F'avc:' '{print $2}' | sort | uniq -c | sort -rn | head -20

# Suppress specific alerts (if they are verified as safe):
# Add rules to /etc/audit/audit.rules or /etc/audit/rules.d/
# (requires audit service restart and SELinux expertise)
```

### Best Practices for SELinux with perfSONAR

1. **Use automated tools:** Always use the helper scripts (`perfSONAR-update-lsregistration.sh`, `perfSONAR-install-nftables.sh`) which handle SELinux contexts automatically.

2. **Run `restorecon` after manual edits:** If you manually edit any perfSONAR configuration file, immediately restore the SELinux context:
   ```bash
   sudo /sbin/restorecon -v /path/to/file
   ```

3. **Monitor audit logs regularly:** Check `/var/log/audit/audit.log` weekly to catch new issues early.

4. **Document exceptions:** If you create local SELinux policy modules, document them in your change log so future admins understand why they exist.

5. **Keep policies minimal:** Only add local policy modules for operations that are verified as safe and necessary. Overly permissive policies increase security risk.

---

## Step 10 – Install flowd-go for SciTags Flow Marking (Recommended)

[flowd-go](https://github.com/scitags/flowd-go) is a lightweight daemon from the
[SciTags](https://www.scitags.org/) initiative that tags perfSONAR network flows with experiment and
activity metadata. When enabled, every egress packet is stamped with an IPv6 Flow Label identifying the
generating experiment, allowing network operators to attribute and monitor measurement traffic.

For background on SciTags and fireflies, see
[SciTags, Fireflies, and perfSONAR](../../perfsonar/scitags-fireflies.md).

!!! tip "flowd-go is optional but recommended"

    flowd-go installation is the default for new deployments. If you do not want SciTags flow marking,
    simply skip this step.

### Install using the helper script

The helper script installs the flowd-go RPM, prompts for your experiment affiliation, auto-detects
network interfaces from `/etc/perfSONAR-multi-nic-config.conf`, writes the configuration, and enables the
service:

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-flowd-go.sh
```

**Non-interactive mode** (auto-confirm, specify experiment on command line):

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-flowd-go.sh \
    --experiment-id 2 --yes
```

**List available experiment IDs:**

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-flowd-go.sh --list-experiments
```

**Specify interfaces manually** (overrides auto-detection):

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-flowd-go.sh \
    --experiment-id 3 --interfaces ens4f0np0,ens4f1np1 --yes
```

??? info "What the script does"

    1. Downloads and installs the `flowd-go` RPM from the SciTags repository
    2. Prompts for the SciTags experiment ID (ATLAS, CMS, LHCb, etc.)
    3. Auto-detects target interfaces from `/etc/perfSONAR-multi-nic-config.conf` or the routing table
    4. Writes `/etc/flowd-go/conf.yaml` with the `perfsonar` plugin and `marker` backend
    5. Enables and starts the `flowd-go` systemd service

??? info "Flags reference"

    | Flag | Description |
    | ---- | ----------- |
    | `--experiment-id N` | SciTags experiment ID (1-14) |
    | `--activity-id N` | Activity ID (default: 2 = network testing) |
    | `--interfaces LIST` | Comma-separated NIC names (auto-detected if omitted) |
    | `--list-experiments` | Show experiment IDs and exit |
    | `--yes` | Skip interactive prompts |
    | `--dry-run` | Preview without changes |
    | `--uninstall` | Remove flowd-go and configuration |

### Verify flowd-go is running

```bash
systemctl status flowd-go
journalctl -u flowd-go --no-pager -n 20
tc qdisc show
```

### Removing flowd-go

If you later decide to remove flowd-go:

```bash
/opt/perfsonar-toolkit/tools_scripts/perfSONAR-install-flowd-go.sh --uninstall
```

---

## Step 11 – Post-Install Validation

Perform these checks before handing the host over to operations:

1. **System services:**

    ??? info "Verify perfSONAR services"
        
        ```bash
        # Check all perfSONAR services are running
        systemctl status pscheduler-scheduler pscheduler-runner pscheduler-archiver pscheduler-ticker
        systemctl status psconfig-pscheduler-agent owamp-server perfsonar-lsregistrationdaemon
        
        # Check web server (Apache)
        systemctl status apache2 --no-pager
        
        # Check measurement archive services
        systemctl status opensearch logstash
        ```

    Ensure all services show `active (running)` status.

1. **Web interface access:**

    ??? info "Verify web UI is accessible"
        
        ```bash
        # Test HTTPS connectivity to web UI
        curl -k -s -o /dev/null -w "%{http_code}" https://localhost/toolkit
        # Should return 200
        
        # Check Apache error logs if issues
        journalctl -u apache2 -n 50
        ```
        
        Access the web UI in a browser: `https://<your-hostname>/toolkit`
        
        Verify the dashboard loads and shows measurement results (may take a few minutes after first tests run).

1. **Service logs:**

    ??? info "Check perfSONAR service logs for errors"
        
        ```bash
        # Check pScheduler logs for errors
        journalctl -u pscheduler-scheduler -n 50 --no-pager
        journalctl -u pscheduler-runner -n 50 --no-pager
        
        # Check pSConfig agent logs
        journalctl -u psconfig-pscheduler-agent -n 50 --no-pager
        
        # Check registration daemon
        journalctl -u perfsonar-lsregistrationdaemon -n 20 --no-pager
        ```

1. **Network path validation:**

    ??? info "Test network connectivity and routing"
        
        Test throughput to a remote endpoint:
        ```bash
        pscheduler task throughput --dest <remote-testpoint>
        ```
        
        Check routing from the host:
        ```bash
        tracepath -n <remote-testpoint>
        ip route get <remote-testpoint-ip>
        ```
        
        Confirm traffic uses the intended policy-based routes (check `ip route get <dest>`).
        
1. **Security posture:**

    ??? info "Check firewall, fail2ban, and SELinux"
        
        ```bash
        # Check nftables firewall rules
        nft list ruleset | grep perfsonar

        # Check fail2ban status (automatically installed by toolkit)
        systemctl status fail2ban
        fail2ban-client status

        # Check for recent SELinux denials
        if command -v ausearch >/dev/null 2>&1; then
            ausearch --message AVC --just-one
        elif [ -f /var/log/audit/audit.log ]; then
            grep -i "avc.*denied" /var/log/audit/audit.log | tail -5
        else
            echo "SELinux audit tools not available"
        fi
        ```

    Investigate any SELinux denials or repeated Fail2Ban bans.

1. **Certificate check (if using HTTPS):**

    ??? info "Verify certificate validity"
        
        ```bash
        # Check certificate via HTTPS connection
        echo | openssl s_client -connect <your-hostname>:443 -servername <your-hostname> 2>/dev/null | openssl x509 -noout -dates -issuer
        ```

    Ensure the certificate is valid and not expired.

1. **Measurement archive:**

    ??? info "Verify local archive is collecting data"
        
        Check that OpenSearch is receiving measurement results:
        
        ```bash
        # Check OpenSearch cluster health
        curl -k https://localhost:9200/_cluster/health?pretty
        
        # Check for measurement data (after tests have run)
        curl -k https://localhost:9200/_cat/indices?v | grep pscheduler
        ```
        
        Via web UI: Navigate to `https://<your-hostname>/toolkit/archive` to view stored measurements.

1. **Reporting:**

    ??? info "Run perfSONAR diagnostic reports"
        
        Run the perfSONAR troubleshoot command and send outputs to operations:
        ```bash
        pscheduler troubleshoot
        ```
    
---

## Ongoing Maintenance

- **Quarterly or as-needed:** Re-validate routing policy and nftables rules after network changes or security audits.

- **Monthly or during maintenance windows:** Apply OS updates (`dnf update`) and reboot during scheduled downtime.

- Monitor psconfig feeds for changes in mesh participation and test configuration.

- Track certificate expiry with `certbot renew --dry-run` if you rely on Let's Encrypt (automatic renewal is configured but monitoring is recommended).

- Review container logs periodically for errors: `podman logs perfsonar-testpoint` and `podman logs certbot`.

- Verify auto-update timer is active: `systemctl list-timers perfsonar-auto-update.timer`.

---

## Updating an Existing Deployment

The **dnf-automatic** service (Step 5.3) keeps perfSONAR RPM packages current on a
daily schedule, but it does not update the **helper scripts** installed during
Step 2.4 (PBR generator, fasterdata tuning, DNS checker, nftables helpers, etc.).
When the repository publishes bug fixes or new features that touch these scripts you
need to run the **deployment updater** to bring your installation in sync.

### Quick update (one-liner)

If you already have the tools installed under `/opt/perfsonar-toolkit/tools_scripts`:

```bash
/opt/perfsonar-toolkit/tools_scripts/update-perfsonar-deployment.sh --type toolkit --apply --restart --yes
```

If the script is not yet present (older installations), bootstrap it first:

```bash
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/update-perfsonar-deployment.sh \
  -o /tmp/update-perfsonar-deployment.sh
chmod 0755 /tmp/update-perfsonar-deployment.sh
/tmp/update-perfsonar-deployment.sh --type toolkit --apply --restart --yes
```

### What the updater does

| Phase | Action | Default |
| ----- | ------ | ------- |
| 1 — Scripts | Re-downloads all helper scripts from the repository | Always |
| 2 — Config files | Installs or updates host configuration overrides (if any) | Report only; `--apply` to write |
| 3 — RPM packages | Checks for `perfsonar*` package updates via `dnf` | Report only; `--apply` to install |
| 4 — Services | Restarts perfSONAR daemons if packages or configs changed | Only with `--restart` |

!!! note "Phase 5 (systemd units) is skipped for toolkit deployments"
    Toolkit installations manage their own systemd services via RPM scriptlets.
    The `--update-systemd` flag only applies to container deployments.

### Report-only mode (safe, no changes)

Run without flags to see what would change:

```bash
/opt/perfsonar-toolkit/tools_scripts/update-perfsonar-deployment.sh --type toolkit
```

### Full update with restart

```bash
/opt/perfsonar-toolkit/tools_scripts/update-perfsonar-deployment.sh \
    --type toolkit --apply --restart --yes
```

??? info "Updater flags reference"

    | Flag | Description |
    | ---- | ----------- |
    | `--type TYPE` | Deployment type: `container` or `toolkit` (auto-detected if omitted) |
    | `--base DIR` | Base directory (default: auto-detected) |
    | `--apply` | Apply changes (default: report only) |
    | `--restart` | Restart services after updates (implies `--apply`) |
    | `--update-systemd` | Re-run `install-systemd-units.sh` (container only, ignored for toolkit) |
    | `--yes` | Skip interactive confirmations |
    | `--dry-run` | Show what would change without modifying anything |

??? tip "When should I run the updater?"

    - After the repository announces bug fixes or new features affecting helper scripts
    - When you see a new release in the [CHANGELOG](https://github.com/osg-htc/networking/blob/master/CHANGELOG.md)
    - If you encounter a known issue that has been fixed in a newer script version
    - After a major perfSONAR version upgrade to ensure helper scripts are compatible

---

## Troubleshooting

### Networking Issues

??? failure "Policy-based routing not working correctly"
    
    **Symptoms:** Traffic not using expected interfaces, routing to wrong gateway.
    
    **Diagnostic steps:**
    
    ```bash
    # Check routing rules
    ip rule show

    # Check routing tables
    ip route show table all


    # Test specific route lookup
    ip route get <destination-ip>

    # Check NetworkManager connections
    nmcli connection show

    # Review PBR script log
    tail -100 /var/log/perfSONAR-multi-nic-config.log

    ```

    **Solutions:**

    - Verify `/etc/perfSONAR-multi-nic-config.conf` has correct IPs and gateways
    - Reapply configuration: `/opt/perfsonar-toolkit/tools_scripts/perfSONAR-pbr-nm.sh --yes`
    - Reboot if rules are not being applied correctly
    - Check for conflicting NetworkManager or systemd-networkd rules

??? failure "DNS resolution failing for test endpoints"
    
    **Symptoms:** perfSONAR tests fail with "unknown host" or DNS errors.
    
    **Diagnostic steps:**
    
    ```bash
    # Test DNS resolution from container
    podman exec -it perfsonar-testpoint dig <remote-testpoint>

    # Check container's resolv.conf

    podman exec -it perfsonar-testpoint cat /etc/resolv.conf

    # Verify forward and reverse DNS
    /opt/perfsonar-toolkit/tools_scripts/check-perfsonar-dns.sh

    ```

    **Solutions:**

    - Ensure DNS servers are correctly configured on host
    - Fix missing PTR records in DNS zones
    - Verify forward A/AAAA records match reverse PTR records

### Certificate Issues

??? failure "Let's Encrypt certificate issuance fails"
    
    **Symptoms:** Certbot fails with "Failed to authenticate" or "Connection refused" errors.
    
    **Diagnostic steps:**
    
    ```bash
    # Check if port 80 is open
    nft list ruleset | grep "80"

    # Verify Apache is NOT listening on port 80 in container
    podman exec perfsonar-testpoint netstat -tlnp | grep :80

    # Test port 80 accessibility from external host
    curl -v http://<your-fqdn>/

    # Run certbot in verbose mode

    podman run --rm --net=host \
        -v /etc/letsencrypt:/etc/letsencrypt:Z \
        -v /var/www/html:/var/www/html:Z \
        docker.io/certbot/certbot:latest certonly \
        --standalone -d <SERVER_FQDN> -m <EMAIL> --dry-run -vvv

    ```

    **Common causes:**

    - Port 80 blocked by firewall: Add with `perfSONAR-install-nftables.sh --ports=80,443`
    - Apache listening on port 80: Verify testpoint-entrypoint-wrapper.sh patched Apache correctly
    - DNS not propagated: Wait for DNS changes to propagate globally
    - Rate limiting: Let's Encrypt has rate limits; wait if you've hit them

??? failure "Certificate not loaded after renewal"
    
    **Symptoms:** Old certificate still in use after automatic renewal.
    
    **Diagnostic steps:**
    
    ```bash
    # Check certificate files
    ls -la /etc/letsencrypt/live/<fqdn>/

    # Verify deploy hook is configured
    podman logs certbot 2>&1 | grep "deploy hook"

    # Check if container restarted
    podman ps --format 'table {{.Names}}\t{{.Status}}'

    # Manually restart testpoint
    podman restart perfsonar-testpoint

    ```

    **Solutions:**

    - Verify deploy hook script exists and is executable: `/opt/perfsonar-toolkit/tools_scripts/certbot-deploy-hook.sh`
    - Ensure deploy hook is mounted in container at: `/etc/letsencrypt/renewal-hooks/deploy/certbot-deploy-hook.sh`
    - Verify Podman socket is mounted in certbot container: `/run/podman/podman.sock`
    - Check deploy hook logs: `journalctl -u perfsonar-certbot.service | grep deploy`
    - Manually restart testpoint after renewals if deploy hook fails: `podman restart perfsonar-testpoint`

    **Note:** Certbot automatically executes scripts in `/etc/letsencrypt/renewal-hooks/deploy/` when certificates are
    renewed. Do not use `--deploy-hook` parameter with full paths ending in `.sh` as certbot will append `-hook` to the filename.

### perfSONAR Service Issues

??? failure "perfSONAR services not running"
    
    **Symptoms:** Web interface not accessible, pScheduler tests not running.
    
    **Diagnostic steps (RPM install):**
    
    ```bash
    # Check key services
    systemctl status httpd pscheduler-scheduler pscheduler-runner pscheduler-ticker

    # Check for recent errors in service logs
    journalctl -u httpd -u pscheduler-scheduler -u pscheduler-runner -u pscheduler-ticker -n 100

    # pScheduler diagnostics
    pscheduler troubleshoot
    ```

    **Solutions:**

    - Restart services: `systemctl restart httpd pscheduler-scheduler pscheduler-runner pscheduler-ticker`
    - Verify certificates are in place (if using HTTPS): `ls -la /etc/letsencrypt/live/`
    - Check Apache SSL configuration and vhost

### Auto-Update Issues

??? failure "Auto-update not working"
    
    **Symptoms:** `yum update`/`dnf update` not picking up perfSONAR updates or cron/Ansible automation failing.
    
    **Diagnostic steps (RPM install):**
    
    ```bash
    # Check when repo metadata was last refreshed
    sudo dnf repolist -v | head -n 20

    # Check for available perfSONAR updates
    sudo dnf list updates 'perfsonar*'

    # If you have a local cron/automation script, review its logs
    sudo journalctl -u cron -n 200
    ```

    **Solutions:**

    - Refresh metadata: `sudo dnf clean all && sudo dnf makecache`
    - Update packages: `sudo dnf update -y 'perfsonar*'`
    - Verify repositories are enabled and reachable (perfSONAR, EPEL, CRB)
    - If using site automation, confirm the job is scheduled and succeeds

### General Debugging Tips

??? tip "Useful debugging commands"
    
    **Service management (RPM install):**
    
    ```bash
    # Check key services
    systemctl status httpd pscheduler-scheduler pscheduler-runner pscheduler-ticker

    # Restart key services
    systemctl restart httpd pscheduler-scheduler pscheduler-runner pscheduler-ticker

    # pScheduler diagnostics
    pscheduler troubleshoot
    ```

    **Networking:**

    ```bash
    # Check which process is listening on a port
    ss -tlnp | grep <port>

    # Test connectivity to remote host
    ping <remote-ip>
    traceroute <remote-ip>

    # Check nftables rules (or firewalld if used)
    nft list ruleset
    # or
    firewall-cmd --list-all
    ```

??? note "What to include when reporting issues via email"

    To help us diagnose toolkit (RPM) install problems quickly, please include:

    - Host details: OS version (`cat /etc/os-release`), kernel (`uname -r`), and that this is a **Toolkit/RPM** install.
    - What failed: which step/command you ran and the exact error output (paste the terminal snippet).
    - Timestamps: approximate time of failure and timezone.
    - Packages/services: `rpm -qa 'perfsonar*' | sort | head -n 30`, and `systemctl status pscheduler-scheduler pscheduler-runner pscheduler-ticker httpd`.
    - Logs: `journalctl -u pscheduler-scheduler -u pscheduler-runner -u pscheduler-ticker -u httpd -n 200`, plus any relevant `/var/log/perfsonar/*.log` excerpts.
    - Network state: `ip -br addr`, `ip rule show`, `nmcli connection show`, and `nft list ruleset` (or `firewall-cmd --list-all` if firewalld is used).
    - Certificates (if Let’s Encrypt or custom HTTPS involved): whether port 80/443 are reachable externally and excerpts from `/var/log/httpd/error_log` and `/var/log/letsencrypt/letsencrypt.log`.
    - Contact info: your name, site, and a callback email.

    Send reports to your usual perfSONAR support contact or project mailing list with the subject prefix `[perfSONAR toolkit install issue]`.

    **Logs (RPM install):**

    ```bash
    # Web server errors
    journalctl -u httpd -n 200
    tail -n 200 /var/log/httpd/error_log

    # pScheduler services
    journalctl -u pscheduler-scheduler -u pscheduler-runner -u pscheduler-ticker -n 200

    # perfSONAR application logs (if present)
    ls /var/log/perfsonar
    tail -n 200 /var/log/perfsonar/pscheduler.log 2>/dev/null
    ```

---
