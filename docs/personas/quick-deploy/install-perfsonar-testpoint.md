---
title: Install: perfSONAR Testpoint
description: Instructions and verification to deploy a perfSONAR testpoint for WLCG/OSG.
persona: quick-deploy
owners: [networking-team@osg-htc.org]
status: draft
tags: [install, perfSONAR, container]
---

# Installing a perfSONAR Testpoint for WLCG/OSG

This quick-deploy playbook walks WLCG/OSG site administrators through the end-to-end installation, configuration, and validation of a perfSONAR testpoint on Enterprise Linux 9 (EL9). Each phase references tooling that already lives in this repository so you can automate as much as possible while still capturing the site-specific information required by OSG/WLCG operations.

---

## Prerequisites and Planning

Before you begin, gather the following information:

- **Hardware details:** hostname, BMC/iLO/iDRAC credentials (if used), interface names, available storage.
- **Network data:** IPv4/IPv6 assignments for each NIC, default gateway, internal/external VLAN information, PSConfig registration URLs.
- **Operational contacts:** site admin email, OSG facility name, latitude/longitude, usage policy link.
- **Repository artifacts:** the scripts referenced below are in `docs/perfsonar/` in this repository.

> **Note:** All shell commands assume an interactive root shell. Prefix with `sudo` when running as a non-root user.

---

## Step 1 – Install and Harden EL9

1. **Provision EL9:** Install AlmaLinux, Rocky Linux, or RHEL 9 with the *Minimal* profile.
2. **Apply baseline updates:**

   ```bash
   dnf update -y && dnf install -y epel-release chrony vim git
   ```

3. **Set the hostname and time sync:**
    !!! note when you have multiple NICs pick one to be the hostname.  That should also be the NIC that hosts the default route (See step 2 below).
   ```bash
   hostnamectl set-hostname <testpoint-hostname>
   systemctl enable --now chronyd
   timedatectl set-timezone <Region/City>
   ```

4. **Disable unused services:**

   ```bash
   systemctl disable --now firewalld NetworkManager-wait-online
   dnf remove -y rsyslog
   ```

5. **Record NIC names:**

   ```bash
   nmcli device status
   ip -br addr
   ```

Document interface mappings; you will need them for the policy-based routing configuration.

---

## Step 2 – Configure Policy-Based Routing (PBR)

The repository ships an enhanced script `docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh` that automates NetworkManager configuration and routing rules and can auto-generate its config file.

1. **Stage the script:**

   ```bash
   install -m 0755 docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh /usr/local/sbin/perfSONAR-pbr-nm.sh
   ```

2. **Auto-generate `/etc/perfSONAR-multi-nic-config.conf`:** use the script’s generator to detect NICs, addresses, prefixes, and gateways and write a starting config you can review/edit.

    - Preview (no changes):

       ```bash
       /usr/local/sbin/perfsonar-pbr-nm.sh --generate-config-debug
       ```

    - Write the config file to `/etc/perfSONAR-multi-nic-config.conf`:

       ```bash
       /usr/local/sbin/perfsonar-pbr-nm.sh --generate-config-auto
       ```

    Then open the file and adjust any site-specific values (e.g., confirm `DEFAULT_ROUTE_NIC`, add any `NIC_IPV4_ADDROUTE` entries, or replace “-” for unused IP/gateway fields).

3. **Execute the script:**

    - Rehearsal (no changes, extra logging recommended on first run):

       ```bash
       perfsonar-pbr-nm.sh --dry-run --debug
       ```

    - Apply changes non-interactively (auto-confirm):

       ```bash
       perfsonar-pbr-nm.sh --yes
       ```

    - Or run interactively and answer the confirmation prompt when ready:

       ```bash
       perfsonar-pbr-nm.sh
       ```

    The script creates a timestamped backup of existing NetworkManager profiles, seeds routing tables, and applies routing rules. Review `/var/log/perfSONAR-multi-nic-config.log` after the run and retain it with your change records.

4. **Verify the routing policy:**

   ```bash
   nmcli connection show
   ip rule show
   ip route show table <table-id>
   ```

   Confirm that non-default interfaces have their own routing tables and that the default interface owns the system default route.

---

## Step 3 – Configure nftables, SELinux, and Fail2Ban

Use `docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh` to configure a hardened nftables profile with optional SELinux and Fail2Ban support.

Prerequisites (not installed by the script):

- `nftables` must already be installed and available (`nft` binary) for firewall configuration.
- `fail2ban` must be installed if you want the optional jail configuration.
- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

1. **Stage the installer:**

   ```bash
   install -m 0755 docs/perfsonar/tools_scripts/perfSONAR-install-nftables.sh /usr/local/sbin/perfsonar-install-nftables.sh
   ```

