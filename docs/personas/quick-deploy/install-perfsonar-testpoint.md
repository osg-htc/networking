# Installing a perfSONAR Testpoint for WLCG/OSG

This quick-deploy playbook walks WLCG/OSG site administrators through the end-to-end installation, configuration, and validation of a perfSONAR testpoint on Enterprise Linux 9 (EL9). Each phase references tooling that already lives in this repository so you can automate as much as possible while still capturing the site-specific information required by OSG/WLCG operations.

---

## Prerequisites and Planning

Before you begin, gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage.
- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN information, PSConfig registration URLs.
- **Operational contacts:** site admin email, OSG facility name, latitude/longitude, usage policy link.
- **Repository artifacts:** the scripts referenced below are in `docs/perfsonar/` in this repository.

- **Existing perfSONAR configuration:** If you are replacing or upgrading an existing perfSONAR instance, capture its configuration and registration data before taking services offline. Useful items to collect include:

    - `/etc/perfsonar/` configuration files, especially `lsregistrationdaemon.conf`
    - any site-specific psconfig or testpoint config files stored in container volumes or host paths
    - exported firewall, monitoring, and cron jobs that the current instance relies on

   The repository includes a helper script `docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh` which can copy and update `lsregistrationdaemon.conf` from running containers or the host; it can be used to extract registration config for re-use or migration. If you need to re-register or migrate metadata, run that script (or copy the `lsregistrationdaemon.conf` manually) and keep a copy in your change log.

