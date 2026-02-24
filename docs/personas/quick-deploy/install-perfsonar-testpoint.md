# Installing a perfSONAR Testpoint for WLCG/OSG
<!-- markdownlint-disable MD040 -->

This guide walks WLCG/OSG site administrators through end-to-end installation, configuration, and validation of a
perfSONAR testpoint on Enterprise Linux 9 (EL9). It uses automated tooling from this repository to streamline the
process while accommodating site-specific requirements.

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

??? info "Quick capture of existing lsregistration config (if you have a prior installation)"
    
    Download a temp copy:   
    ```bash
    curl -fsSL \
      https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-update-lsregistration.sh \
      -o /tmp/update-lsreg.sh
    chmod 0755 /tmp/update-lsreg.sh
    ```
    
    **For container-based installations (testpoint):**
    ```bash
    /tmp/update-lsreg.sh extract --output /root/restore-lsreg.sh
    ```
    
    **For RPM-based/local installations (toolkit or older hosts):**
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
    long boot delays while containers and policy-based routing come up. If your site depends on
    `network-online.target` (for example, iSCSI/NFS root or bonded links that must be up before services start), leave
    `NetworkManager-wait-online` enabled.
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

## Step 2 – Choose Your Deployment Path

After completing Step 1 (minimal OS hardening), you can proceed in one of two ways:

### Path A: Orchestrated Guided Install (Recommended for New Deployments)

The orchestrator automates package installation, bootstrap, PBR configuration, security hardening, container deployment,
certificate issuance, and pSConfig enrollment with interactive pauses (or non-interactive batch mode).

**Download and run the orchestrator:**

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh \
    -o /tmp/perfSONAR-orchestrator.sh
chmod 0755 /tmp/perfSONAR-orchestrator.sh
```

**Interactive mode** (pause at each step, confirm/skip/quit):

```bash
/tmp/perfSONAR-orchestrator.sh
```

**Non-interactive mode** (auto-confirm all steps):

```bash
/tmp/perfSONAR-orchestrator.sh --non-interactive --option A
```

**With Let's Encrypt (Option B):**

```bash
/tmp/perfSONAR-orchestrator.sh --option B --fqdn <FQDN> --email <EMAIL>
```

**Flags:**

- `--option {A|B}` — **Deployment mode:** A = testpoint only (default); B = testpoint with Let's Encrypt certificate automation
- `--fqdn NAME` — primary FQDN for certificates (required for `--option B`)
- `--email ADDRESS` — email for Let's Encrypt notifications (required for `--option B`)
- `--non-interactive` — skip pauses, auto-confirm
- `--yes` — auto-confirm internal script prompts
- `--dry-run` — preview steps without executing
- `--auto-update` — install and enable a systemd timer that pulls container images daily and restarts containers only if updated (creates `/usr/local/bin/perfsonar-auto-update.sh`, a systemd service and timer)

!!! tip "Paths vs. Orchestrator Options"
    **Paths = how you install the testpoint**
    - **Path A (Automated Install Path)**: Use the orchestrator script (guided/automated).
    - **Path B (Manual Install Path)**: Follow the manual, step-by-step commands.

    **Orchestrator Options = what the orchestrator deploys** (only used when you choose Path A)
    - **Option A**: Testpoint only (no automatic certificate management)
    - **Option B**: Testpoint with Let's Encrypt automation (requires `--fqdn` and `--email`)

    Remember: choose Path A or Path B first. If you pick Path A, then choose Option A or B for certificate handling.

**If you choose this path, skip to [Step 7](#step-7-register-and-configure-with-wlcgosg)** (the orchestrator completes Steps 2–6 for you).

---

### Path B: Manual Step-by-Step

For users who prefer granular control or need to customize each stage, continue with manual package installation,
bootstrap, and configuration.

#### Step 2.1 – Install Base Packages

On minimal hosts several required tools (e.g. `dig`, `nft`, `podman-compose`) are missing. Install all recommended
prerequisites in one command:

```bash
dnf -y install podman podman-docker podman-compose \
    jq curl tar gzip rsync bind-utils \
    nftables fail2ban policycoreutils-python-utils \
    python3 iproute iputils procps-ng sed grep gawk

```

This ensures all subsequent steps (PBR generation, DNS checks, firewall hardening, container deployment) have their dependencies available.

#### Step 2.2 – Bootstrap Helper Scripts

Use the bootstrap script to install helper scripts under `/opt/perfsonar-tp/tools_scripts`:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
    -o /tmp/install_tools_scripts.sh

chmod 0755 /tmp/install_tools_scripts.sh

/tmp/install_tools_scripts.sh /opt/perfsonar-tp
```

