# perfSONAR Toolkit Installation Guide - Adaptation Plan

## Overview
This document outlines the changes needed to adapt `install-perfsonar-testpoint.md` (container-based) into `install-perfsonar-toolkit.md` (RPM-based).

## Key Differences: Testpoint vs Toolkit

### Testpoint (Container-based)
- Lightweight deployment using podman/docker containers
- No local web UI or measurement archive
- Central archiving (measurements stored remotely)
- Container image updates via pull/restart
- perfSONAR services run inside containers
- Suitable for simple measurement points

### Toolkit (RPM-based)
- Full-featured deployment via RPM packages
- Includes local web UI at https://hostname/toolkit
- Local measurement archive (OpenSearch/Logstash)
- Package updates via dnf/yum
- perfSONAR services run as native systemd services
- Suitable for sites needing local data storage and web interface

## Sections to Adapt

### Title and Introduction (Lines 1-43)
**Changes:**
- Change title to "Installing a perfSONAR Toolkit for WLCG/OSG"
- Update intro to describe RPM-based installation
- Mention key features: local web UI, measurement archive
- Reference upstream docs: https://docs.perfsonar.net/install_el.html

**Keep:**
- Prerequisites and planning section
- Hardware/network/operational contacts info
- Existing perfSONAR configuration backup guidance

### Step 1 – Install and Harden EL9 (Lines 45-86)
**Changes:**
- Minimal changes - mostly identical to testpoint
- OS hardening steps are the same

**Keep:**
- EL9 minimal install instructions
- Hostname and time sync setup
- Service disabling (firewalld, NetworkManager-wait-online, rsyslog)

### Step 2 – Choose Your Deployment Path (Lines 88-182)

**MAJOR CHANGES NEEDED:**

#### Remove:
- Orchestrator option (testpoint-specific, uses containers)
- podman/podman-compose/podman-docker from package list
- Container-specific tools

