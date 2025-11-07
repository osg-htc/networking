# Installing a perfSONAR Testpoint for WLCG/OSG

This guide walks WLCG/OSG site administrators through end-to-end installation, configuration, and validation of a perfSONAR testpoint on Enterprise Linux 9 (EL9). It uses automated tooling from this repository to streamline the process while accommodating site-specific requirements.

---

## Prerequisites and Planning

Before you begin, gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage.
- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN
  information, PSConfig registration URLs.
- **Operational contacts:** site admin email, OSG facility name, latitude/longitude.
- **Repository artifacts:** Scripts and configurations from the [perfsonar/testpoint](https://github.com/perfsonar/testpoint) repository, installed to `/opt/perfsonar-tp/tools_scripts`.

- **Existing perfSONAR configuration:** If replacing an existing instance, back up `/etc/perfsonar/` files, especially `lsregistrationdaemon.conf`, and any container volumes. Use `perfSONAR-update-lsregistration.sh` to extract registration config.


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

---

1. **Apply baseline updates and verify dependencies:**

    Use the helper to check for required tools and apply OS updates.

    ```bash
    /opt/perfsonar-tp/tools_scripts/check-deps.sh
    ```

??? tip "Alternative: check-deps.sh one-off run without installing tools"

        ```bash
        # Preferred: run from the installed tools path (see Step 2):
        /opt/perfsonar-tp/tools_scripts/check-deps.sh

        # If you must run it without installing the tools, download to /tmp and run
        curl -fsSL \
            https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-deps.sh \
            -o /tmp/check-deps.sh
        chmod 0755 /tmp/check-deps.sh
        /tmp/check-deps.sh
        ```

## Step 3 – Configure Policy-Based Routing (PBR)

The script `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh` automates NetworkManager profiles and routing rule setup.

1. **Preview generation (no changes):**

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-debug
    ```

1. **Generate config file automatically:**

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto
    ```

    Write the config file to `/etc/perfSONAR-multi-nic-config.conf`. Open and adjust site-specific values (e.g., confirm `DEFAULT_ROUTE_NIC`, add `NIC_IPV4_ADDROUTE` entries).

!!! warning "Gateways required for addresses"
    Any NIC with an IPv4 address must also have an IPv4 gateway, and any NIC with an IPv6 address
    must have an IPv6 gateway. If the generator cannot detect a gateway, it adds a WARNING block
    to the generated file listing affected NICs. Edit `NIC_IPV4_GWS`/`NIC_IPV6_GWS` accordingly
    before applying changes.

!!! note "Gateway prompts"

    During generation, the script attempts to detect gateways per-NIC. If a NIC has an IP address
    but no gateway could be determined, it will prompt you interactively to enter an IPv4 and/or
    IPv6 gateway (or `-` to skip). Prompts are skipped in non-interactive sessions or when you
    use `--yes`.

1. **Apply changes:**

    Dry-run first:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --dry-run --debug
    ```

    Apply non-interactively:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes
    ```

    The script backs up NetworkManager profiles, seeds routing tables, and applies rules. Review `/var/log/perfSONAR-multi-nic-config.log` and retain it. Reboot if needed.

### DNS: forward and reverse entries (required)

All IP addresses that will be used for perfSONAR testing MUST have DNS entries: a forward (A/AAAA)
record and a matching reverse (PTR) record. This is required so remote test tools and site operators
can reliably reach and identify your host, and because some measurement infrastructure and
registration systems perform forward/reverse consistency checks.

- For single-stack IPv4-only hosts: ensure A and PTR are present and consistent.
- For single-stack IPv6-only hosts: ensure AAAA and PTR are present and consistent.
- For dual-stack hosts: both IPv4 and IPv6 addresses used for testing must have matching forward and
  reverse records (A+PTR and AAAA+PTR).

??? example "Run the DNS checker"
    Validate forward/reverse DNS for addresses in `/etc/perfSONAR-multi-nic-config.conf`.

    ```bash
    /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh
    ```

    Or download temporarily:

    ```bash
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-perfsonar-dns.sh \
        -o /tmp/check-dns.sh
    chmod 0755 /tmp/check-dns.sh
    /tmp/check-dns.sh
    ```

    **Notes and automation tips:**

    - The script above uses `dig` (bind-utils package) which is commonly available; you can adapt it
      to use `host` if preferred.
    - Run the check as part of your provisioning CI or as a pre-flight check before enabling measurement registration.
    - For large sites or many addresses, parallelize the checks (xargs -P) or use a small Python
      script that leverages `dns.resolver` for async checks.
    - If your PTR returns a hostname with a trailing dot, the script strips it before the forward check.

If any addresses fail these checks, correct the DNS zone (forward and/or reverse) and allow DNS
propagation before proceeding with registration and testing.

<!-- Consolidated DNS checker instructions into a single admonition above -->

1. **Verify the routing policy:**

   ```bash
   nmcli connection show
   ip rule show
   ip route show table <table-id>
   ```

Confirm that non-default interfaces have their own routing tables and that the default interface
owns the system default route.

---

## Step 4 – Configure nftables, SELinux, and Fail2Ban

Use `/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh` to configure a hardened nftables profile with optional SELinux and Fail2Ban support. No staging or copy step is required.

Script location in the repository:

- [Directory (browse)](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts)
- [Raw file (direct download)](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh)

Prerequisites (not installed by the script):

- `nftables` must already be installed and available (`nft` binary) for firewall configuration.
- `fail2ban` must be installed if you want the optional jail configuration.
- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

1. **Run with desired options:**

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes
    ```

    - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the
      summary and answer manually).
    - Add `--dry-run` for a rehearsal that only prints the planned actions.

    The script writes nftables rules for perfSONAR services, derives SSH allow-lists from
    `/etc/perfSONAR-multi-nic-config.conf`, optionally adjusts SELinux, and enables Fail2Ban
    jails—only if those components are already installed.

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

    1. **Confirm firewall state and security services:**

??? info "Verification commands"

    ```bash
    nft list ruleset
    sestatus
    systemctl status fail2ban
    ```

    Document any site-specific exceptions (e.g., additional allowed management hosts) in your change log.

    ---

## Step 5 – Deploy the Containerized perfSONAR Testpoint

Run the official testpoint image using Podman or Docker. Bind-mount host paths for persistence.

Key host paths:

- `/opt/perfsonar-tp/psconfig` → container `/etc/perfsonar/psconfig`
- For Let's Encrypt: `/etc/apache2`, `/var/www/html`, `/etc/letsencrypt`

Use `podman-compose` or `docker-compose`.

### Prepare directories on the host

```bash
mkdir -p /opt/perfsonar-tp/psconfig
#  The directories below are if we also use Lets Encrypt
mkdir -p /var/www/html
mkdir -p /etc/apache2
mkdir -p /etc/letsencrypt
```

### Seed defaults from the testpoint container

First, create a minimal compose file and start the container without host bind-mounts so we can copy
baseline content out.

```yaml
version: "3.9"
services:
    testpoint:
        container_name: perfsonar-testpoint
        image: ghcr.io/perfsonar/testpoint:5.2.4-systemd
        network_mode: "host"
        cgroup: host
        environment:

            - TZ=UTC

        restart: unless-stopped
        tmpfs:

            - /run
            - /run/lock
            - /tmp

        volumes:

            - /sys/fs/cgroup:/sys/fs/cgroup:rw

        tty: true
        pids_limit: 8192
        cap_add:

            - CAP_NET_RAW

```

Bring it up with your preferred tool:

```bash
(cd /opt/perfsonar-tp; podman-compose up -d)  # or: (cd /opt/perfsonar-tp; docker-compose up -d)
```

### Copy baseline content out of the running container

```bash
# Use docker cp or podman cp (either works)
docker cp perfsonar-testpoint:/etc/perfsonar/psconfig /opt/perfsonar-tp/psconfig
# Below are if also using Lets Encrypt
docker cp perfsonar-testpoint:/etc/apache2 /etc/apache2
docker cp perfsonar-testpoint:/var/www/html /var/www/html

```

If SELinux is enforcing, we’ll relabel these paths when we mount (using `:z`/`:Z` below), so you
don’t need manual `chcon`.

### Replace the compose file with bind-mounts and optional certbot

You can download a ready-to-use compose file from this repository, or create it manually.

- [Browse](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts/docker-compose.yml)
- Download directly:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

Or create/edit `/opt/perfsonar-tp/docker-compose.yml` with the following content (includes an
optional `certbot` sidecar):

```yaml
version: "3.9"
services:
    testpoint:
        container_name: perfsonar-testpoint
        image: ghcr.io/perfsonar/testpoint:5.2.4-systemd
        network_mode: "host"
        cgroup: host
        environment:

            - TZ=UTC

        restart: unless-stopped
        tmpfs:

            - /run
            - /run/lock
            - /tmp

        volumes:

            - /sys/fs/cgroup:/sys/fs/cgroup:rw
            - /opt/perfsonar-tp/psconfig:/etc/perfsonar/psconfig:Z
            - /var/www/html:/var/www/html:z
            - /etc/apache2:/etc/apache2:z
            - /etc/letsencrypt:/etc/letsencrypt:z

        tty: true
        pids_limit: 8192
        cap_add:

            - CAP_NET_RAW

    # Optional: Let’s Encrypt renewer sharing HTML and certs with testpoint
    certbot:
        image: certbot/certbot
        container_name: certbot
        network_mode: "host"
        restart: unless-stopped
        entrypoint:
            ["/bin/sh","-c","trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;"]
        depends_on:

            - testpoint

        volumes:

            - /var/www/html:/var/www/html:z
            - /etc/letsencrypt:/etc/letsencrypt:z

```

### Restart with the new compose

```bash
(cd /opt/perfsonar-tp; podman-compose down)
(cd /opt/perfsonar-tp; podman-compose up -d)  # or docker-compose down && docker-compose up -d
```

### Optional – obtain your first Let’s Encrypt certificate

The `certbot` sidecar above continuously renews existing certs. For the initial issuance, run a one-
shot command and then reload Apache inside the testpoint container:

```bash
# Issue (HTTP-01 webroot challenge). Replace values accordingly.
docker run --rm --net=host -v /var/www/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt \
    certbot/certbot certonly --webroot -w /var/www/html -d <SERVER_FQDN> \
    --email <LETSENCRYPT_EMAIL> --agree-tos --no-eff-email

# Gracefully reload Apache within the testpoint container (or restart the service)
docker exec -it perfsonar-testpoint bash -lc 'systemctl reload httpd || apachectl -k graceful || true'
```

??? info "Notes"

    - Ensure port 80 on the host is reachable from the internet while issuing certificates.
    - All shared paths use SELinux-aware `:z`/`:Z` to permit container access on enforcing hosts.


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

For each active NIC, register with the psconfig service so measurements cover all paths.

Confirm the resulting files in `/etc/perfsonar/psconfig/pscheduler.d/` map to the correct interface
addresses (`ifaddr` tags).

1. **Document memberships:** update your site wiki or change log with assigned mesh names, feed
   URLs, and support contacts.

### Update Lookup Service registration inside the container

Use the helper script to edit `/etc/perfsonar/lsregistrationdaemon.conf` inside the running
`perfsonar-testpoint` container and restart the daemon only if needed.

Install and run examples (root shell):

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
    toolkit-system-health
    ```

    ---

## Ongoing Maintenance

- Schedule quarterly re-validation of routing policy and nftables rules.
- Apply `dnf update` monthly and reboot during the next maintenance window.
- Monitor psconfig feeds for changes in mesh participation.
- Track certificate expiry (`certbot renew --dry-run`) if you rely on Let’s Encrypt.

### Automatic image updates and safe restarts

Keep containers current and only restart them when their image actually changes.

??? info "Auto-update via labels and a systemd timer"

    1. Add an auto-update label to services in your compose file (both `testpoint` and `certbot` if used):

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

        This instructs Podman to check the registry for newer images and restart only if an update is pulled.

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