**Verify bootstrap completed successfully:**

```bash
# Check that all helper scripts were downloaded
ls -1 /opt/perfsonar-tp/tools_scripts/*.sh | wc -l
# Should show 11 shell scripts

# Verify key scripts are present and executable
ls -l /opt/perfsonar-tp/tools_scripts/{perfSONAR-pbr-nm.sh,perfSONAR-install-nftables.sh,perfSONAR-orchestrator.sh}
```

---

## Step 3 – Configure Policy-Based Routing (PBR)

!!! note "Skip this step if you used the orchestrator (Path A)"
    
    The orchestrator automates PBR configuration. If you ran it in Step 2, skip to [Step 4](#step-4-configure-nftables-selinux-and-fail2ban).
    
The script `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh` automates NetworkManager profiles and routing rule
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
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-debug    
```

Generate and **write** the config file:
        
```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --generate-config-auto 
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
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes
```
        
??? info "If SSH connection drops during network reconfiguration:"
        
    1. Access via BMC/iLO/iDRAC console or physical console
    1. Review `/var/log/perfSONAR-multi-nic-config.log` for errors
    1. Check network state with `nmcli connection show` and `ip addr`
    1. Restore from backup if needed: backups are in `/var/backups/nm-connections-<timestamp>/`
    1. Reapply config after corrections: `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes`


#### Full rebuild (destructive – removes all NM connections first)

```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --rebuild-all --yes
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
    /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh
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

!!! note "Skip this step if you used the orchestrator (Path A)"
    
    The orchestrator automates security hardening. If you ran it in Step 2, skip to [Step 5](#step-5-deploy-the-containerized-perfsonar-testpoint).
    
Use `/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh` to configure a hardened nftables profile with
optional SELinux and Fail2Ban support. No staging or copy step is required.
    
Prerequisites (not installed by the script and should have been installed when check-deps.sh was run above):
    
- `nftables` must already be installed and available (`nft` binary) for firewall configuration.

- `fail2ban` must be installed if you want the optional jail configuration.

- SELinux tools (e.g., `getenforce`, `policycoreutils`) must be present to attempt SELinux configuration.

If any prerequisite is missing, the script skips that component and continues.

### Install/configure the desired options

You can use the install script to install the options you want (selinux, fail2ban)
```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --selinux --fail2ban --yes
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
    /opt/perfsonar-tp/tools_scripts/perfSONAR-install-nftables.sh --print-rules
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

## Step 5 – Deploy the Containerized perfSONAR Testpoint

!!! note "Skip this step if you used the orchestrator (Path A)"
    
    The orchestrator automates container deployment and certificate issuance. If you ran it in Step 2, skip to [Step 6](#step-6-configure-and-enroll-in-psconfig).
    
Run the official testpoint image using Podman (or Docker). Choose one of the two deployment modes:

- **Option A:** Testpoint only (simplest) — bind-mounts `/opt/perfsonar-tp/psconfig`, `/var/www/html`, and `/etc/apache2` for Apache and pSConfig.

- **Option B:** Testpoint + Let’s Encrypt — two containers that share Apache files and certs via host bind mounts.

Use `podman-compose` (or `docker-compose`) in the examples below.

### Option A — Testpoint only (simplest)

#### 1) Seed required host directories (REQUIRED before first compose up)

**Why seed?** The perfsonar-testpoint container requires baseline configuration files from the image to be present on
the host filesystem. Without seeding, the bind-mounted directories would be empty, causing Apache and perfSONAR services
to fail.

**What's seeded:**

- `/opt/perfsonar-tp/psconfig` — perfSONAR pSConfig files (baseline remotes and archives)

- `/var/www/html` — Apache webroot with index.html (required for healthcheck)

- `/etc/apache2` — Apache config including `sites-available/default-ssl.conf`

Run the bundled seeding helper script (automatically installed in Step 2):

```bash
/opt/perfsonar-tp/tools_scripts/seed_testpoint_host_dirs.sh
```

??? info "Seed script details"

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
    
    If SELinux is enforcing, the `:Z` and `:z` options in the compose files will cause Podman to relabel the host paths when
    containers start. No manual `chcon` commands are required.

#### 2) Deploy the container

Download a ready-made compose file (or copy it manually): Browse: [repo
view](https://github.com/osghtc/networking/blob/master/docs/perfsonar/tools_scripts/docker-compose.testpoint.yml)

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

Manage pSConfig files under `/opt/perfsonar-tp/psconfig` on the host; they are consumed by the container at `/etc/perfsonar/psconfig`. 

#### 3) Ensure containers restart automatically on reboot (systemd unit for testpoint - REQUIRED)

!!! warning "podman-compose limitation with systemd containers"
    
    The perfSONAR testpoint image runs **systemd internally** and requires the `--systemd=always` flag to function
    correctly. **podman-compose does not support this flag**, which causes containers to crash-loop after reboot with exit
    code 255.
    
    You **must** use the systemd unit approach below instead of relying on compose alone.
    
    Install the provided systemd units to manage containers with proper systemd support:
    
```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-units.sh \
    -o /tmp/install-systemd-units.sh
chmod 0755 /tmp/install-systemd-units.sh

# Install testpoint-only systemd unit
/tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp

# Enable and start now
systemctl enable --now perfsonar-testpoint.service

# Verify service and containers
systemctl status perfsonar-testpoint.service --no-pager
podman ps
```

??? info "Notes on podman/systemd"

    - The service uses `podman run --systemd=always` to enable proper systemd operation inside the container
    - The compose file is kept for reference but not used by the systemd units
    - If you need to update container configuration, edit the systemd unit file directly: `/etc/systemd/system/perfsonar-testpoint.service`
    - After editing the unit file, reload and restart: `systemctl daemon-reload && systemctl restart perfsonar-testpoint.service`

Jump to [Step 6](#step-6-configure-and-enroll-in-psconfig) below.

---

### Option B — Testpoint + Let's Encrypt (shared Apache and certs)

This mode runs two containers (`perfsonar-testpoint` and `certbot`) and bind-mounts the following host paths so Apache
content and certificates persist on the host and are shared between containers:

- `/opt/perfsonar-tp/psconfig` → `/etc/perfsonar/psconfig` — perfSONAR configuration

- `/var/www/html` → `/var/www/html` — Apache webroot (shared for HTTP-01 challenges)

- `/etc/apache2` → `/etc/apache2` — Apache configuration (for SSL certificate patching)

- `/etc/letsencrypt` → `/etc/letsencrypt` — Let's Encrypt certificates and state

#### 1) Seed required host directories (REQUIRED before first compose up)

**Why seed?** The perfsonar-testpoint container requires baseline configuration files from the image to be present on
the host filesystem. Without seeding, the bind-mounted directories would be empty, causing Apache and perfSONAR services
to fail.

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

??? info "Seed script details"

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
    
    If SELinux is enforcing, the `:Z` and `:z` options in the compose files will cause Podman to relabel the host paths when
    containers start. No manual `chcon` commands are required.
    
    **SELinux Volume Labels:**
    
    - `:Z` (uppercase) - Exclusive access. Podman creates a unique SELinux label for this volume that only this specific container can access. Use for volumes that should not be shared between containers.
    - `:z` (lowercase) - Shared access. Podman uses a shared SELinux label that multiple containers can access. Use for volumes that need to be accessed by multiple containers.
    In our compose files:
    - `/etc/letsencrypt:/etc/letsencrypt:Z` - Exclusive to testpoint container
    - `/var/www/html:/var/www/html:z` - Shared between testpoint and certbot containers
    - `/etc/apache2:/etc/apache2:Z` - Exclusive to testpoint container

#### 2) Deploy the testpoint with automatic SSL patching (recommended)

**Prerequisites:** Ensure `/opt/perfsonar-tp/tools_scripts` exists from Step 2 (bootstrap):

```bash
ls -la /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh
```

If the file is missing, run the Step 2 bootstrap first:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
    | bash -s -- /opt/perfsonar-tp
```

Deploy using the compose file with automatic Apache SSL certificate patching. This approach uses an entrypoint wrapper
that auto-discovers Let's Encrypt certificates on container startup and automatically patches the Apache configuration.

Download the auto-patching compose file:

```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/docker-compose.testpoint-le-auto.yml \
    -o /opt/perfsonar-tp/docker-compose.yml
```

??? note "The SERVER_FQDN use is optional"

    **Note:** The `SERVER_FQDN` environment variable is **optional**. The entrypoint wrapper will auto-discover certificates in `/etc/letsencrypt/live` 
    and use the first one found. Only set `SERVER_FQDN` if you have multiple certificates and need to specify which one to use.

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

At this point, the testpoint is running with self-signed certificates. The certbot container is also running but won't
renew anything until you obtain the initial certificates.

#### Ensure containers restart automatically on reboot (systemd units for testpoint & certbot - REQUIRED)

!!! warning "podman-compose limitation with systemd containers"
    
    The perfSONAR testpoint image runs **systemd internally** and requires the `--systemd=always` flag to function
    correctly. **podman-compose does not support this flag**, which causes containers to crash-loop after reboot with exit
    code 255.
    
    You **must** use the systemd unit approach below instead of relying on compose alone.
    
    Install and enable the systemd units so containers start on boot with proper systemd support:
    
```bash
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-units.sh \
    -o /tmp/install-systemd-units.sh
chmod 0755 /tmp/install-systemd-units.sh

# Install both testpoint and certbot systemd units
/tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp --with-certbot

# Enable and start services
systemctl enable --now perfsonar-testpoint.service perfsonar-certbot.service

# Verify services
systemctl status perfsonar-testpoint.service perfsonar-certbot.service --no-pager
podman ps
```

#### 3) Obtain your first Let's Encrypt certificate (one-time)

Use Certbot in standalone mode to obtain the initial certificates. The perfsonar-testpoint image is patched to NOT
listen on port 80, so port 80 is available for Certbot's HTTP-01 challenge.

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

??? info "Certbot command explained"
    
    **Podman options:**
    
    - `--rm` - Remove container after it exits
    - `--net=host` - Use host network (allows binding port 80)
    - `-v /etc/letsencrypt:/etc/letsencrypt:Z` - Mount certificate storage with exclusive SELinux label
    - `-v /var/www/html:/var/www/html:Z` - Mount webroot for HTTP-01 challenge

    **Certbot options:**

    - `certonly` - Obtain certificate only, don't install it
    - `--standalone` - Run standalone HTTP server on port 80 for ACME HTTP-01 challenge
    - `--agree-tos` - Agree to Let's Encrypt Terms of Service
    - `--non-interactive` - Don't prompt for input (required for automation)
    - `-d <FQDN>` - Domain name(s) for the certificate (repeat for each domain/SAN)
    - `-m <EMAIL>` - Email for renewal notifications and account recovery

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

**Automatic Container Restart:** After each successful certificate renewal, certbot automatically runs
a deploy hook script (`certbot-deploy-hook.sh`) that gracefully restarts the `perfsonar-testpoint`
container. This ensures the new certificates are loaded without manual intervention. The deploy hook
uses the mounted Podman socket (`/run/podman/podman.sock`) to communicate with the host's container
runtime via the Podman REST API (using Python, since the `podman` CLI is not present in the certbot
image). On EL9 hosts with SELinux enforcing, the certbot service requires `security_opt: label=disable`
to access the socket.

**Note:** The certbot container in this setup uses **host networking mode** (via `network_mode: host` in the compose
file) so it can bind directly to port 80 for HTTP-01 challenges during renewals. This works because the perfsonar-
testpoint Apache is patched to NOT listen on port 80. Both containers share the host network namespace without conflict.

Test renewal with a dry-run:

```bash
podman exec certbot certbot renew --dry-run
```

If successful, certificates will auto-renew before expiry, and the testpoint will be automatically restarted to load the
new certificates. You can verify this behavior by checking the certbot logs after a renewal:

```bash
podman logs certbot 2>&1 | grep -A5 "deploy hook"

```

---

??? info "Alternative: Manual SSL Patching (without automatic entrypoint wrapper)"
    
    If you prefer not to use the automatic patching entrypoint wrapper, you can use the standard compose file and manually
    patch the Apache SSL configuration after obtaining certificates.
    
    1. Use `docker-compose.testpoint-le.yml` instead of `docker-compose.testpoint-le-auto.yml`
    1. After obtaining Let's Encrypt certificates, run:
    ```bash
    /opt/perfsonar-tp/tools_scripts/patch_apache_ssl_for_letsencrypt.sh <SERVER_FQDN>
    ```
    1. Reload Apache in the running container:
    ```bash
    podman exec perfsonar-testpoint apachectl -k graceful
    ```

This approach requires manual intervention after initial certificate issuance and any time the container is recreated.
The automatic approach (using the entrypoint wrapper) eliminates this manual step.

??? warning "Troubleshooting: Container fails with 'executable file not found' error"
    
    **Error:** `Error: unable to start container: crun: executable file /opt/perfsonar-tp/tools_scripts/testpoint-
    entrypoint-wrapper.sh not found`
    
    **Cause:** The `/opt/perfsonar-tp/tools_scripts` directory doesn't exist or the entrypoint wrapper wasn't downloaded.
    
    **Fix:** Run the Step 2 bootstrap script to fetch all helper scripts:
    
    ```bash
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh \
        | bash -s -- /opt/perfsonar-tp
    
    ```
    
    Then verify the entrypoint wrapper exists:
    
    ```bash
    ls -la /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh
    
    ```
    
    If you've already started the container and it failed, remove it before retrying:
    
    ```bash
    
    podman-compose down
    podman-compose up -d
    
    ```
    
---

## Step 6 – Configure and Enroll in pSConfig

!!! note "Skip this step if you used the orchestrator (Path A)"
    
    The orchestrator automates pSConfig enrollment. If you ran it in Step 2, skip to [Step 7](#step-7-register-and-configure-with-wlcgosg).
    
We need to enroll your testpoint with the OSG/WLCG pSConfig service so tests are auto-configured. Use the "auto URL" for each FQDN you expose for 
perfSONAR (one or two depending on whether you split latency/throughput by hostname).
    
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

Automation tip: derive FQDNs from your configured IPs (PTR lookup) and enroll automatically. Review the list before
applying.

```bash
# Dry run only (show planned URLs):
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -n

# Typical usage (podman):
/opt/perfsonar-tp/tools_scripts/perfSONAR-auto-enroll-psconfig.sh -v

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

## Step 7 – Register and Configure with WLCG/OSG

1. **OSG/WLCG registration workflow:**

    ??? info "Registration steps and portals"
        
        - Register the host in [OSG topology](https://topology.opensciencegrid.org/host).
        - Create or update a [GGUS](https://ggus.eu/) ticket announcing the new measurement point.
        - In [GOCDB](https://goc.egi.eu/portal/), add the service endpoint
                `org.opensciencegrid.crc.perfsonar-testpoint` bound to this host.

1. **Document memberships:**

    Update your site wiki or change log with assigned mesh names, feed  URLs, and support contacts.

1. **Update Lookup Service registration inside the container:**

    Use the helper script to edit `/etc/perfsonar/lsregistrationdaemon.conf` inside the running `perfsonar-testpoint`
    container and restart the daemon only if needed. Install and run examples below, pick which type you want (root shell):

    ```bash
    # Preview changes only (uses the copy from /opt/perfsonar-tp/tools_scripts)
    /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh update \
        --dry-run --site-name "Acme Co." --project WLCG \
        --admin-email admin@example.org --admin-name "pS Admin"

    # Restore previously saved settings from the Prerequisites extract (if you saved a restore script earlier)
    bash /root/restore-lsreg.sh

    # Apply new settings and restart the daemon inside the container
    /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh create \
        --site-name "Acme Co." --domain example.org --project WLCG --project OSG \
        --city Berkeley --region CA --country US --zip 94720 \
        --latitude 37.5 --longitude -121.7469 \
        --admin-name "pS Admin" --admin-email admin@example.org
    ```

1. **Automatic image updates and safe restarts**

    Keep containers current and only restart them when their image actually changes.

    ??? info "Auto-update for compose-managed containers"
        
        Since these containers are managed by `podman-compose`, we use a different approach than systemd-managed containers.
        Create a simple script and systemd timer to periodically pull new images and restart containers if updates are available.
        
        1. Create an update script:

            ```bash
            cat > /usr/local/bin/perfsonar-auto-update.sh << 'EOF'
            #!/bin/bash
            # perfsonar-auto-update.sh - Check for and apply container image updates
            set -e

            COMPOSE_DIR="/opt/perfsonar-tp"
            LOGFILE="/var/log/perfsonar-auto-update.log"

            log() {
                echo "$(date -Iseconds) $*" | tee -a "$LOGFILE"
            }

            cd "$COMPOSE_DIR"

            log "Checking for image updates..."

            # Pull latest images
            if podman-compose pull 2>&1 | tee -a "$LOGFILE" | grep -q "Downloaded newer image"; then
                log "New images found - recreating containers..."
                podman-compose up -d
                log "Containers updated successfully"
            else
                log "No updates available"
            fi
            EOF

            chmod +x /usr/local/bin/perfsonar-auto-update.sh
            ```

        1. Create a systemd service:

            ```bash

            cat > /etc/systemd/system/perfsonar-auto-update.service << 'EOF'
            [Unit]
            Description=perfSONAR Container Auto-Update
            After=network-online.target

            [Service]
            Type=oneshot
            ExecStart=/usr/local/bin/perfsonar-auto-update.sh

            [Install]
            WantedBy=multi-user.target
            EOF
            ```

        1. Create a systemd timer (runs daily at 3 AM):

            ```bash
            cat > /etc/systemd/system/perfsonar-auto-update.timer << 'EOF'

            [Unit]
            Description=perfSONAR Container Auto-Update Timer

            [Timer]
            OnCalendar=daily
            RandomizedDelaySec=1h
            Persistent=true

            [Install]
            WantedBy=timers.target
            EOF
            ```

        1. Enable and start the timer:

            ```bash
            systemctl daemon-reload
            systemctl enable --now perfsonar-auto-update.timer
            ```

        1. Verify the timer is active:

            ```bash
            systemctl list-timers perfsonar-auto-update.timer
            ```

        1. Test manually (optional):

            ```bash
            systemctl start perfsonar-auto-update.service
            journalctl -u perfsonar-auto-update.service -n 50
            ```

        1. Monitor the update log:

            ```bash
            tail -f /var/log/perfsonar-auto-update.log
            ```

This approach ensures containers are updated only when new images are available, minimizing unnecessary restarts while
keeping your deployment current.

---

## Step 8 – Post-Install Validation

Perform these checks before handing the host over to operations:

1. **System services:**

    ??? info "Verify Podman runtime and containers"
        
        ```bash
        # Check Podman service is available
        systemctl status podman

        # Verify containers are managed by compose
        cd /opt/perfsonar-tp && podman-compose ps

        # Alternative: check containers directly
        podman ps --filter name=perfsonar
        ```

    Ensure Podman is active and containers are running.

1. **Container health:**

    ??? info "Check container status and logs"
        
        ```bash
        # Check all containers are running and healthy
        podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

        # Check perfsonar-testpoint logs for errors
        podman logs perfsonar-testpoint --tail 50

        # If using Let's Encrypt, check certbot logs
        podman logs certbot --tail 20 2>/dev/null || echo "Certbot container not present (testpoint-only mode)"

        # Verify services inside container are running
        podman exec perfsonar-testpoint systemctl status apache2 psconfig-pscheduler-agent --no-pager
        ```

1. **Network path validation:**

    ??? info "Test network connectivity and routing"
        
        Test throughput to a remote testpoint (run from inside the container):
        ```bash
        podman exec -it perfsonar-testpoint pscheduler task throughput --dest <remote-testpoint>
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

        # Check fail2ban status (if installed in Step 4)
        if command -v fail2ban-client >/dev/null 2>&1; then
            fail2ban-client status
        else
            echo "fail2ban not installed (optional)"
        fi

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

1. **LetsEncrypt certificate check:**

    ??? info "Verify certificate validity"
        
        ```bash
        # Check certificate via HTTPS connection
        echo | openssl s_client -connect <SERVER_FQDN>:443 -servername <SERVER_FQDN> 2>/dev/null | openssl x509 -noout -dates -issuer

        # Alternative: Check certificate files directly
        sudo openssl x509 -in /etc/letsencrypt/live/<SERVER_FQDN>/cert.pem -noout -dates -issuer
        ```

    Ensure the issuer is Let's Encrypt and the validity period is acceptable. This check only applies if you configured Let's Encrypt in Step 3.

1. **Reporting:**

    ??? info "Run perfSONAR diagnostic reports"
        
        Run the perfSONAR troubleshoot command from inside the container and send outputs to operations:
        ```bash
        podman exec -it perfsonar-testpoint pscheduler troubleshoot
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

## Troubleshooting

### Container Issues

??? failure "Container won't start or exits immediately"
    
    **Symptoms:** `podman ps` shows no running containers, or container exits shortly after starting.
    
    **Diagnostic steps:**
    
    ```bash
    # Check container logs
    podman logs perfsonar-testpoint

    # Check for systemd initialization errors
    podman logs perfsonar-testpoint 2>&1 | grep -i "failed\|error"

    # Verify compose file syntax
    cd /opt/perfsonar-tp
    podman-compose config

    ```

    **Common causes:**

    - Missing entrypoint wrapper: Ensure `/opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh` exists
    - SELinux denials: Check `ausearch -m avc -ts recent` and consider temporarily setting to permissive mode for testing
    - Incorrect bind-mount paths: Verify all host directories exist and have correct permissions
    - Cgroup issues: Ensure `cgroupns: private` is set and no manual cgroup bind-mounts exist

??? failure "Container won't start or exits immediately"
    
    **Symptoms:** `podman ps` shows no running containers, or container exits shortly after starting.
    
    **Diagnostic steps:**
    
    ```bash
    # Check container logs
    podman logs perfsonar-testpoint

    # Check for systemd initialization errors
    podman logs perfsonar-testpoint 2>&1 | grep -i "failed\|error"

    # Verify compose file syntax
    cd /opt/perfsonar-tp
    podman-compose config

    ```

    **Common causes:**

    - Missing entrypoint wrapper: Ensure `/opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh` exists
    - SELinux denials: Check `ausearch -m avc -ts recent` and consider temporarily setting to permissive mode for testing
    - Incorrect bind-mount paths: Verify all host directories exist and have correct permissions
    - Cgroup issues: Ensure `cgroupns: private` is set and no manual cgroup bind-mounts exist

??? failure "Container crashes after reboot with exit code 255"
    
    **Symptoms:** Containers run fine when started manually but crash-loop after host reboot. Logs show repeated restarts
    with exit code 255.
    
    **Cause:** The perfSONAR testpoint image runs systemd internally but podman-compose doesn't support the
    `--systemd=always` flag required for proper systemd operation in containers.
    
    **Diagnostic steps:**
    
    ```bash
    # Check container status
    podman ps -a

    # Check systemd service status
    systemctl status perfsonar-testpoint.service

    # View recent container logs
    podman logs perfsonar-testpoint --tail 100

    # Check if using compose-based service (BAD)
    grep -A5 "ExecStart" /etc/systemd/system/perfsonar-testpoint.service
    ```

    **Solution:**

    Replace the compose-based systemd service with proper systemd units that use `podman run --systemd=always`:

    ```bash
    # Stop and disable old service
    systemctl stop perfsonar-testpoint.service
    systemctl disable perfsonar-testpoint.service

    # Install new systemd units
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-units.sh \
        -o /tmp/install-systemd-units.sh
    chmod 0755 /tmp/install-systemd-units.sh

    # For testpoint only:
    /tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp

    # For testpoint + certbot:
    /tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp --with-certbot

    # Enable and start
    systemctl enable --now perfsonar-testpoint.service

    # If using certbot:
    systemctl enable --now perfsonar-certbot.service

    # Verify containers are running
    podman ps
    curl -kI https://127.0.0.1/
    ```

    **Verification:**

    After installing the new units, the testpoint should:
    - Start successfully on boot
    - Run systemd properly inside the container
    - Maintain state across reboots
    - Show "Up" status in `podman ps` (not "Exited" or crash-looping)

??? failure "Certbot service fails with 'Unable to open config file' error"
    
    **Symptoms:** `perfsonar-certbot.service` fails immediately after starting with exit code 2. Logs show: `certbot: error:
    Unable to open config file: trap exit TERM; while...`
    
    **Cause:** The certbot container image has a built-in entrypoint that expects certbot commands directly. When using a
    shell loop for renewal, the entrypoint tries to parse the shell command as a certbot config file, causing this error.
    
    **Diagnostic steps:**
    
    ```bash
    # Check certbot service status
    systemctl status perfsonar-certbot.service

    # View detailed logs
    journalctl -u perfsonar-certbot.service -n 50

    # Check for the error in logs
    journalctl -u perfsonar-certbot.service | grep "Unable to open config file"

    # Verify service file configuration
    grep -A5 "ExecStart" /etc/systemd/system/perfsonar-certbot.service
    ```

    **Solution:**

    The certbot service needs two flags:
    - `--systemd=always` for proper systemd integration and reboot persistence
    - `--entrypoint=/bin/sh` to override the built-in entrypoint

    Re-run the installation script to get the fixed version:

    ```bash
    # Stop current service
    systemctl stop perfsonar-certbot.service

    # Download and install updated systemd units
    curl -fsSL \
        https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-units.sh \
        -o /tmp/install-systemd-units.sh
    chmod 0755 /tmp/install-systemd-units.sh

    # Install with certbot support
    /tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp --with-certbot

    # Start the fixed service
    systemctl daemon-reload
    systemctl start perfsonar-certbot.service

    # Verify it's running
    systemctl status perfsonar-certbot.service
    podman ps | grep certbot
    ```

    **Expected result:** The certbot container should be running (not exiting) and the service should be in "active (running)" state.

??? failure "SELinux denials blocking container operations"
    
    **Symptoms:** Container starts but services fail, permission denied errors in logs.
    
    **Diagnostic steps:**
    
    ```bash
    
    # Check for recent SELinux denials
    ausearch -m avc -ts recent

    # Temporarily set to permissive for testing
    setenforce 0

    # Test if issue resolves, then check audit log
    ausearch -m avc -ts recent > /tmp/selinux-denials.txt

    ```

    **Solutions:**

    - Verify volume labels are correct (`:Z` for exclusive, `:z` for shared)
    - Recreate containers to reapply SELinux labels: `podman-compose down && podman-compose up -d`
    - If persistent issues, consider creating custom SELinux policy or running in permissive mode

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
    - Reapply configuration: `/opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --yes`
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
    /opt/perfsonar-tp/tools_scripts/check-perfsonar-dns.sh

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

    - Verify deploy hook script exists and is executable: `/opt/perfsonar-tp/tools_scripts/certbot-deploy-hook.sh`
    - Ensure deploy hook is mounted in container at: `/etc/letsencrypt/renewal-hooks/deploy/certbot-deploy-hook.sh`
    - Verify Podman socket is mounted in certbot container: `podman exec certbot ls /run/podman/podman.sock`
    - Verify `security_opt: label=disable` is set on the certbot service in `docker-compose.yml` (required on EL9/SELinux hosts)
    - Check deploy hook logs: `journalctl -u perfsonar-certbot.service | grep deploy`
    - Manually restart testpoint after renewals if deploy hook fails: `podman restart perfsonar-testpoint`

    **Note:** Certbot automatically executes scripts in `/etc/letsencrypt/renewal-hooks/deploy/` when certificates are
    renewed. The deploy hook uses the Podman REST API via Python (not the `podman` CLI, which is absent from the Alpine-based certbot image).

### perfSONAR Service Issues

??? failure "perfSONAR services not running"
    
    **Symptoms:** Web interface not accessible, tests not running.
    
    **Diagnostic steps:**
    
    ```bash
    # Check service status inside container
    podman exec perfsonar-testpoint systemctl status apache2
    podman exec perfsonar-testpoint systemctl status pscheduler-ticker
    podman exec perfsonar-testpoint systemctl status owamp-server

    # Check for errors in service logs
    podman exec perfsonar-testpoint journalctl -u apache2 -n 50
    podman exec perfsonar-testpoint journalctl -u pscheduler-ticker -n 50

    ```

    **Solutions:**

    - Restart services inside container: `podman exec perfsonar-testpoint systemctl restart apache2`
    - Check Apache SSL configuration was patched correctly
    - Verify certificates are in place: `ls -la /etc/letsencrypt/live/`
    - Restart container: `podman restart perfsonar-testpoint`

### Auto-Update Issues

??? failure "Auto-update not working"
    
    **Symptoms:** Containers not updating despite new images available.
    
    **Diagnostic steps:**
    
    ```bash
    # Check timer status
    systemctl status perfsonar-auto-update.timer
    systemctl list-timers perfsonar-auto-update.timer

    # Check service logs
    journalctl -u perfsonar-auto-update.service -n 100

    # Check update log
    tail -50 /var/log/perfsonar-auto-update.log

    # Manually test update
    systemctl start perfsonar-auto-update.service

    ```

    **Solutions:**

    - Enable timer if not active: `systemctl enable --now perfsonar-auto-update.timer`
    - Verify script exists and is executable: `ls -la /usr/local/bin/perfsonar-auto-update.sh`
    - Check podman-compose is installed and working
    - Review script for errors and update if needed

### General Debugging Tips

??? tip "Useful debugging commands"
    
    **Container management:**
    
    ```bash
    # View all containers (running and stopped)
    podman ps -a

    # View container resource usage
    podman stats

    # Enter container for interactive debugging
    podman exec -it perfsonar-testpoint /bin/bash

    # View compose configuration
    cd /opt/perfsonar-tp && podman-compose config

    ```

    **Networking:**

    ```bash
    # Check which process is listening on a port
    ss -tlnp | grep <port>

    # Test connectivity to remote testpoint
    ping <remote-ip>
    traceroute <remote-ip>

    # Check nftables rules
    nft list ruleset
    ```

??? note "What to include when reporting issues via email"

    To help us diagnose install problems quickly, please include:

    - Host details: OS version (e.g., `cat /etc/os-release`), kernel (`uname -r`), and whether this is testpoint or toolkit.
    - Script/log context: which script/step failed and the exact command you ran.
    - Timestamps: approximate time of failure and timezone.
    - Outputs/logs: relevant console output and excerpts from `journalctl -u podman -n 200`, `tail -200 /var/log/perfSONAR-install-nftables.log`, and any script-specific log mentioned in the error.
    - Network state: `ip -br addr`, `ip rule show`, `nmcli connection show`, and whether port 80/443 should be open externally.
    - Certificates (if LE): whether port 80 was reachable from the Internet and the contents of `/var/log/letsencrypt/letsencrypt.log` around the failure.
    - Contact info: your name, site, and a callback email.

    Send reports to your usual perfSONAR support contact or project mailing list with the subject prefix `[perfSONAR install issue]`.

    **Logs:**

    ```bash
    # System journal for container runtime
    journalctl -u podman -n 100

    # All logs from a container
    podman logs perfsonar-testpoint --tail=100

    # Follow logs in real-time
    podman logs -f perfsonar-testpoint
    ```

---