2. **Run with desired options:**

   ```bash
   perfsonar-install-nftables.sh --selinux --fail2ban --yes
   ```

   - Use `--yes` to skip the interactive confirmation prompt (omit it if you prefer to review the summary and answer manually).
   - Add `--dry-run` for a rehearsal that only prints the planned actions.

    The script writes nftables rules for perfSONAR services, derives SSH allow-lists from `/etc/perfSONAR-multi-nic-config.conf`, optionally adjusts SELinux, and enables Fail2Ban jails—only if those components are already installed.

    Notes:
    - SSH allow-list is built from your NIC address/prefix arrays in `/etc/perfSONAR-multi-nic-config.conf`:
       - CIDR values in `NIC_IPV4_PREFIXES`/`NIC_IPV6_PREFIXES` paired with corresponding addresses are treated as subnets.
       - Address entries without a prefix are treated as single hosts.
       - The script logs the resolved lists (IPv4/IPv6 subnets and hosts) for review.
    - The generated nftables file is validated with `nft -c -f` before being written; on validation failure, nothing is installed and a message is logged.
    - Output locations: rules → `/etc/nftables.d/perfsonar.nft`, log → `/var/log/perfSONAR-install-nftables.log`, backups → `/var/backups/perfsonar-install-<timestamp>`.

   Tip: preview the fully rendered nftables rules (no changes are made):

   ```bash
   perfsonar-install-nftables.sh --print-rules
   ```

   Optional: manually add extra management hosts/subnets

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

   ```bash
   nft list ruleset
   sestatus
   systemctl status fail2ban
   ```

   Document any site-specific exceptions (e.g., additional allowed management hosts) in your change log.

---

## Step 4 – Deploy the Containerized perfSONAR Testpoint

WLCG/OSG supports the container-based perfSONAR testpoint using Podman and Podman Compose. This section also layers an alternate Docker Compose binary that allows automatic certificate management via Let’s Encrypt.

1. **Install Podman tooling:**

   ```bash
   dnf install -y podman podman-compose python3-pip
   pip3 install --upgrade docker-compose
   ```

   The `docker-compose` Python package supplies the alternative binary (`/usr/local/bin/docker-compose`) required for Let’s Encrypt automation used by the perfSONAR systemd stack.

2. **Enable cgroups v2 and lingering user sessions (if not default):**

   ```bash
   grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
   loginctl enable-linger perfsonar
   ```

   Reboot if you updated the kernel arguments.

3. **Clone the deployment bundle:**

   ```bash
   git clone https://github.com/perfsonar/perfsonar-testpoint-container.git /opt/perfsonar-testpoint
   cd /opt/perfsonar-testpoint
   ```

4. **Customize environment variables:** edit `.env` (or `pscheduler.env`, `esmond.env`, etc.) to set
   - `LETSENCRYPT_EMAIL`
   - `SERVER_FQDN`
   - `SITE_NAME`
   - data volumes under `/var/lib/perfsonar`

5. **Deploy via Podman Compose:**

   ```bash
   podman-compose up -d
   podman ps
   ```

   Verify that `pscheduler`, `esmond`, and `maat` containers are running. Podman generates systemd unit files under `~/.config/systemd/user/` that keep the stack running across reboots.

6. **Optional – generate systemd units with docker-compose:**

   ```bash
   docker-compose --profile systemd config > /etc/systemd/system/perfsonar-testpoint.service
   systemctl daemon-reload
   systemctl enable --now perfsonar-testpoint.service
   ```

   Use this when you require root-managed units instead of user lingering.

---

## Step 5 – Register and Configure with WLCG/OSG

1. **PerfSONAR toolkit configuration:**
   - Browse to [https://<SERVER_FQDN>/toolkit](https://<SERVER_FQDN>/toolkit) and complete the local toolkit setup wizard.
   - Populate site contact email, usage policy URL, and location (latitude/longitude). Export the configuration via `/etc/perfsonar/psconfig/nodes/local.json` for record keeping.

2. **OSG/WLCG registration workflow:**
   - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
   - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
   - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

3. **PSConfig enrollment:**
   - For each active NIC, register with the psconfig service so measurements cover all paths. Example:

     ```bash
     /usr/bin/psconfig pscheduler add --url https://psconfig.opensciencegrid.org/pub/<feed>.json
     ```

   - Confirm the resulting files in `/etc/perfsonar/psconfig/pscheduler.d/` map to the correct interface addresses (`ifaddr` tags).

4. **Document memberships:** update your site wiki or change log with assigned mesh names, feed URLs, and support contacts.

---

## Step 6 – Post-Install Validation

Perform these checks before handing the host over to operations:

1. **System services:**

   ```bash
   systemctl status podman
   systemctl --user status podman-compose@perfsonar-testpoint.service
   ```

   Ensure both are active/green.

2. **Container health:**

   ```bash
   podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
   podman logs pscheduler-agent | tail
   ```

3. **Network path validation:**

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

Document any deviations from this procedure so the next deployment at your site can reuse improvements with minimal effort.
