# Installing a perfSONAR Testpoint for WLCG/OSG

This quick-deploy playbook walks WLCG/OSG site administrators through the end-to-end installation, configuration, and validation of a perfSONAR testpoint on Enterprise Linux 9 (EL9). Each phase references tooling that already lives in this repository so you can automate as much as possible while still capturing the site-specific information required by OSG/WLCG operations.

---

## Prerequisites and Planning

Before you begin, gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage.
- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN information, PSConfig registration URLs.
- **Operational contacts:** site admin email, OSG facility name, latitude/longitude, usage policy link.
- **Repository artifacts:** the scripts referenced below are in `docs/perfsonar/` in this repository.

### Clone the Repository

This guide references multiple scripts from the osg-htc/networking repository. Clone the repository to your testpoint host for easy access to all tools.

**Recommended locations:**

- **Networking repo:** `/opt/networking` (configuration scripts and documentation)
- **perfSONAR testpoint compose bundle:** `/opt/testpoint` (if using containerized testpoint)

```bash
# Clone the networking repository to /opt
cd /opt
git clone https://github.com/osg-htc/networking.git

# Optional: if deploying the perfSONAR testpoint container, clone it separately
# git clone https://github.com/perfsonar/testpoint.git /opt/testpoint
```

After cloning, all script examples in this guide that reference `docs/perfsonar/tools_scripts/` assume you're running commands from `/opt/networking`.

> **Note:** All shell commands assume an interactive root shell. Prefix with `sudo` when running as a non-root user.

---

## Step 1 – Install and Harden EL9

1. **Provision EL9:** Install AlmaLinux, Rocky Linux, or RHEL 9 with the *Minimal* profile.

2. **Apply baseline updates (and verify dependencies):**

    Use the repository's helper to check for required tools and print
    copy/paste install commands. Then apply OS updates and any remaining
    baseline packages.

    - From a local clone of this repository (recommended):

        ```bash
        cd /opt/networking
        ./docs/perfsonar/tools_scripts/check-deps.sh
        ```

    ??? tip "Alternative: Download and run directly"
        ```bash
        curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-deps.sh -o ./check-deps.sh
        chmod 0755 ./check-deps.sh
        ./check-deps.sh
        ```

    ??? info "Apply updates and install baseline packages"
        On EL9, apply updates and install common baseline packages, then add any
        packages suggested by the checker (copy/paste the printed dnf line):

        ```bash
        dnf update -y
        dnf install -y epel-release chrony vim git
        # (Optional) install any additional packages suggested by check-deps.sh
        # e.g., dnf install -y NetworkManager rsync curl openssl nftables
        ```

3. **Set the hostname and time sync:**
    
    Note when you have multiple NICs pick one to be the hostname.  That should also be the NIC that hosts the default route (See step 2 below).

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

## Step 2 – Configure Policy-Based Routing (PBR)

The repository ships an enhanced script `docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh` that automates NetworkManager configuration and routing rules and can auto-generate its config file.

Script location in the repository:

- [Directory (browse)](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts)
- [Raw file (direct download)](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh)

1. **Stage the script:**

    - From a local clone of this repository:

        ```bash
        cd /opt/networking
        install -m 0755 docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh ~/perfsonar-pbr-nm.sh
        cd ~
        ```

    ??? tip "Alternative: Download directly from the repository URL"
        ```bash
        curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh -o ./perfSONAR-pbr-nm.sh
        chmod 0755 ./perfSONAR-pbr-nm.sh
        ```

