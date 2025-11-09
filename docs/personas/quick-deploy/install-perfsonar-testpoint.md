# Installing a perfSONAR Testpoint for WLCG/OSG

This guide walks WLCG/OSG site administrators through end-to-end installation, configuration, and validation of a perfSONAR testpoint on Enterprise Linux 9 (EL9). It uses automated tooling from this repository to streamline the process while accommodating site-specific requirements.

---

## Prerequisites and Planning

Before you begin, it may be helpful to gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage locations.
- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN
  information.
- **Operational contacts:** site admin email, OSG facility/site name, latitude/longitude.


## Existing perfSONAR configuration

If replacing an existing instance, you may want to back up `/etc/perfsonar/` files, especially `lsregistrationdaemon.conf`, and any container volumes. We have a script named`perfSONAR-update-lsregistration.sh` to extract/save/restore registration config that you may want to use.


??? info "Quick capture of existing lsregistration config (if you have a src)"

     Download temporarily:

    ```bash
    curl -fsSL \
      https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh \
      -o /tmp/update-lsreg.sh
    chmod 0755 /tmp/update-lsreg.sh

    ```
    
    Use the downloaded tool to extract a restore script:

    ```bash
    /tmp/update-lsreg.sh extract --output /root/restore-lsreg.sh
    ```



Note: Repository clone instructions are in Step 2.

> **Note:** All shell commands assume an interactive root shell.

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
    dnf remove -y rsyslog
    ```

    ??? info "Why disable unused services?"

        We recommend disabling unused services during initial provisioning to
        reduce complexity and avoid unexpected interference with network and
        container setup. Services such as `firewalld`, `NetworkManager-wait-online`,
        and `rsyslog` can alter networking state, hold boot or network events,
        or conflict with the automated nftables/NetworkManager changes performed
        by the helper scripts. Disabling non-essential services makes the
        install deterministic, reduces the host attack surface, and avoids
        delays or race conditions while configuring policy-based routing,
        nftables rules, and container networking.

1. **Update the system and packages:**

    ```bash
    dnf -y update
    ```

1. **Record NIC names:** Document interface mappings for later PBR configuration.

    ```bash
    nmcli device status
    ip -br addr
    ```

---

## Step 2 – Bootstrap the Testpoint and Tools

Use the bootstrap script to clone the perfSONAR testpoint repository into `/opt/perfsonar-tp` and install helper scripts under `/opt/perfsonar-tp/tools_scripts`.

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
    -o /tmp/install_tools_scripts.sh
chmod 0755 /tmp/install_tools_scripts.sh
/tmp/install_tools_scripts.sh /opt/perfsonar-tp
```

After this step scripts are available at `/opt/perfsonar-tp/tools_scripts`.

> **Note:** All shell commands assume an interactive root shell. Prefix with `sudo` when running as a non-root user.

**Find needed packages and verify dependencies:**

Use the helper to check for required tools.
```bash
/opt/perfsonar-tp/tools_scripts/check-deps.sh
```

---
## Step 3 – Configure Policy-Based Routing (PBR)

The script `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh` automates NetworkManager profiles and routing rule setup.  It attempts to fill out the needed network configuraiton in `/etc/perfSONAR-multi-nic-config.conf`


1. **Generate config file automatically:**

    !!! warning "Gateways required for addresses"

        Any NIC with an IPv4 address must also have an IPv4 gateway, and any NIC with an IPv6 address
        must have an IPv6 gateway. If the generator cannot detect a gateway, it adds a WARNING block
        to the generated file listing affected NICs. Edit `NIC_IPV4_GWS`/`NIC_IPV6_GWS` accordingly before applying changes.

    !!! note "Gateway prompts"

        During generation, the script attempts to detect gateways per-NIC. If a NIC has an IP address
        but no gateway could be determined, it will prompt you interactively to enter an IPv4 and/or
        IPv6 gateway (or `-` to skip). Prompts are skipped in non-interactive sessions or when you use `--yes`.

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto
    ```

    The script writes the config file to `/etc/perfSONAR-multi-nic-config.conf`. Edit to adjust site-specific values (e.g., confirm `DEFAULT_ROUTE_NIC`, add `NIC_IPV4_ADDROUTE` entries) and verify the entries.  Next step is to apply the network changes...

1. **Apply changes:**

    !!! warning "Connect via console for network changes"

        When applying network changes across an ssh connection, your session may be interrupted.   Please try to run the perfSONAR-pbr-nm.sh script when connected either direcatly to the console or by using 'nohup' in front of the script invocation.

    Apply non-interactively with `--yes` or interactively without:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes
    ```

    The script backs up NetworkManager profiles, seeds routing tables, and applies rules. Review `/var/log/perfSONAR-multi-nic-config.log` and retain it. Reboot if needed (sometimes this seems to be required to get the changed networking in place).