??? info "Quick capture of existing lsregistration config (if replacing)"

    You can capture your current Lookup Service registration before redeploying.

    - Download the helper temporarily and extract a self-contained restore script (works even if you haven't done Step 2 yet):

        ```bash
        curl -fsSL \
            https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh \
            -o /tmp/perfSONAR-update-lsregistration.sh
        chmod 0755 /tmp/perfSONAR-update-lsregistration.sh
        sudo /tmp/perfSONAR-update-lsregistration.sh extract --output /root/restore-lsreg.sh
        # Save /root/restore-lsreg.sh with your change notes
        ```


   Note: the full repository clone/checkout instructions have been moved to Step 2 (after Step 1) so you can perform the clone once the host is provisioned.

> **Note:** All shell commands assume an interactive root shell. Prefix with `sudo` when running as a non-root user.

---

## Step 1 – Install and Harden EL9

1. **Provision EL9:** Install AlmaLinux, Rocky Linux, or RHEL 9 with the *Minimal* profile.


3. **Set the hostname and time sync:**

    Note when you have multiple NICs pick one to be the hostname. That should also be the NIC that hosts the default route (See step 2 below).

??? info "System configuration commands"

    ```bash
    hostnamectl set-hostname <testpoint-hostname>
    systemctl enable --now chronyd
    timedatectl set-timezone <Region/City>
    ```

4. **Disable unused services:**

??? info "Service cleanup commands"

    ```bash
    systemctl disable --now firewalld NetworkManager-wait-online
    dnf remove -y rsyslog
    ```

5. **Record NIC names:**

??? info "Commands to list network interfaces"

    ```bash
    nmcli device status
    ip -br addr
    ```

    Document interface mappings; you will need them for the policy-based routing configuration.

---

## Step 2 – Clone the Repository

This guide references multiple scripts from the osg-htc/networking repository. Clone the repository to your testpoint host for easy access to all tools.

**Recommended locations:**

- **perfSONAR testpoint compose bundle:** `/opt/perfsonar-tp` (if using containerized testpoint)

First check out the perfSONAR testpoint:

```bash
git clone https://github.com/perfsonar/testpoint.git /opt/perfsonar-tp
```

We will then check out just the tools_scripts directory from THIS repo, to give us access to the appropriate scripts and tools.

Create only the perfSONAR tools directory from this repository using a sparse checkout, and place it under `/opt/perfsonar-tp/tools_scripts`:

```bash
# Create destination directory
mkdir -p /opt/perfsonar-tp/tools_scripts

# Use a temporary sparse checkout to fetch only docs/perfsonar/tools_scripts
tmpdir=$(mktemp -d)
git clone --depth=1 --filter=blob:none --sparse \
    https://github.com/osg-htc/networking.git "$tmpdir/networking"

cd "$tmpdir/networking"
git sparse-checkout set docs/perfsonar/tools_scripts

# Copy the tools into /opt/perfsonar-tp/tools_scripts
rsync -a docs/perfsonar/tools_scripts/ /opt/perfsonar-tp/tools_scripts/

# Optional: list what was installed
ls -1 /opt/perfsonar-tp/tools_scripts

# Cleanup
cd /
rm -rf "$tmpdir"
```

Notes:
- The source path in this repo is `docs/perfsonar/tools_scripts` (plural). We install it to `/opt/perfsonar-tp/tools_scripts` to keep the same name.
- You don’t need to keep a full clone of the networking repo on the host for these tools; the sparse checkout above fetches only the needed directory.

After preparing the host, assume scripts from this guide are available at `/opt/perfsonar-tp/tools_scripts` and run them from there unless a raw download is shown.

> **Note:** All shell commands assume an interactive root shell. Prefix with `sudo` when running as a non-root user.

---
2. **Apply baseline updates (and verify dependencies):**

    Use the repository's helper to check for required tools and print
    copy/paste install commands. Then apply OS updates and any remaining
    baseline packages.

    - You can run check-deps.sh from the local copy:

        ```bash
        /opt/perfsonar-tp/tools_scripts/check-deps.sh
        ```

??? tip "Alternative: Download and run directly"

    ```bash
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-deps.sh \
        -o ./check-deps.sh
    chmod 0755 ./check-deps.sh
    ./check-deps.sh
    ```

## Step 3 – Configure Policy-Based Routing (PBR)

The repository ships an enhanced script `docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh` that automates NetworkManager configuration and routing rules and can auto-generate its config file. After Step 2, the local path for this script is `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh`.


1. **Run the PBR helper:** (already available from Step 2 in `/opt/perfsonar-tp/tools_scripts`)

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --help
    ```

1. **Auto-generate `/etc/perfSONAR-multi-nic-config.conf`:**

    Use the generator to detect NICs, addresses, prefixes, and gateways and write a starting config you can review/edit. Auto-generation is opt-in; it does not run by default.

    - Write the config file to `/etc/perfSONAR-multi-nic-config.conf`:

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto
    ```

    Then open the file and adjust any site-specific values (e.g., confirm `DEFAULT_ROUTE_NIC`, add any `NIC_IPV4_ADDROUTE` entries, or replace “-” for unused IP/gateway fields).

!!! warning "Gateways required for addresses"
    Any NIC with an IPv4 address must also have an IPv4 gateway, and any NIC with an IPv6 address must have an IPv6 gateway. If the generator cannot detect a gateway, it adds a WARNING block to the generated file listing affected NICs. Edit `NIC_IPV4_GWS`/`NIC_IPV6_GWS` accordingly before applying changes.

!!! note "Gateway prompts"

    During generation, the script attempts to detect gateways per-NIC. If a NIC has an IP address but no gateway could be determined, it will prompt you interactively to enter an IPv4 and/or IPv6 gateway (or `-` to skip). Prompts are skipped in non-interactive sessions or when you use `--yes`.

1. **Execute the script:**

   It is likely you will get disconnected if you are logged in via 'ssh'.  It is strongly recommended to run the script directly on the console or perhaps use 'nohup' in front of the command so that it will not drop the shell.  You can also use the --dry-run option to see what it will do without making changes.

    - Apply changes non-interactively (auto-confirm):

    ```bash
    /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes
    ```

!!! note "Missing gateways at apply time"

    If the loaded config still contains `-` for a gateway on a NIC that has an IP address, the script will prompt you interactively to provide a gateway before applying changes. Use `--yes` (or run non-interactively) to suppress prompts; in that case, missing gateways will cause validation to fail so you can correct the config first.

    The script creates a timestamped backup of existing NetworkManager profiles, seeds routing tables, and applies routing rules. Review `/var/log/perfSONAR-multi-nic-config.log` after the run and retain it with your change records.

    On some hosts, we have had to reboot or power-cycle to get the new network settings in place.

### DNS: forward and reverse entries (required)

All IP addresses that will be used for perfSONAR testing MUST have DNS entries: a forward (A/AAAA) record and a matching reverse (PTR) record. This is required so remote test tools and site operators can reliably reach and identify your host, and because some measurement infrastructure and registration systems perform forward/reverse consistency checks.

- For single-stack IPv4-only hosts: ensure A and PTR are present and consistent.
- For single-stack IPv6-only hosts: ensure AAAA and PTR are present and consistent.
- For dual-stack hosts: both IPv4 and IPv6 addresses used for testing must have matching forward and reverse records (A+PTR and AAAA+PTR).

??? example "Run the DNS checker"
    Run the shipped DNS checker to validate forward/reverse DNS for addresses in `/etc/perfSONAR-multi-nic-config.conf`.

    ```bash
    # Preferred: use the local tools checkout from Step 2
    sudo /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh

    # Alternative: download and run directly
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-perfsonar-dns.sh \
        -o ./check-perfsonar-dns.sh
    chmod 0755 ./check-perfsonar-dns.sh
    sudo ./check-perfsonar-dns.sh
    ```

    **Notes and automation tips:**

    - The script above uses `dig` (bind-utils package) which is commonly available; you can adapt it to use `host` if preferred.
    - Run the check as part of your provisioning CI or as a pre-flight check before enabling measurement registration.
    - For large sites or many addresses, parallelize the checks (xargs -P) or use a small Python script that leverages `dns.resolver` for async checks.
    - If your PTR returns a hostname with a trailing dot, the script strips it before the forward check.

If any addresses fail these checks, correct the DNS zone (forward and/or reverse) and allow DNS propagation before proceeding with registration and testing.

<!-- Consolidated DNS checker instructions into a single admonition above -->

1. **Verify the routing policy:**

   ```bash
   nmcli connection show
   ip rule show
   ip route show table <table-id>
   ```

   Confirm that non-default interfaces have their own routing tables and that the default interface owns the system default route.

---

## Step 4 – Configure nftables, SELinux, and Fail2Ban

Use `/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh` to configure a
hardened nftables profile with optional SELinux and Fail2Ban support.

Prerequisites (not installed by the script):

- `nftables` must already be installed and available (`nft` binary) for firewall configuration.
- `fail2ban` must be installed if you want the optional jail configuration.
- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

1. **Use the help script:**

    1. **Run with desired options:**

    ```bash
    ~/perfsonar-install-nftables.sh --selinux --fail2ban --yes
    ```

    - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the summary and answer manually).
    - Add `--dry-run` for a rehearsal that only prints the planned actions.

    The script writes nftables rules for perfSONAR services, derives SSH allow-lists from
    `/etc/perfSONAR-multi-nic-config.conf`, optionally adjusts SELinux, and enables Fail2Ban
    jails—only if those components are already installed.