2. **Auto-generate `/etc/perfSONAR-multi-nic-config.conf`:** use the script’s generator to detect NICs, addresses, prefixes, and gateways and write a starting config you can review/edit. Auto-generation is opt-in; it does not run by default.

    - Preview (no changes):

        ```bash
        ~/perfsonar-pbr-nm.sh --generate-config-debug
        ```

    - Write the config file to `/etc/perfSONAR-multi-nic-config.conf`:

        ```bash
        ~/perfsonar-pbr-nm.sh --generate-config-auto
        ```

    Then open the file and adjust any site-specific values (e.g., confirm `DEFAULT_ROUTE_NIC`, add any `NIC_IPV4_ADDROUTE` entries, or replace “-” for unused IP/gateway fields).

    !!! warning "Gateways required for addresses"
        Any NIC with an IPv4 address must also have an IPv4 gateway, and any NIC with an IPv6 address must have an IPv6 gateway. If the generator cannot detect a gateway, it adds a WARNING block to the generated file listing affected NICs. Edit `NIC_IPV4_GWS`/`NIC_IPV6_GWS` accordingly before applying changes.

    !!! note "Gateway prompts"

        During generation, the script attempts to detect gateways per-NIC. If a NIC has an IP address but no gateway could be determined, it will prompt you interactively to enter an IPv4 and/or IPv6 gateway (or `-` to skip). Prompts are skipped in non-interactive sessions or when you use `--yes`.

3. **Execute the script:**

    - Rehearsal (no changes, extra logging recommended on first run):

        ```bash
        ~/perfsonar-pbr-nm.sh --dry-run --debug
        ```

    - Apply changes non-interactively (auto-confirm):

        ```bash
        ~/perfsonar-pbr-nm.sh --yes
        ```

    - Or run interactively and answer the confirmation prompt when ready:

        ```bash
        ~/perfsonar-pbr-nm.sh
        ```

    !!! note "Missing gateways at apply time"

        If the loaded config still contains `-` for a gateway on a NIC that has an IP address, the script will prompt you interactively to provide a gateway before applying changes. Use `--yes` (or run non-interactively) to suppress prompts; in that case, missing gateways will cause validation to fail so you can correct the config first.

The script creates a timestamped backup of existing NetworkManager profiles, seeds routing tables, and applies routing rules. Review `/var/log/perfSONAR-multi-nic-config.log` after the run and retain it with your change records.

### DNS: forward and reverse entries (required)

All IP addresses that will be used for perfSONAR testing MUST have DNS entries: a forward (A/AAAA) record and a matching reverse (PTR) record. This is required so remote test tools and site operators can reliably reach and identify your host, and because some measurement infrastructure and registration systems perform forward/reverse consistency checks.

- For single-stack IPv4-only hosts: ensure A and PTR are present and consistent.
- For single-stack IPv6-only hosts: ensure AAAA and PTR are present and consistent.
- For dual-stack hosts: both IPv4 and IPv6 addresses used for testing must have matching forward and reverse records (A+PTR and AAAA+PTR).

??? example "Example: Bash script to automate DNS verification"
    The `perfSONAR-multi-nic-config.conf` contains the arrays `NIC_IPV4_ADDRS` and `NIC_IPV6_ADDRS` (with `-` for unused entries). You can automate a forward/reverse consistency check using `dig` or `host` by sourcing the config and iterating the arrays.

    ```bash
    # quick DNS consistency check using /etc/perfSONAR-multi-nic-config.conf
    set -euo pipefail
    CONFIG=/etc/perfSONAR-multi-nic-config.conf
    [ -f "$CONFIG" ] || { echo "Config not found: $CONFIG" >&2; exit 2; }
    source "$CONFIG"

    check_ip() {
       local ip=$1
       local family=$2   # 4 or 6
       # strip CIDR if present
       ip=${ip%%/*}
       [ "$ip" = "-" ] && return 0

       # PTR lookup (reverse)
       ptr=$(dig +short -x "$ip" | head -n1)
       if [ -z "$ptr" ]; then
          echo "MISSING PTR for $ip"
          return 1
       fi
       # remove trailing dot from PTR
       ptr=${ptr%.}

       # Forward lookup for the hostname returned by PTR
       if [ "$family" = "4" ]; then
          fwd=$(dig +short A "$ptr" | tr '\n' ' ')
       else
          fwd=$(dig +short AAAA "$ptr" | tr '\n' ' ')
       fi

       if ! echo "$fwd" | grep -qw "$ip"; then
          echo "INCONSISTENT: PTR $ptr does not resolve back to $ip (resolved: $fwd)"
          return 1
       fi
       echo "OK: $ip ⇄ $ptr"
       return 0
    }

    errors=0
    for ip in "${NIC_IPV4_ADDRS[@]:-}"; do
       if [ "$ip" != "-" ]; then
          check_ip "$ip" 4 || errors=$((errors+1))
       fi
    done
    for ip in "${NIC_IPV6_ADDRS[@]:-}"; do
       if [ "$ip" != "-" ]; then
          check_ip "$ip" 6 || errors=$((errors+1))
       fi
    done

    if (( errors > 0 )); then
       echo "DNS verification failed ($errors problem(s)). Fix DNS (forward/reverse) before running tests." >&2
       exit 1
    fi
    echo "DNS forward/reverse checks passed for configured addresses."
    ```

    **Notes and automation tips:**

    - The script above uses `dig` (bind-utils package) which is commonly available; you can adapt it to use `host` if preferred.
    - Run the check as part of your provisioning CI or as a pre-flight check before enabling measurement registration.
    - For large sites or many addresses, parallelize the checks (xargs -P) or use a small Python script that leverages `dns.resolver` for async checks.
    - If your PTR returns a hostname with a trailing dot, the script strips it before the forward check.