1. **DNS: forward and reverse entries (required):**

    All IP addresses that will be used for perfSONAR testing MUST have DNS entries: a forward (A/AAAA)
    record and a matching reverse (PTR) record. This is required so remote test tools and site operators
    can reliably reach and identify your host, and because some measurement infrastructure and
    registration systems perform forward/reverse consistency checks.

    - For single-stack IPv4-only hosts: ensure A and PTR are present and consistent.
    - For single-stack IPv6-only hosts: ensure AAAA and PTR are present and consistent.
    - For dual-stack hosts: both IPv4 and IPv6 addresses used for testing must have matching forward and reverse records (A+PTR and AAAA+PTR).

    ??? example "Run the DNS checker"
        Validate forward/reverse DNS for addresses in `/etc/perfSONAR-multi-nic-config.conf`.

        ```bash
        /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh
        ```

    **Notes and automation tips:**

    - The script above uses `dig` (bind-utils package) which is commonly available; you can adapt it
      to use `host` if preferred.
    - Run the check as part of your provisioning CI or as a pre-flight check before enabling measurement registration.
    - For large sites or many addresses, parallelize the checks (xargs -P) or use a small Python
      script that leverages `dns.resolver` for async checks.
    - If your PTR returns a hostname with a trailing dot, the script strips it before the forward check.

    If any addresses fail these checks, correct the DNS zone (forward and/or reverse) and allow DNS propagation before proceeding with registration and testing.

1. **Verify the routing policy:**

    ```bash
    nmcli connection show
    ip rule show
    ip route show table <table-id>
    ```

    Confirm that non-default interfaces have their own routing tables and that the default interface owns the system default route.

---
## Step 4 – Configure nftables, SELinux, and Fail2Ban

Use `/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh` to configure a hardened nftables profile with optional SELinux and Fail2Ban support. No staging or copy step is required.

Prerequisites (not installed by the script and should have been installed when check-deps.sh was run above):

- `nftables` must already be installed and available (`nft` binary) for firewall configuration.
- `fail2ban` must be installed if you want the optional jail configuration.
- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