??? info "How SSH allow-lists and validation work"
**SSH allow-list derivation:**

- CIDR values in `NIC_IPV4_PREFIXES`/`NIC_IPV6_PREFIXES` paired with corresponding addresses are treated as subnets.
- Address entries without a prefix are treated as single hosts.
- The script logs the resolved lists (IPv4/IPv6 subnets and hosts) for review.

**Validation and output:**

- The generated nftables file is validated with `nft -c -f` before being written; on validation failure, nothing is installed and a message is logged.
- Output locations: rules → `/etc/nftables.d/perfsonar.nft`, log → `/var/log/perfSONAR-install-nftables.log`, backups → `/var/backups/perfsonar-install-<timestamp>`.

??? tip "Preview nftables rules before applying"
    You can preview the fully rendered nftables rules (no changes are made):

    ```bash
    ~/perfsonar-install-nftables.sh --print-rules
    ```

??? tip "Manually add extra management hosts/subnets"
If you need to allow additional SSH sources not represented by your NIC-derived prefixes, edit `/etc/nftables.d/perfsonar.nft` and add entries to the appropriate sets:

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

We’ll run the official testpoint image from the GitHub Container Registry using Podman, but we’ll show Docker-style commands so you can choose either tool. We’ll bind-mount host paths so edits on the host are reflected inside the containers.