#### Add:
- **perfSONAR Toolkit RPM Installation Steps** (from https://docs.perfsonar.net/install_el.html):
  
  1. Configure DNF repositories:
     ```bash
     dnf install epel-release
     dnf config-manager --set-enabled crb
     dnf install http://software.internet2.edu/rpms/el9/x86_64/latest/packages/perfsonar-repo-0.11-1.noarch.rpm
     dnf clean all
     ```
  
  2. Install perfSONAR Toolkit bundle:
     ```bash
     dnf install perfsonar-toolkit
     ```
     Note: This automatically includes:
     - perfsonar-toolkit-security (firewall + fail2ban)
     - perfsonar-toolkit-sysctl (tuning)
     - perfsonar-toolkit-systemenv-testpoint (auto-update, logging)
  
  3. Run post-install configuration:
     ```bash
     /usr/lib/perfsonar/scripts/configure_sysctl
     /usr/lib/perfsonar/scripts/configure_firewall install
     ```

#### Keep (with adaptations):
- Base package installation for helper scripts:
  ```bash
  dnf -y install jq curl tar gzip rsync bind-utils \
      nftables python3 iproute iputils procps-ng sed grep gawk
  ```
  (Note: fail2ban, policycoreutils-python-utils already in perfsonar-toolkit-security)

- Bootstrap helper scripts section (unchanged - scripts still useful for PBR, DNS checks, registration updates)

### Step 3 – Configure Policy-Based Routing (Lines 185-324)
**Changes:**
- NO MAJOR CHANGES - PBR is deployment-agnostic
- Scripts work the same for both testpoint and toolkit

**Keep:**
- All PBR configuration and perfSONAR-pbr-nm.sh usage
- Gateway detection and config generation
- In-place vs full rebuild modes
- DNS forward/reverse validation

### Step 4 – Configure nftables, SELinux, and Fail2Ban (Lines 326-422)
**Changes:**
- Note that perfsonar-toolkit-security already installed fail2ban
- Note that perfsonar-toolkit already ran configure_firewall
- Emphasize this step is for **additional** customization or re-running after changes

**Keep:**
- perfSONAR-install-nftables.sh usage for custom rules
- SSH allow-list management
- SELinux and fail2ban verification commands

**Add note:**
```markdown
!!! info "Toolkit automatic security hardening"
    
    The perfsonar-toolkit bundle automatically installs and configures:
    - nftables rules via `/usr/lib/perfsonar/scripts/configure_firewall`
    - fail2ban with perfSONAR jails
    - SELinux policies (if enforcing)
    
    This step is only needed if you want to customize beyond the defaults or
    integrate with the OSG helper scripts for PBR-derived SSH access control.
```

### Step 5 – Deploy perfSONAR (Lines 424-814)

**MAJOR CHANGES - COMPLETE REWRITE:**

#### Remove entire container deployment section:
- podman-compose commands
- Container image pulling
- Option A/B (testpoint vs Let's Encrypt containers)
- Seeding host directories
- Systemd units for containers

#### Replace with:
```markdown
## Step 5 – Start and Verify perfSONAR Services

The perfSONAR Toolkit installation automatically enables and starts all required services.
Verify they are running:

```bash
systemctl status pscheduler-scheduler
systemctl status pscheduler-runner
systemctl status pscheduler-archiver
systemctl status pscheduler-ticker
systemctl status psconfig-pscheduler-agent
systemctl status owamp-server
systemctl status perfsonar-lsregistrationdaemon
```

If any service is not running, start it:

```bash
systemctl start <service-name>
```

All services are configured to start automatically on boot.

### Access the Web Interface

The perfSONAR Toolkit provides a local web interface for configuration and monitoring:

1. Open a browser and navigate to: `https://<your-hostname>/toolkit`

2. Complete first-time setup:
   - Set administrator username and password
   - Configure administrative information (site name, location, contacts)
   - Review and adjust test settings
   - Configure measurement archive settings (if using central archiving)

3. Web UI features:
   - Dashboard with measurement results
   - Test configuration and scheduling
   - Administrative information management
   - Service health monitoring
   - Archive configuration

See upstream documentation: https://docs.perfsonar.net/install_config_first_time.html

### Configure Automatic Updates

The perfsonar-toolkit bundle enables automatic updates by default. Verify:

```bash
systemctl status dnf-automatic.timer
```

To manually check for updates:

```bash
dnf check-update perfsonar\*
```

To apply updates manually:

```bash
dnf update perfsonar\*
systemctl restart pscheduler-scheduler pscheduler-runner pscheduler-archiver pscheduler-ticker
```

**Note:** Updates are applied automatically overnight. Services are restarted as needed.
```

### Step 6 – Configure and Enroll in pSConfig (Lines 815-863)
**Changes:**
- Adapt commands from container context to native filesystem

**Before (testpoint - container):**
```bash
podman exec perfsonar-testpoint ls -la /etc/perfsonar/psconfig
```

**After (toolkit - native):**
```bash
ls -la /etc/perfsonar/psconfig
```

**Keep:**
- Concept of mesh enrollment and pSConfig feeds
- File placement in `/etc/perfsonar/psconfig/pscheduler.d/`
- Agent restart commands (adapt from container to native):
  - Before: `podman exec perfsonar-testpoint systemctl restart psconfig-pscheduler-agent`
  - After: `systemctl restart psconfig-pscheduler-agent`

**Add:**
- Web UI option: "Alternatively, configure pSConfig templates via the web interface at https://<hostname>/toolkit/admin?view=psconfig"

### Step 7 – Register and Configure with WLCG/OSG (Lines 865-1008)
**Changes:**
- Adapt lsregistration script commands from container to native

**Before (container):**
```bash
podman exec perfsonar-testpoint vi /etc/perfsonar/lsregistrationdaemon.conf
```

**After (native):**
```bash
vi /etc/perfsonar/lsregistrationdaemon.conf
```

OR use web UI:
```markdown
Configure via web interface: https://<hostname>/toolkit/admin?view=host
```

**Before (container - using helper script):**
```bash
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh create ...
```

**After (native - adapt script or use web UI):**
```markdown
!!! tip "Use Web UI for registration"
    
    The easiest way to update registration information is via the Toolkit web interface:
    1. Navigate to https://<hostname>/toolkit/admin?view=host
    2. Fill in site name, location, contacts, projects
    3. Save changes - the lsregistrationdaemon restarts automatically

Alternatively, edit `/etc/perfsonar/lsregistrationdaemon.conf` directly and restart:
```bash
systemctl restart perfsonar-lsregistrationdaemon
```
```

**Keep:**
- OSG/WLCG registration workflow (topology, GGUS, GOCDB)
- Document memberships guidance
- Auto-update guidance (already handled by dnf-automatic)

**Remove:**
- Container-specific auto-update script and systemd timer (toolkit uses dnf-automatic)

### Step 8 – Post-Install Validation (Lines 1010-end)
**Changes:**
- Adapt all validation commands from container to native

**Container commands to adapt:**
```bash
# Before (container)
podman ps
podman logs perfsonar-testpoint
podman exec perfsonar-testpoint systemctl status apache2
podman exec -it perfsonar-testpoint pscheduler task throughput --dest <remote>

# After (native)
systemctl status pscheduler-scheduler pscheduler-runner
journalctl -u pscheduler-scheduler -n 50
systemctl status apache2 --no-pager
pscheduler task throughput --dest <remote>
```

**Add:**
- Web UI health check: "Verify web interface is accessible: https://<hostname>/toolkit"
- Archive validation: "Check measurement archive contains data: https://<hostname>/toolkit/archive"

**Keep:**
- Network path validation (unchanged)
- Security posture checks (nftables, fail2ban, SELinux)
- Certificate checks (adapt for native Apache, not container)

## Additional Sections to Add

### When to Choose Toolkit vs Testpoint

Add a new section early in the document (after prerequisites):

```markdown
## Choosing Between Toolkit and Testpoint

### Use perfSONAR Toolkit (this guide) if you need:
- Local web interface for configuration and monitoring
- Local measurement archive (store data on-site)
- Full-featured perfSONAR installation
- Site-specific data retention requirements

### Use perfSONAR Testpoint instead if you prefer:
- Lightweight container-based deployment
- Central archiving (measurements stored remotely)
- Minimal local resource usage
- Container-based update workflow

See [Installing a perfSONAR Testpoint](install-perfsonar-testpoint.md) for container-based deployment.
```

## Helper Scripts Compatibility

### Scripts that work unchanged:
- `perfSONAR-pbr-nm.sh` (PBR configuration)
- `check-perfsonar-dns.sh` (DNS validation)
- `perfSONAR-install-nftables.sh` (custom firewall rules)

### Scripts that need adaptation:
- `perfSONAR-update-lsregistration.sh` - Remove `podman exec` wrapper, edit files directly
  - OR recommend web UI instead for toolkit deployments

### Scripts not applicable to toolkit:
- `perfSONAR-orchestrator.sh` (testpoint-specific, uses containers)
- `docker-compose.*.yml` files (container-specific)
- `seed_testpoint_host_dirs.sh` (container-specific)
- `testpoint-entrypoint-wrapper.sh` (container-specific)
- `install-systemd-units.sh` (container-specific)
- `perfsonar-auto-update.sh` (container-specific - toolkit uses dnf-automatic)

## Summary of Effort

**Major rewrites:**
- Step 2: Replace orchestrator/container prep with RPM installation
- Step 5: Replace container deployment with service verification and web UI setup

**Moderate adaptations:**
- Step 4: Add note about automatic security hardening in toolkit
- Step 6: Change container commands to native filesystem/service commands
- Step 7: Change container exec commands to native, add web UI options
- Step 8: Adapt validation commands from container to native services

**Minimal/no changes:**
- Step 1: Install and harden EL9 (identical)
- Step 3: Configure PBR (identical)

## Next Steps

1. Create `install-perfsonar-toolkit.md` with adaptations outlined above
2. Add cross-references between testpoint and toolkit guides
3. Update landing page (`quick-deploy/landing.md` or similar) to list both options
4. Test build site to verify Markdown rendering
5. Consider creating comparison table in shared documentation