1. **Install/configure the desired options:**

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes
    ```

    - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the
      summary and answer manually).
    - Add `--dry-run` for a rehearsal that only prints the planned actions.

    The script writes nftables rules for perfSONAR services, derives SSH allow-lists from
    `/etc/perfSONAR-multi-nic-config.conf`, optionally adjusts SELinux, and enables Fail2ban jails—only if those components are already installed.

    ??? info "SSH allow-lists and validation"

        - Derives SSH allow-lists from `/etc/perfSONAR-multi-nic-config.conf` (CIDR prefixes and addresses).
        - Validates nftables rules before writing.
        - Outputs: rules to `/etc/nftables.d/perfsonar.nft`, log to `/var/log/perfSONAR-install-nftables.log`, backups to `/var/backups/`.

    ??? tip "Preview nftables rules before applying"
        You can preview the fully rendered nftables rules (no changes are made):
    
        ```bash
        /opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --print-rules
        ```

    ??? tip "Manually add extra management hosts/subnets"

        If you need to allow additional SSH sources not represented by your NIC-derived prefixes,
        edit `/etc/nftables.d/perfsonar.nft` and add entries to the appropriate sets. Example:

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

1. **Confirm nftables state and security services:**

    ??? info "Verification commands"

        ```bash
        nft list ruleset
        sestatus
        systemctl status fail2ban
        ```

        You may want to document any site-specific exceptions (e.g., additional allowed management hosts) in your change log.

---

## Step 5 – Deploy the Containerized perfSONAR Testpoint

Run the official testpoint image using Podman (or Docker). Choose one of the two deployment modes:

- Option A: Testpoint only (simplest) — only bind-mount `/opt/perfsonar-tp/psconfig` for pSConfig.
- Option B: Testpoint + Let’s Encrypt — two containers that share Apache files and certs via host bind mounts.

Use `podman-compose` (or `docker-compose`) in the examples below.

### Option A — Testpoint only (simplest)

Prepare the pSConfig directory and a minimal compose file. No other host bind-mounts are required.

```bash
mkdir -p /opt/perfsonar-tp/psconfig
```

Download a ready-made compose file (or copy it manually):  
Browse: [repo view](https://github.com/osg-htc/networking/blob/master/docs/perfsonar/tools_scripts/docker-compose.testpoint.yml)

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

Edit the `docker-compose.yml` as desired.


Bring it up:

```bash
(cd /opt/perfsonar-tp; podman-compose up -d) 
```

Verify the container is running and healthy:

```bash
podman ps
```

The container should show `healthy` status. The healthcheck monitors Apache HTTPS availability.

That's it for the testpoint-only mode. Manage pSConfig files under `/opt/perfsonar-tp/psconfig` on the host; they are consumed by the container at `/etc/perfsonar/psconfig`. Jump to Step 6 below.

---
### Option B — Testpoint + Let's Encrypt (shared Apache and certs)

This mode runs two containers (`perfsonar-testpoint` and `certbot`) and bind-mounts the following host paths so Apache content and certificates persist on the host and are shared between containers:

- `/opt/perfsonar-tp/psconfig` → `/etc/perfsonar/psconfig` — perfSONAR configuration
- `/var/www/html` → `/var/www/html` — Apache webroot (shared for HTTP-01 challenges)
- `/etc/apache2` → `/etc/apache2` — Apache configuration (for SSL certificate patching)
- `/etc/letsencrypt` → `/etc/letsencrypt` — Let's Encrypt certificates and state

#### 1) Seed required host directories (REQUIRED before first compose up)

**Why seed?** The perfsonar-testpoint container requires baseline configuration files from the image to be present on the host filesystem. Without seeding, the bind-mounted directories would be empty, causing Apache and perfSONAR services to fail.

**What's seeded:**
- `/opt/perfsonar-tp/psconfig` — perfSONAR pSConfig files (baseline remotes and archives)
- `/var/www/html` — Apache webroot with index.html (required for healthcheck)
- `/etc/apache2` — Apache config including `sites-available/default-ssl.conf` (patched by entrypoint wrapper)

**What's NOT seeded:**
- `/etc/letsencrypt` — Certbot creates this automatically; no pre-seeding needed

Run the bundled seeding helper script (automatically installed in Step 2):

```bash
/opt/perfsonar-tp/tools_scripts/seed_testpoint_host_dirs.sh
```

This script:
- Pulls the latest perfSONAR testpoint image
- Creates temporary containers to extract baseline files
- Copies content to host directories
- Verifies seeding was successful
- Skips seeding if directories already have content (idempotent)

Verify seeding succeeded:

```bash
# Should show config files
ls -la /opt/perfsonar-tp/psconfig

# Should show index.html and perfsonar/ directory  
ls -la /var/www/html

# Should show sites-available/, sites-enabled/, etc.
ls -la /etc/apache2
```

??? tip "SELinux labeling handled automatically"

    If SELinux is enforcing, the `:Z` and `:z` options in the compose files will cause Podman to
    relabel the host paths when containers start. No manual `chcon` commands are required.


#### 2) Deploy the testpoint with automatic SSL patching (recommended)

Deploy using the compose file with automatic Apache SSL certificate patching. This approach uses
an entrypoint wrapper that auto-discovers Let's Encrypt certificates on container startup and
automatically patches the Apache configuration.

Download the auto-patching compose file:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint-le-auto.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

**Note:** The `SERVER_FQDN` environment variable is **optional**. The entrypoint wrapper will
auto-discover certificates in `/etc/letsencrypt/live` and use the first one found. Only set
`SERVER_FQDN` if you have multiple certificates and need to specify which one to use.

If you want to explicitly set the FQDN (optional):

```bash
# Optional: only needed if you have multiple certificates
sed -i 's/# - SERVER_FQDN=.*/- SERVER_FQDN=<YOUR_FQDN>/' /opt/perfsonar-tp/docker-compose.yml
```

Start the containers:

```bash
cd /opt/perfsonar-tp
podman-compose up -d
```

At this point, the testpoint is running with self-signed certificates. The certbot container is also
running but won't renew anything until you obtain the initial certificates.

#### 3) Obtain your first Let's Encrypt certificate (one-time)

Use Certbot in standalone mode to obtain the initial certificates. The perfsonar-testpoint image is
patched to NOT listen on port 80, so port 80 is available for Certbot's HTTP-01 challenge.

**Important:** Stop the certbot sidecar temporarily to free port 80:

```bash
podman stop certbot
```

Now run Certbot standalone with host networking to bind port 80:

```bash
podman run --rm --net=host \
    -v /etc/letsencrypt:/etc/letsencrypt:Z \
    -v /var/www/html:/var/www/html:Z \
    docker.io/certbot/certbot:latest certonly \
    --standalone --agree-tos --non-interactive \
    -d <SERVER_FQDN> -d <ALT_FQDN> \
    -m <LETSENCRYPT_EMAIL>