Key paths to persist on the host will depend upon your deployment use-case.  For a simple perfSONAR testpoint deployment only, we only need to persist the /etc/perfsonar/psconfig area of the container.   If Lets Encrypt will be used, we also need to ensure visibility of certain locations between the containers and we do that be using the host filesystem.  However, this requires "seeding" those host directories initial as is covered below.

- `/opt/perfsonar-tp/psconfig` → container `/etc/perfsonar/psconfig`
- `/etc/apache2` → container `/etc/apache2` (Apache configs)
- `/var/www/html` → container `/var/www/html` (webroot for Toolkit and ACME challenges)
- `/etc/letsencrypt` → container `/etc/letsencrypt` (certs/keys, if using Let’s Encrypt)


Tip: you can use either `podman-compose` or `docker-compose` in the steps below. Substitute the command that matches your preference.

### Prepare directories on the host

```bash
mkdir -p /opt/perfsonar-tp/psconfig
#  The directories below are if we also use Lets Encrypt
mkdir -p /var/www/html
mkdir -p /etc/apache2
mkdir -p /etc/letsencrypt
```

### Seed defaults from the testpoint container

First, create a minimal compose file and start the container without host bind-mounts so we can copy baseline content out.

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
docker cp perfsonar-testpoint:/etc/apache2 /etc/apache2
docker cp perfsonar-testpoint:/var/www/html /var/www/html
docker cp perfsonar-testpoint:/etc/perfsonar/psconfig /opt/perfsonar-tp/psconfig
```

If SELinux is enforcing, we’ll relabel these paths when we mount (using `:z`/`:Z` below), so you don’t need manual `chcon`.

### Replace the compose file with bind-mounts and optional certbot

You can download a ready-to-use compose file from this repository, or create it manually.

- [Browse](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts/docker-compose.yml)
- Download directly:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

Or create/edit `/opt/perfsonar-tp/docker-compose.yml` with the following content (includes an optional `certbot` sidecar):

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

The `certbot` sidecar above continuously renews existing certs. For the initial issuance, run a one-shot command and then reload Apache inside the testpoint container:

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

We need to register your instance and ensure it is configurated with the required meta data for the lsregistration daemon (see below).

1. **OSG/WLCG registration workflow:**

??? info "Registration steps and portals"
    - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
    - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
    - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

1. **pSConfig enrollment:**

   For each active NIC, register with the psconfig service so measurements cover all paths.

??? info "Registration command and verification"
Example registration:

```bash
/usr/bin/psconfig psconfig remote --configure-archives add --url https://psconfig.opensciencegrid.org/pub/auto/<NIC-FQDN>
```

Confirm the resulting files in `/etc/perfsonar/psconfig/pscheduler.d/` map to the correct interface addresses (`ifaddr` tags).

1. **Document memberships:** update your site wiki or change log with assigned mesh names, feed URLs, and support contacts.

### Update Lookup Service registration inside the container

Use the helper script to edit `/etc/perfsonar/lsregistrationdaemon.conf` inside the
running `perfsonar-testpoint` container and restart the daemon only if needed.

- Script (browse): [perfSONAR-update-lsregistration.sh](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh)
- Raw (download): [raw link](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh)

Install and run examples (root shell):

Note: the helper uses subcommands; use the `update` command to apply field changes.
Other available commands: `save`, `restore`, `create`, `extract`.

From the local tools checkout (preferred):

```bash
# Preview changes only
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh update \
    --dry-run \
    --site-name "Acme Co." --project WLCG \
    --admin-email admin@example.org --admin-name "pS Admin"

# Apply common updates and restart the daemon inside the container
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh update \
    --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
    --city Berkeley --region CA --country US --zip 94720 \
    --latitude 37.5 --longitude -121.7469 \
    --admin-name "pS Admin" --admin-email admin@example.org

# Produce a self-contained restore script for host restore
sudo /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh extract \
    --output /tmp/restore-lsreg.sh
sudo /tmp/restore-lsreg.sh
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


