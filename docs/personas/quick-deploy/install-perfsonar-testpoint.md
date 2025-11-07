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

    ## Step 6 – Register and configure with WLCG/OSG (quick)

    Register the host with OSG/WLCG and ensure pSConfig enrollment so the testpoint receives automated
    measurement feeds. Below are the essential commands and a short helper usage section.

    1) Register a single FQDN (interactive; runs inside the container):

    ```bash
    # Add an auto URL for one FQDN (replace with your FQDN)
    podman exec -it perfsonar-testpoint psconfig remote --configure-archives add \
      "https://psconfig.opensciencegrid.org/pub/auto/your.host.example"

    # Confirm configured remotes
    podman exec -it perfsonar-testpoint psconfig remote list
    ```

    2) Quick automated enrollment (recommended helper)

    The repository provides a helper that discovers public FQDNs (reverse DNS), de-duplicates them,
    and performs enrollment. Typical quick commands:

    ```bash
    # Show what would be done (dry-run)
    /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -n -v -f /etc/perfSONAR-multi-nic-config.conf

    # Perform non-interactive enrollment (CI-safe)
    sudo /opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -y -f /etc/perfSONAR-multi-nic-config.conf
    ```

    Notes:
    - The helper skips RFC1918 (private) IPv4 addresses and only derives FQDNs from public IPs.
    - Discovered FQDNs are logged to `/var/log/perfsonar-auto-enroll-psconfig.log` (falls back to `/tmp/`).
    - Use `-n` to review URLs before applying; use `-v` for debug output.

    3) Verify

    After enrollment, verify the container psconfig files and remotes:

    ```bash
    podman exec -it perfsonar-testpoint psconfig remote list
    podman exec -it perfsonar-testpoint ls -l /etc/perfsonar/psconfig/pscheduler.d/
    ```

    If you need to edit/restore `lsregistrationdaemon.conf`, use the updater helper under `/opt/perfsonar-tp/tools_scripts` (see Step 6 examples in the helper README).
    Apply non-interactively with `--yes` or interactively without:

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

Run the official testpoint image using Podman or Docker. Choose one of the two deployment modes:

- Option A: Testpoint only (simplest) — only bind-mount `/opt/perfsonar-tp/psconfig` for pSConfig.
- Option B: Testpoint + Let’s Encrypt — two containers that share Apache files and certs via
    host bind mounts.

Use `podman-compose` or `docker-compose` in the examples below.

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

Or create `/opt/perfsonar-tp/docker-compose.yml` with:

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
        tty: true
        pids_limit: 8192
        cap_add:
            - CAP_NET_RAW
```

Bring it up:

```bash
(cd /opt/perfsonar-tp; podman-compose up -d)  # or: (cd /opt/perfsonar-tp; docker-compose up -d)
```

That’s it for the testpoint-only mode. Manage pSConfig files under `/opt/perfsonar-tp/psconfig` on
the host; they are consumed by the container at `/etc/perfsonar/psconfig`.

---

### Option B — Testpoint + Let’s Encrypt (shared Apache and certs)

This mode runs two containers (`testpoint` and `certbot`) and bind-mounts the following host paths
so Apache content and certificates persist on the host and are shared:

- `/var/www/html` — webroot used for HTTP-01 challenges
- `/etc/apache2` — Apache configuration
- `/etc/letsencrypt` — Let’s Encrypt certs and state

#### 1) Seed host directories from a temporary testpoint container

Start a temporary testpoint without bind-mounts, then copy baseline content out to the host.

Create `/opt/perfsonar-tp/docker-compose.yml` (temporary) with:

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

Bring it up and seed:

```bash
(cd /opt/perfsonar-tp; podman-compose up -d)  # or docker-compose up -d
mkdir -p /opt/perfsonar-tp/psconfig /var/www/html /etc/apache2 /etc/letsencrypt
docker cp perfsonar-testpoint:/etc/perfsonar/psconfig /opt/perfsonar-tp/psconfig
docker cp perfsonar-testpoint:/var/www/html /var/www/html
docker cp perfsonar-testpoint:/etc/apache2 /etc/apache2
# Seed /etc/letsencrypt from the certbot image (may be minimal; populated on first issuance)
docker create --name certbot-seed certbot/certbot >/dev/null 2>&1 || true
docker cp certbot-seed:/etc/letsencrypt /etc/letsencrypt || true
docker rm -f certbot-seed >/dev/null 2>&1 || true
```

If SELinux is enforcing, the `:z`/`:Z` options in the next step handle labels; no manual `chcon` is
required.

??? note "About /etc/letsencrypt seeding"

    The `/etc/letsencrypt` directory is seeded from the Certbot image (not the testpoint)
    to create the expected path on the host. This seed may be minimal or empty; it will be
    populated during the initial certificate issuance in Step 5.3. Keeping the directory present
    (even if empty) ensures the bind mount works and SELinux labels can be applied on enforcing
    hosts.

Stop the temporary container before switching to the final compose:

```bash
(cd /opt/perfsonar-tp; podman-compose down)  # or docker-compose down
```

#### 2) Create the final compose with shared volumes and certbot

Download a ready-made compose file (or copy it manually):  
Browse: [repo view](https://github.com/osg-htc/networking/blob/master/docs/perfsonar/tools_scripts/docker-compose.testpoint-le.yml)

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint-le.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

Or create `/opt/perfsonar-tp/docker-compose.yml` with:

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

    certbot:
        image: certbot/certbot
        container_name: certbot
        network_mode: "host"
        restart: unless-stopped
        entrypoint: ["/bin/sh","-c","trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;"]
        depends_on:
            - testpoint
        volumes:
            - /var/www/html:/var/www/html:z
            - /etc/letsencrypt:/etc/letsencrypt:z
```