```

Replace:
- `<SERVER_FQDN>` with your primary hostname (e.g., `psum05.aglt2.org`)
- `<ALT_FQDN>` with additional FQDNs if needed (one `-d` flag per FQDN)
- `<LETSENCRYPT_EMAIL>` with your email for certificate notifications

After successful issuance, restart the perfsonar-testpoint container to trigger the automatic patching:

```bash
podman restart perfsonar-testpoint
```

Check the logs to verify the SSL config was patched:

```bash
podman logs perfsonar-testpoint 2>&1 | grep -A5 "Patching Apache"
```

You should see output confirming the certificate paths were updated.

#### 4) Restart the certbot sidecar for automatic renewals

Now that certificates are in place, restart the certbot sidecar to enable automatic renewals:

```bash
podman start certbot
```

The certbot container runs a renewal loop that checks for expiring certificates every 12 hours.

**Note:** The certbot container in this setup uses **host networking mode** (via `network_mode: host` in the
compose file) so it can bind directly to port 80 for HTTP-01 challenges during renewals. This works
because the perfsonar-testpoint Apache is patched to NOT listen on port 80. Both containers share
the host network namespace without conflict.

Test renewal with a dry-run:

```bash
podman exec certbot certbot renew --dry-run
```

If successful, certificates will auto-renew before expiry. After each renewal, restart the testpoint
to reload the certificates:

```bash
# Optional: add a systemd timer or cron job to restart testpoint after renewals
podman restart perfsonar-testpoint
```

---

??? info "Alternative: Manual SSL Patching (without automatic entrypoint wrapper)"

    If you prefer not to use the automatic patching entrypoint wrapper, you can use the standard
    compose file and manually patch the Apache SSL configuration after obtaining certificates.

    1. Use `docker-compose.testpoint-le.yml` instead of `docker-compose.testpoint-le-auto.yml`
    2. After obtaining Let's Encrypt certificates, run:

    ```bash
    /opt/perfsonar-tp/tools_scripts/patch_apache_ssl_for_letsencrypt.sh <SERVER_FQDN>
    ```

    3. Reload Apache in the running container:

    ```bash
    podman exec perfsonar-testpoint apachectl -k graceful
    ```

    This approach requires manual intervention after initial certificate issuance and any time
    the container is recreated. The automatic approach (using the entrypoint wrapper) eliminates
    this manual step.


---
## Step 6 – Register and Configure with WLCG/OSG

We need to register your instance and ensure it is configured with the required meta data for the
lsregistration daemon (see below).

1. **OSG/WLCG registration workflow:**

    ??? info "Registration steps and portals"

        - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
        - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
            - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint
                `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

1. **pSConfig enrollment:**

    Register this host with the OSG/WLCG pSConfig service so tests are auto-configured. Use the "auto URL" for each FQDN you expose for perfSONAR (one or two depending on whether you split latency/throughput by hostname).

    Basic enroll (interactive root on the host; runs inside the container) if you have only one entry to make (automation alternative below):

    ```bash
    # Add auto URLs (configures archives too) and show configured remotes
    podman exec -it perfsonar-testpoint psconfig remote --configure-archives add \
        "https://psconfig.opensciencegrid.org/pub/auto/ps-lat-example.my.edu"

    podman exec -it perfsonar-testpoint psconfig remote list
    ```

    If there are any stale/old/incorrect entries, you can remove them:

    ```bash
    podman exec -it perfsonar-testpoint psconfig remote delete "<old-url>"
    ```

    Automation tip: derive FQDNs from your configured IPs (PTR lookup) and enroll automatically. Review the list before applying.

    ```bash
    # Dry run only (show planned URLs):
    /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -n

    # Typical usage (podman):
    /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -v

    podman exec -it perfsonar-testpoint psconfig remote list
    ```

    ??? note "The auto enroll script details"

        - Parses IP lists from `/etc/perfSONAR-multi-nic-config.conf`  (`NIC_IPV4_ADDRS` / `NIC_IPV6_ADDRS`).
        - Performs reverse DNS lookups (getent/dig) to derive FQDNs.
        - Deduplicates while preserving discovery order.
        - Adds each `https://psconfig.opensciencegrid.org/pub/auto/<FQDN>` with `--configure-archives`.
        - Lists configured remotes and returns non-zero if any enrollment fails.

    Integrate into provisioning CI by running with `-n` (dry-run) for approval and then `-y` once approved.