If any addresses fail these checks, correct the DNS zone (forward and/or reverse) and allow DNS propagation before proceeding with registration and testing.

??? example "Download and run the DNS checker"
    You can download and run the DNS checker directly on the host (or from any machine that has network visibility to your DNS servers). The script expects `/etc/perfSONAR-multi-nic-config.conf` to exist and be readable.

    ```bash
    # Download (curl)
    curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-perfsonar-dns.sh -o ./check-perfsonar-dns.sh
    # Or download with wget
    # wget -O ./check-perfsonar-dns.sh https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/check-perfsonar-dns.sh

    chmod 0755 ./check-perfsonar-dns.sh

    # Install DNS tools if missing (EL9)
    sudo dnf install -y bind-utils

    # Debian/Ubuntu alternative
    # sudo apt-get update && sudo apt-get install -y dnsutils

    # Run the check (needs to read /etc/perfSONAR-multi-nic-config.conf)
    sudo ./check-perfsonar-dns.sh
    ```

    **Notes:**

    - If you downloaded the script to a different path, either move it to the host and run it there, or copy `/etc/perfSONAR-multi-nic-config.conf` to the machine where you run the check (recommended only for temporary verification; treat the config as sensitive).
    - The script uses `dig` (preferred) or `host` as a fallback; ensure one of those is installed.
    - Run this check after you generate or edit `/etc/perfSONAR-multi-nic-config.conf` and before you register or start active measurements.

1. **Verify the routing policy:**

   ```bash
   nmcli connection show
   ip rule show
   ip route show table <table-id>
   ```

   Confirm that non-default interfaces have their own routing tables and that the default interface owns the system default route.

---

## Step 3 – Configure nftables, SELinux, and Fail2Ban

Use `docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh` to configure a hardened nftables profile with optional SELinux and Fail2Ban support.

Script location in the repository:

- [Directory (browse)](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts)
- [Raw file (direct download)](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh)

Prerequisites (not installed by the script):

- `nftables` must already be installed and available (`nft` binary) for firewall configuration.
- `fail2ban` must be installed if you want the optional jail configuration.
- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

1. **Stage the installer:**

    - From a local clone of this repository:

        ```bash
        cd /opt/networking
        install -m 0755 docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh ~/perfsonar-install-nftables.sh
        cd ~
        ```

    ??? tip "Alternative: Download directly from the repository URL"
        ```bash
        curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh -o ~/perfsonar-install-nftables.sh
        chmod 0755 ~/perfsonar-install-nftables.sh
        ```

2. **Run with desired options:**

   ```bash
   ~/perfsonar-install-nftables.sh --selinux --fail2ban --yes
   ```

   - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the summary and answer manually).
   - Add `--dry-run` for a rehearsal that only prints the planned actions.

    The script writes nftables rules for perfSONAR services, derives SSH allow-lists from `/etc/perfSONAR-multi-nic-config.conf`, optionally adjusts SELinux, and enables Fail2Ban jails—only if those components are already installed.

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

3. **Confirm firewall state and security services:**

   ??? info "Verification commands"
      ```bash
      nft list ruleset
      sestatus
      systemctl status fail2ban
      ```

   Document any site-specific exceptions (e.g., additional allowed management hosts) in your change log.

---

## Step 4 – Deploy the Containerized perfSONAR Testpoint