Start the final stack:

```bash
(cd /opt/perfsonar-tp; podman-compose up -d)  # or docker-compose up -d
```

#### 3) Obtain your first Let’s Encrypt certificate (one-time)

The `certbot` sidecar above will renew automatically. For the initial issuance, run:

```bash
docker run --rm --net=host -v /var/www/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt \
    certbot/certbot certonly --webroot -w /var/www/html -d <SERVER_FQDN> \
    --email <LETSENCRYPT_EMAIL> --agree-tos --no-eff-email

# Gracefully reload Apache within the testpoint container (or restart the service)
docker exec -it perfsonar-testpoint bash -lc 'systemctl reload httpd || apachectl -k graceful || true'
```

??? info "Notes"

        - Ensure TCP port 80 on the host is reachable from the internet while issuing certificates.
        - Shared paths use SELinux-aware `:z`/`:Z` to permit container access on enforcing hosts.


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

Basic enroll (interactive root on the host; runs inside the container):

```bash
# Replace with your actual FQDNs (one or two)
FQDN_LAT="<latency.example.org>"
FQDN_BW="<throughput.example.org>"   # optional if you use a second FQDN

# Add auto URLs (configures archives too) and show configured remotes
podman exec -it perfsonar-testpoint psconfig remote --configure-archives add \
    "https://psconfig.opensciencegrid.org/pub/auto/${FQDN_LAT}"
[ -n "${FQDN_BW}" ] && podman exec -it perfsonar-testpoint psconfig remote \
    --configure-archives add "https://psconfig.opensciencegrid.org/pub/auto/${FQDN_BW}"

podman exec -it perfsonar-testpoint psconfig remote list
# or with Docker:
# docker exec -it perfsonar-testpoint psconfig remote list
```

Remove any stale/old entries if present:

```bash
podman exec -it perfsonar-testpoint psconfig remote delete "<old-url>"
```

Automation tip: derive FQDNs from your configured IPs (PTR lookup) and enroll automatically. Review the list before applying.

```bash
# Build candidate FQDN list from IPs referenced in /etc/perfSONAR-multi-nic-config.conf
mapfile -t PS_IPS < <(awk -F= '/^NIC_(IPV4|IPV6)_ADDRS=/ {gsub(/"|\n/,"",$2); split($2,a,/[ ,]/); for(i in a) if (a[i] != "" && a[i] != "-") print a[i]; }' \
    /etc/perfSONAR-multi-nic-config.conf)

FQDNS=()
for ip in "${PS_IPS[@]}"; do
    # Reverse lookup; prefer getent for libc resolution, fallback to dig -x
    name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    if [ -z "$name" ]; then
        name=$(dig +short -x "$ip" | head -n1)
    fi
    name=${name%.}   # strip trailing dot
    if [ -n "$name" ]; then FQDNS+=("$name"); fi
done

# Deduplicate while preserving order
uniq_fqdns=()
for n in "${FQDNS[@]}"; do
    skip=""; for u in "${uniq_fqdns[@]}"; do [ "$u" = "$n" ] && skip=1 && break; done
    [ -z "$skip" ] && uniq_fqdns+=("$n")
done

printf "Will enroll these FQDNs:\n"; printf " - %s\n" "${uniq_fqdns[@]}"
read -r -p "Proceed with enrollment (y/N)? " ans; [ "$ans" = "y" ] || exit 0

for fq in "${uniq_fqdns[@]}"; do
    podman exec -it perfsonar-testpoint psconfig remote --configure-archives add \
        "https://psconfig.opensciencegrid.org/pub/auto/${fq}"
done

podman exec -it perfsonar-testpoint psconfig remote list
```

Verification: Confirm the files under `/etc/perfsonar/psconfig/pscheduler.d/` (inside the container) reflect the expected feeds and, where applicable, `ifaddr` entries match the intended interfaces.

### Helper Script (Recommended)

Instead of the ad-hoc automation snippet above, you can use the installed helper script:

```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh --help

# Typical usage (podman):
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -v

# Dry run only (show planned URLs):
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -n

# Non-interactive (CI) enrollment:
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -y

# If your container name differs:
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -c my-ps-testpoint
```

The script:

- Parses IP lists from `/etc/perfSONAR-multi-nic-config.conf` (`NIC_IPV4_ADDRS` / `NIC_IPV6_ADDRS`).
- Performs reverse DNS lookups (getent/dig) to derive FQDNs.
- Deduplicates while preserving discovery order.
- Adds each `https://psconfig.opensciencegrid.org/pub/auto/<FQDN>` with `--configure-archives`.
- Lists configured remotes and returns non-zero if any enrollment fails.

Integrate into provisioning CI by running with `-n` (dry-run) for approval and then `-y` once approved.

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