1. **Document memberships:** update your site wiki or change log with assigned mesh names, feed  URLs, and support contacts.

1. **Update Lookup Service registration inside the container**

    Use the helper script to edit `/etc/perfsonar/lsregistrationdaemon.conf` inside the running `perfsonar-testpoint` container and restart the daemon only if needed.

    Install and run examples below, pick which type you want (root shell):

    ```bash
    # Preview changes only (uses the copy from /opt/perfsonar-tp/tools_scripts)
    /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh \
        --dry-run --site-name "Acme Co." --project WLCG \
        --admin-email admin@example.org --admin-name "pS Admin"

    # Restore previously saved settings from the Prerequisites extract (if you saved a restore script earlier)
    bash /root/restore-lsreg.sh

    # Apply new settings and restart the daemon inside the container
    /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh \
        --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
        --city Berkeley --region CA --country US --zip 94720 \
        --latitude 37.5 --longitude -121.7469 \
        --admin-name "pS Admin" --admin-email admin@example.org
    ```

1. **Automatic image updates and safe restarts**

    Keep containers current and only restart them when their image actually changes.

    ??? info "Auto-update via labels and a systemd timer"

        1. Add an auto-update label to services in your compose file (both `testpoint` and `certbot` if used).  If you copied the example docker-compose.yml from the repo, this is already done:

            ```yaml
            services:
                testpoint:
                    # ...
                    labels:

                        - io.containers.autoupdate=registry

                certbot:
                    # ...
                    labels:

                        - io.containers.autoupdate=registry

            ```

            The lable instructs Podman to check the registry for newer images and restart only if an update is pulled but we need to turn on the auto-update timer:

        1. Enable the Podman auto-update timer (runs daily by default):

            ```bash
            systemctl enable --now podman-auto-update.timer
            ```

        1. Run ad-hoc when desired and preview:

            ```bash
            podman auto-update --dry-run
            podman auto-update
            ```

        1. Inspect recent runs:

            ```bash
            systemctl list-timers | grep podman-auto-update
            journalctl -u podman-auto-update --since "1 day ago"
            ```

---
## Step 7 – Post-Install Validation

Perform these checks before handing the host over to operations:

1. **System services:**

    ??? info "Verify Podman and compose services"

        ```bash
        systemctl status podman
        systemctl --user status podman-compose@perfsonar-testpoint.service
        ```

    Ensure both are active/green.

1. **Container health:**

    ??? info "Check container status and logs"

        ```bash
        podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        podman logs pscheduler-agent | tail
        ```

1. **Network path validation:**

    ??? info "Test network connectivity and routing"

        ```bash
        pscheduler task throughput --dest <remote-testpoint>
        tracepath -n <remote-testpoint>
        ```

    Confirm traffic uses the intended policy-based routes (check `ip route get <dest>`).

1. **Security posture:**

    ??? info "Check firewall, fail2ban, and SELinux"

        ```bash
        nft list ruleset | grep perfsonar
        fail2ban-client status
        ausearch --message AVC --just-one
        ```

    Investigate any SELinux denials or repeated Fail2Ban bans.

1. **LetsEncrypt certificate check:**

    ??? info "Verify certificate validity"

        ```bash
        openssl s_client -connect <SERVER_FQDN>:443 -servername <SERVER_FQDN> | openssl x509 -noout -dates -issuer
        ```

    Ensure the issuer is Let’s Encrypt and the validity period is acceptable.

1. **Reporting:**

    ??? info "Run perfSONAR diagnostic reports"
        Run the perfSONAR toolkit daily report and send outputs to operations:

        ```bash
        pscheduler troubleshoot
        ```

---

## Ongoing Maintenance

- Schedule quarterly re-validation of routing policy and nftables rules.
- Apply `dnf update` monthly and reboot during the next maintenance window.
- Monitor psconfig feeds for changes in mesh participation.
- Track certificate expiry (`certbot renew --dry-run`) if you rely on Let’s Encrypt.




