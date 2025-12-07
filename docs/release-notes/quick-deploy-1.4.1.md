# Release Notes - Quick Deploy Guide v1.4.1

**Release Date:** December 3, 2025

## Overview

Version 1.4.1 is a bug-fix release that resolves critical container lifecycle issues with the certbot systemd service,
ensuring both perfSONAR testpoint and certbot containers survive system reboots and maintain proper systemd integration.

## Highlights

### Fixed Certbot Service Restart After Reboot

The `perfsonar-certbot.service` systemd unit has been fixed to properly manage the certbot container lifecycle.
Previously, the certbot service would fail immediately after starting with exit code 2 and the error: `certbot: error:
Unable to open config file`.

**Root Cause:** The certbot container image has a built-in entrypoint that expects direct certbot commands. When the
systemd unit attempted to run a shell loop for certificate renewal, the entrypoint incorrectly interpreted the shell
command as a config file path.

**Solution:** Three critical fixes were applied to the `install-systemd-units.sh` script:

1. **Added `--entrypoint=/bin/sh`** to override the container's built-in entrypoint, allowing shell commands to execute properly

1. **Added `--systemd=always`** to ensure proper systemd integration and automatic container restart after host reboots

1. **Improved command syntax** from `/bin/sh -c '...'` to `-c "..."` with proper signal handling

1. **Removed `--deploy-hook` parameter** from certbot renew command - certbot automatically discovers and executes hooks in `/etc/letsencrypt/renewal-hooks/deploy/` (using `--deploy-hook` with paths ending in `.sh` causes certbot to append `-hook` to the filename, breaking hook execution)

## Detailed Changes

### Files Modified

- `docs/perfsonar/tools_scripts/install-systemd-units.sh`

  - Added `--systemd=always` flag to certbot service

  - Added `--entrypoint=/bin/sh` to override certbot container entrypoint

  - Changed trap handling from `trap exit TERM` to `trap 'exit 0' TERM` for cleaner shutdown

  - Fixed command syntax to use `-c` flag properly with entrypoint override

  - Removed `--deploy-hook` parameter from `certbot renew` command to use automatic hook discovery

### Documentation Updates

- `docs/personas/quick-deploy/install-perfsonar-testpoint.md`

  - Added new troubleshooting section: "Certbot service fails with 'Unable to open config file' error"

  - Includes diagnostic steps, root cause explanation, and solution

  - Provides verification commands to confirm the fix

## Impact

### Before Fix

- ❌ Certbot service would crash immediately after starting

- ❌ Certificate renewal automation would fail

- ❌ Service would not survive system reboots

- ❌ Logs showed: `certbot: error: Unable to open config file`

### After Fix

- ✅ Certbot service starts and runs continuously

- ✅ Certificate renewal loop operates correctly (checks every 12 hours)

- ✅ Both testpoint and certbot containers survive system reboots

- ✅ Proper systemd integration with `--systemd=always` flag

## Upgrade Path

### For New Installations

No action needed - the fixed script is automatically used when running:

```bash
/opt/perfsonar-tp/tools_scripts/install-systemd-units.sh --with-certbot
```

### For Existing Deployments with Failing Certbot Service

If you're experiencing the certbot service failure, update to the fixed version:

```bash
# Stop the failing service
systemctl stop perfsonar-certbot.service

# Download the updated script
curl -fsSL \
    https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install-systemd-units.sh \
    -o /tmp/install-systemd-units.sh
chmod 0755 /tmp/install-systemd-units.sh

# Reinstall with the fix
/tmp/install-systemd-units.sh --install-dir /opt/perfsonar-tp --with-certbot

# Reload and start
systemctl daemon-reload
systemctl start perfsonar-certbot.service

# Verify success
systemctl status perfsonar-certbot.service
podman ps | grep certbot
```

## Verification

After applying the fix, verify both services are working correctly:

```bash
# Check service status
systemctl status perfsonar-testpoint.service perfsonar-certbot.service

# Verify containers are running
podman ps --format 'table {{.Names}}\t{{.Status}}'

# Test HTTPS endpoint
curl -kI https://127.0.0.1/

# Check certbot logs for renewal messages
journalctl -u perfsonar-certbot.service -n 20
```

**Expected Results:**

- Both services show `active (running)` status

- Both containers show "Up" status (not "Exited")

- HTTPS endpoint returns `HTTP/1.1 200 OK`

- No error messages in certbot logs

## Reboot Persistence Test

To confirm the fix resolves the reboot persistence issue:

```bash
# Verify services are enabled
systemctl is-enabled perfsonar-testpoint.service perfsonar-certbot.service

# Reboot the system
reboot

# After reboot, verify everything started automatically
systemctl status perfsonar-testpoint.service perfsonar-certbot.service
podman ps
curl -kI https://127.0.0.1/
```

## Breaking Changes

None. This is a backward-compatible bug fix.

## Known Issues

None at this time.

## Commits

- fix: Add --systemd=always and --entrypoint to certbot service for reboot persistence (956b053)

## Next Steps

- Monitor deployments to ensure certbot renewal automation works correctly

- Consider adding automated tests for post-reboot container state

- Evaluate whether additional health checks should be added to systemd units

---

For the full installation guide, see [Installing a perfSONAR Testpoint for WLCG/OSG](../personas/quick-deploy/install-
perfsonar-testpoint.md).

For troubleshooting certificate issues, see the [Certificate Issues](../personas/quick-deploy/install-perfsonar-
testpoint.md#certificate-issues) section.