We’ll run the official testpoint image from the GitHub Container Registry using Podman, but we’ll show Docker-style commands so you can choose either tool. We’ll bind-mount host paths so edits on the host are reflected inside the containers.

Key paths to persist on the host:

- `/opt/testpoint/psconfig` → container `/etc/perfsonar/psconfig`
- `/etc/apache2` → container `/etc/apache2` (Apache configs)
- `/var/www/html` → container `/var/www/html` (webroot for Toolkit and ACME challenges)
- `/etc/letsencrypt` → container `/etc/letsencrypt` (certs/keys, if using Let’s Encrypt)

1. Install container tooling (Podman and optional Docker-style compose):

   ```bash
   dnf install -y podman podman-compose python3-pip
   pip3 install --upgrade docker-compose
   ```

   Tip: you can use either `podman-compose` or `docker-compose` in the steps below. Substitute the command that matches your preference.

2. Prepare directories on the host:

   ```bash
   mkdir -p /opt/testpoint/psconfig
   mkdir -p /var/www/html
   mkdir -p /etc/apache2
   mkdir -p /etc/letsencrypt
   ```

3. Seed defaults from the testpoint container (first run without host bind-mounts for Apache/webroot so we can copy the initial content out):

   Create a minimal compose file at `/opt/testpoint/docker-compose.yml`:

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
         # Don't bind Apache/webroot yet; we'll copy defaults out first
         # Persist perfSONAR psconfig later after seeding (see step 5)
       tty: true
       pids_limit: 8192
       cap_add:
         - CAP_NET_RAW
   ```

   Bring it up with your preferred tool:

   ```bash
   (cd /opt/testpoint; podman-compose up -d)  # or: (cd /opt/testpoint; docker-compose up -d)
   ```

4. Copy baseline content out of the running container to the host:

   ```bash
   # Use docker cp or podman cp (either works)
   docker cp perfsonar-testpoint:/etc/apache2 /etc/apache2
   docker cp perfsonar-testpoint:/var/www/html /var/www/html
   docker cp perfsonar-testpoint:/etc/perfsonar/psconfig /opt/testpoint/psconfig
   ```

   If SELinux is enforcing, we’ll relabel these paths when we mount (using `:z`/`:Z` below), so you don’t need manual `chcon`.

5. Replace the compose file with bind-mounts that map host paths directly, and (optionally) add a `certbot` sidecar for Let’s Encrypt.

    You can download a ready-to-use compose file from this repository:

    - [Browse](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts/docker-compose.yml)
    - Download directly:

       ```bash
       curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.yml -o /opt/testpoint/docker-compose.yml
       ```

    Or create/edit `/opt/testpoint/docker-compose.yml` with the following content:

    Note: The provided compose file ships with `io.containers.autoupdate=registry` labels pre-set for Podman auto-update.

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
             - /opt/testpoint/psconfig:/etc/perfsonar/psconfig:Z
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

6. Restart with the new compose:

   ```bash
   (cd /opt/testpoint; podman-compose down)
   (cd /opt/testpoint; podman-compose up -d)  # or docker-compose down && docker-compose up -d
   ```

7. Optional – obtain your first Let’s Encrypt certificate:

   The `certbot` sidecar above continuously renews existing certs. For the initial issuance, run a one-shot command and then reload Apache inside the testpoint container:

   ```bash
   # Issue (HTTP-01 webroot challenge). Replace values accordingly.
   docker run --rm --net=host -v /var/www/html:/var/www/html -v /etc/letsencrypt:/etc/letsencrypt \
     certbot/certbot certonly --webroot -w /var/www/html -d <SERVER_FQDN> \
     --email <LETSENCRYPT_EMAIL> --agree-tos --no-eff-email

   # Gracefully reload Apache within the testpoint container (or restart the service)
   docker exec -it perfsonar-testpoint bash -lc 'systemctl reload httpd || apachectl -k graceful || true'
   ```

   Notes:
   - Ensure port 80 on the host is reachable from the internet while issuing certificates.
   - All shared paths use SELinux-aware `:z`/`:Z` to permit container access on enforcing hosts.

8. Verify:

   ```bash
   curl -fsS http://localhost/toolkit/ | head -n 5
   docker ps  # or podman ps
   ```

---

## Step 5 – Register and Configure with WLCG/OSG

1. **PerfSONAR toolkit configuration:**
   
   Browse to `https://<SERVER_FQDN>/toolkit` and complete the local toolkit setup wizard.
   
   ??? info "Configuration details to populate"
      - Site contact email
      - Usage policy URL
      - Location (latitude/longitude)
      - Export the configuration via `/etc/perfsonar/psconfig/nodes/local.json` for record keeping

