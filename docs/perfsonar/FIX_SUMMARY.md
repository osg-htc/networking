# perfSONAR Testpoint Container Restart Fix - Summary

## Problem

After a host reboot, podman-compose containers for perfSONAR testpoint did not restart automatically because there was
no systemd service to manage them. Additionally, the deployed docker-compose.yml configuration had issues that caused
the testpoint container to enter a restart loop.

## Solutions Implemented

### 1. Created Systemd Service for Automatic Restart

**File**: `/etc/systemd/system/perfsonar-testpoint.service`

A systemd service unit was created to manage the podman-compose containers and ensure they start automatically on boot.

**Key features**:

- Type: oneshot with RemainAfterExit

- Starts after network-online.target

- Runs `podman-compose up -d` on start

- Runs `podman-compose down` on stop

- Automatic restart on failure

- Enabled by default to start on boot

**Status**: Service is now installed, enabled, and running successfully on `/opt/perfsonar-tp`.

### 2. Fixed Container Configuration Issue

**File**: `/opt/perfsonar-tp/docker-compose.yml`

Updated the docker-compose.yml to use the recommended configuration:

- Changed from `cgroupns: private` to `cgroup: host`

- Added required `/sys/fs/cgroup:/sys/fs/cgroup:rw` volume mount

- Added `tty: true` for proper terminal handling

- Removed custom entrypoint wrapper that was causing initialization issues

**Result**: Containers now start properly without entering a restart loop.

### 3. Created Helper Script

**File**: `docs/perfsonar/tools_scripts/install-systemd-service.sh`

A new helper script automates the installation and configuration of the systemd service.

**Features**:

- Root privilege check

- Validates podman-compose is installed

- Validates installation directory exists

- Creates systemd service file

- Reloads systemd and enables service

- Supports custom installation paths

- Provides helpful usage examples

**Usage**:

```bash
sudo bash install-systemd-service.sh [/opt/perfsonar-tp]
```text

### 4. Updated Documentation

**Files Updated**:

- `docs/perfsonar/install-testpoint.md` - Added section on enabling automatic restart

- `docs/perfsonar/tools_scripts/README.md` - Added systemd service installer documentation

- `docs/perfsonar/CONTAINER_RESTART_ISSUE.md` - New troubleshooting guide for container restart issues

**Key additions**:

- Instructions for installing systemd service (manual and automated)

- Useful systemctl commands for managing the service

- Explanation of why systemd service is needed

- Troubleshooting guidance

### 5. Created Ansible Playbook

**File**: `ansible/playbooks/deploy-testpoint-container.yml`

A complete Ansible playbook for automated deployment of perfSONAR testpoint containers.

**Features**:

- Installs required packages (podman, podman-compose, etc.)

- Downloads and installs tools_scripts

- Deploys docker-compose.yml

- Installs and enables systemd service

- Verifies containers are running

- Includes health checks

**Also updated**: `ansible/README.md` with deployment options and usage examples.

## Files Modified in Repository

### New Files Created

1. `docs/perfsonar/tools_scripts/install-systemd-service.sh` - Systemd service installer

1. `ansible/playbooks/deploy-testpoint-container.yml` - Ansible deployment playbook

1. `docs/perfsonar/CONTAINER_RESTART_ISSUE.md` - Troubleshooting guide

### Files Updated

1. `docs/perfsonar/install-testpoint.md` - Added automatic restart section

1. `docs/perfsonar/tools_scripts/README.md` - Added systemd service documentation

1. `ansible/README.md` - Added container deployment section

## Testing and Verification

### Local System (/opt/perfsonar-tp)

✅ Systemd service created and enabled ✅ Containers starting successfully ✅ perfSONAR testpoint responding on
<https://localhost/> ✅ Service will survive reboots (enabled in systemd)

### Verification Commands

```bash
# Check service status
systemctl status perfsonar-testpoint

# Check containers
podman ps

# Test web interface
curl -kSfI https://localhost/

# View service logs
journalctl -u perfsonar-testpoint -f
```

## Next Steps for Deployment

To apply these fixes to other perfSONAR testpoint deployments:

1. **Manual deployment**:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-service.sh \
       -o /tmp/install-systemd-service.sh
   sudo bash /tmp/install-systemd-service.sh /opt/perfsonar-tp

```text

1. **Automated deployment with Ansible**:

   ```bash
   ansible-playbook -i inventory ansible/playbooks/deploy-testpoint-container.yml
```

1. **Fix existing deployments with restart issues**:

- Update docker-compose.yml to recommended configuration

- Restart the perfsonar-testpoint service

## Benefits

✅ **Automatic restart after reboot** - Containers will always start when the host boots ✅ **Service management** -
Standard systemctl commands for start/stop/restart ✅ **Logging** - Centralized logs via journalctl ✅ **Reliability** -
Automatic restart on failure ✅ **Automation** - Ansible playbook for consistent deployments ✅ **Documentation** - Clear
instructions for users

## Conclusion

The perfSONAR testpoint container restart issue has been fully resolved. The systemd service is now managing the
containers, ensuring they restart automatically after host reboots. Documentation and automation scripts have been
updated to help others implement this fix easily.