2. **OSG/WLCG registration workflow:**
   
   ??? info "Registration steps and portals"
      - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
      - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
      - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

3. **pSConfig enrollment:**
   
   For each active NIC, register with the psconfig service so measurements cover all paths.

   ??? info "Registration command and verification"
      Example registration:

      ```bash
      /usr/bin/psconfig psconfig remote --configure-archives add --url https://psconfig.opensciencegrid.org/pub/auto/<NIC-FQDN>
      ```

      Confirm the resulting files in `/etc/perfsonar/psconfig/pscheduler.d/` map to the correct interface addresses (`ifaddr` tags).

4. **Document memberships:** update your site wiki or change log with assigned mesh names, feed URLs, and support contacts.

### Update Lookup Service registration inside the container

Use the helper script to edit `/etc/perfsonar/lsregistrationdaemon.conf` inside the running `perfsonar-testpoint` container and restart the daemon only if needed.

- Script (browse): [perfSONAR-update-lsregistration.sh](https://github.com/osg-htc/networking/tree/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh)
- Raw (download): [raw link](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh)

Install and run examples (root shell):

```bash
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh \
   -o ~/perfSONAR-update-lsregistration.sh
chmod 0755 ~/perfSONAR-update-lsregistration.sh

# Preview changes only
~/perfSONAR-update-lsregistration.sh --dry-run --site-name "Acme Co." --project WLCG --admin-email admin@example.org --admin-name "pS Admin"

# Apply common updates and restart the daemon inside the container
~/perfSONAR-update-lsregistration.sh \
   --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
   --city Berkeley --region CA --country US --zip 94720 \
   --latitude 37.5 --longitude -121.7469 \
   --admin-name "pS Admin" --admin-email admin@example.org
```

---

## Step 6 – Post-Install Validation

Perform these checks before handing the host over to operations:

1. **System services:**

   ??? info "Verify Podman and compose services"
      ```bash
      systemctl status podman
      systemctl --user status podman-compose@perfsonar-testpoint.service
      ```

      Ensure both are active/green.

2. **Container health:**

   ??? info "Check container status and logs"
      ```bash
      podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
      podman logs pscheduler-agent | tail
      ```

3. **Network path validation:**

   ??? info "Test network connectivity and routing"
      ```bash
      pscheduler task throughput --dest <remote-testpoint>
      tracepath -n <remote-testpoint>
      ```

      Confirm traffic uses the intended policy-based routes (check `ip route get <dest>`).

4. **Toolkit diagnostics:** visit the Toolkit UI → *Dashboard* → *Host Status* to confirm pScheduler, MaDDash, and owamp/bwctl services report healthy.

5. **Security posture:**

   ```bash
   nft list ruleset | grep perfsonar
   fail2ban-client status
   ausearch --message AVC --just-one
   ```

   Investigate any SELinux denials or repeated Fail2Ban bans.

6. **LetsEncrypt certificate check:**

   ```bash
   openssl s_client -connect <SERVER_FQDN>:443 -servername <SERVER_FQDN> | openssl x509 -noout -dates -issuer
   ```

   Ensure the issuer is Let’s Encrypt and the validity period is acceptable.

7. **Reporting:** run the perfSONAR toolkit daily report and send outputs to operations:

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

    2. Enable the Podman auto-update timer (runs daily by default):

        ```bash
        systemctl enable --now podman-auto-update.timer
        ```

    3. Run ad-hoc when desired and preview:

        ```bash
        podman auto-update --dry-run
        podman auto-update
        ```

    4. Inspect recent runs:

        ```bash
        systemctl list-timers | grep podman-auto-update
        journalctl -u podman-auto-update --since "1 day ago"
        ```


