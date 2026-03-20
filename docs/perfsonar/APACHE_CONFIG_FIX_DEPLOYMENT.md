# perfSONAR Apache Configuration Fix - Deployment Guide

**Issue Date**: March 20, 2026  
**Fix Version**: testpoint-entrypoint-wrapper.sh v1.2.0  
**Severity**: Critical (affects all new Let's Encrypt deployments)  
**Status**: Available in networking repository

---

## Overview

This guide helps perfSONAR administrators deploy a critical fix for container-based testpoint installations that use Let's Encrypt certificates. The fix resolves Apache startup failures in fresh deployments.

### What's Fixed

Container installations using bind-mounted Apache configuration with Let's Encrypt fail on first startup with:

```
apache2: Could not open configuration file /etc/apache2/apache2.conf: No such file or directory
```

**This fix ensures Apache configuration is properly initialized automatically on container startup.**

### Who Needs This

✅ **You need this fix if:**
- Running perfSONAR testpoint as a **container** (podman/docker)
- Using **Let's Encrypt** certificates for HTTPS
- Deployment **fails to start** or Apache service won't start
- Fresh installations on new hosts
- Using automated deployment scripts

❌ **You do NOT need this if:**
- Running perfSONAR as an **RPM toolkit** (not containerized)
- Using only self-signed certificates (though updating is still recommended)
- Apache already starts successfully

---

## Quick Start (5 minutes)

### Option 1: Automatic Update (Recommended)

If you have an **existing, running deployment**:

```bash
# SSH to your perfSONAR host
ssh user@perfsonar-host

# Run the update script (interactive, shows what will change)
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart

# Or non-interactive
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart --yes
```

**What this does:**
1. Downloads latest helper scripts (including the fix)
2. Updates Apache configuration if needed
3. Restarts the container to apply changes
4. Apache will initialize properly on next startup

### Option 2: Manual Update (If Preferred)

For more control, update just the wrapper script:

```bash
# 1. Download the fixed script
cd /opt/perfsonar-tp/tools_scripts/
sudo curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh \
  -o testpoint-entrypoint-wrapper.sh.new

# 2. Verify checksum
echo "abf71262bc87d410b2e4ac528fad2c0dcb6237b0cd392b0c50a1b3d4b2619777  testpoint-entrypoint-wrapper.sh.new" | sha256sum -c -

# 3. Install the script
sudo mv testpoint-entrypoint-wrapper.sh.new testpoint-entrypoint-wrapper.sh
sudo chmod 0755 testpoint-entrypoint-wrapper.sh

# 4. Restart the container
sudo podman-compose -f /opt/perfsonar-tp/docker-compose.yml restart perfsonar-testpoint
# OR
sudo docker-compose -f /opt/perfsonar-tp/docker-compose.yml restart perfsonar-testpoint
```

### Option 3: New Installation

If you're doing a **fresh installation**, the fix is already in place:

```bash
# Use the standard orchestrator for new installations
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh \
  | sudo bash -s -- --option B --fqdn ps.example.org --email admin@example.org \
      --experiment-id 2 --non-interactive
```

---

## Deployment Steps (Detailed)

### Step 1: Verify You Need The Fix

Check if Apache is running:

```bash
# On your host
sudo podman ps | grep perfsonar-testpoint

# Inside the container
sudo podman exec perfsonar-testpoint systemctl status apache2

# Check if initialization already completed
sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "Already fixed!" || echo "Needs fix"
```

If you see:
- ✅ Apache is running and initialized marker exists → **No action needed**
- ❌ Apache failed to start → **Apply the fix immediately**
- ⚠️ Apache running but no marker → **Apply the fix to ensure robustness**

### Step 2: Choose Your Update Method

#### Method A: Full Update (Recommended)

This updates all helper scripts and ensures everything is current:

```bash
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh
```

Review the output to see what will change:

```
[INFO] perfSONAR Deployment Updater v1.4.0
[INFO] Mode: REPORT only (use --apply to make changes)
[INFO] Auto-detected deployment type: container
[INFO] Base directory:    /opt/perfsonar-tp
[INFO] Compose file:      /opt/perfsonar-tp/docker-compose.yml
[INFO] Container runtime: podman

[CHANGED] UPDATED: testpoint-entrypoint-wrapper.sh (1.0.0 → 1.2.0)
...
```

If satisfied, apply:

```bash
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart
```

#### Method B: Script-Only Update (Faster)

Update just the entrypoint wrapper if you're confident in other components:

```bash
# 1. Make a backup
sudo cp /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh \
       /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh.$(date +%s)

# 2. Download the fixed version
sudo curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh \
  -o /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh.tmp \
  && sudo mv /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh.tmp \
         /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh

# 3. Make executable
sudo chmod 0755 /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh

# 4. Restart container
cd /opt/perfsonar-tp
sudo podman-compose restart perfsonar-testpoint
```

### Step 3: Verify The Fix Was Applied

After restarting, verify the fix:

```bash
# Wait for container to restart (30-60 seconds)
sleep 60

# Check 1: Apache should be running
sudo podman exec perfsonar-testpoint systemctl status apache2
# Should show: ● apache2.service - The Apache HTTP Server ... Active: active (running)

# Check 2: Apache listening on 443
sudo podman exec perfsonar-testpoint ss -tlnp | grep 443
# Should show: LISTEN ... 443/ssl

# Check 3: Initialization marker should exist
sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "✓ Fixed" || echo "✗ Not fixed"

# Check 4: Configuration is valid
sudo podman exec perfsonar-testpoint apache2ctl -t
# Should show: "AH00558: apache2: Could not reliably determine the server's fully qualified domain name, using..."
# ^ This is a WARNING (expected), not an ERROR

# Check 5: Let's Encrypt certificates in use (if configured)
sudo podman exec perfsonar-testpoint grep -i "/etc/letsencrypt" /etc/apache2/sites-available/default-ssl.conf
# Should show paths to: fullchain.pem, privkey.pem, chain.pem
```

### Step 4: Test HTTPS Access

Test that the web interface is accessible:

```bash
# Get your server's FQDN
FQDN="your-perfsonar-host.example.org"

# Test HTTPS (ignore self-signed cert warning if using default certs)
curl -kv https://${FQDN}/ 2>&1 | head -20

# Should show: HTTP/1.1 200 OK or similar success responses
```

---

## Understanding What The Fix Does

### The Problem (Technical Details)

When you use bind mounts for persistent configuration:

```yaml
volumes:
  - /etc/apache2:/etc/apache2:z        # Host dir empty on fresh install
  - /etc/letsencrypt:/etc/letsencrypt:z
```

On first run:
1. Host's empty `/etc/apache2` is mounted into container
2. Container's original Apache configs are hidden behind the empty mount
3. Apache tries to read `/etc/apache2/apache2.conf` → **not found** → startup fails

### The Solution (What's Fixed)

The updated `testpoint-entrypoint-wrapper.sh` (v1.2.0) now:

1. **Initializes Apache** before starting services:
   - Checks if `/etc/apache2/apache2.conf` exists
   - If missing, restores it or creates a valid default

2. **Creates required directories**:
   - `sites-available`, `sites-enabled`
   - `mods-available`, `mods-enabled`
   - `conf-available`, `conf-enabled`

3. **Enables required modules**:
   - `proxy`, `proxy_http`, `ssl`
   - Needed for pScheduler forwarding and HTTPS

4. **Validates configuration**:
   - Runs `apache2ctl -t` to ensure syntax is valid
   - Provides clear error messages if problems found

5. **Prevents re-initialization**:
   - Uses marker file `/etc/apache2/.initialized`
   - No re-initialization on container restarts
   - Safe to restart container multiple times

### Backward Compatibility

✅ **Fully backward compatible:**
- Existing valid Apache configs are left untouched
- Only initializes missing components
- Marker file prevents redundant operations
- Works with or without Let's Encrypt

---

## Troubleshooting

### Problem: Apache Still Won't Start

```bash
# 1. Check Apache configuration syntax
sudo podman exec perfsonar-testpoint apache2ctl -t
```

**If error shown:**
- Look for specific errors in output
- Check config files for syntax issues
- See "Manual Repair" section below

**If warning but no error (AH00558):**
- This is normal and expected for testpoint
- Apache should still be running

### Problem: Let's Encrypt Certificates Not Being Used

```bash
# Check if certificates exist
sudo podman exec perfsonar-testpoint ls -la /etc/letsencrypt/live/

# Check if Apache config was patched
sudo podman exec perfsonar-testpoint grep -i fullchain /etc/apache2/sites-available/default-ssl.conf
```

**If certificates not found:**
- Ensure certbot has obtained certificates
- Run Let's Encrypt setup again if needed
- Verify certificate path in wrapper script: `SERVER_FQDN` variable

**If Apache config not patched:**
- Check wrapper script output: `sudo podman logs perfsonar-testpoint 2>&1 | grep -i letsencrypt`
- Re-run wrapper script: `sudo podman-compose restart`

### Problem: Permission Denied on Script Update

```bash
# If you get permission errors, use sudo
sudo su -  # Become root
cd /opt/perfsonar-tp/tools_scripts/

# Then run update commands above
```

### Problem: Container Won't Restart

```bash
# Check container status
sudo podman ps -a | grep perfsonar

# Check logs for errors
sudo podman logs perfsonar-testpoint 2>&1 | tail -50

# Force restart (more aggressive)
sudo podman-compose -f /opt/perfsonar-tp/docker-compose.yml down
sudo podman-compose -f /opt/perfsonar-tp/docker-compose.yml up -d

# Or with docker-compose
sudo docker-compose -f /opt/perfsonar-tp/docker-compose.yml down
sudo docker-compose -f /opt/perfsonar-tp/docker-compose.yml up -d
```

### Manual Repair (If Needed)

If automatic fix doesn't work, manually restore Apache config:

```bash
# Option 1: Use the container's original config (if available)
sudo podman exec perfsonar-testpoint bash -c '
  if [[ -f /tmp/apache2.conf.orig ]]; then
    cp /tmp/apache2.conf.orig /etc/apache2/apache2.conf
  fi
'

# Option 2: Generate minimal config inside container
sudo podman exec perfsonar-testpoint bash -c '
  cat > /etc/apache2/apache2.conf << "EOF"
DefaultRuntimeDir ${APACHE_RUN_DIR}
PidFile ${APACHE_PID_FILE}
Timeout 300
KeepAlive On
KeepAliveTimeout 5
User www-data
Group www-data
ErrorLog ${APACHE_LOG_DIR}/error.log
LogLevel warn
IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf
IncludeOptional conf-enabled/*.conf
IncludeOptional sites-enabled/*.conf
EOF
'

# Option 3: Restart Apache after manual fix
sudo podman exec perfsonar-testpoint systemctl restart apache2
```

---

## Verification Checklist

After deployment, verify each item:

- [ ] Apache is running: `sudo podman exec perfsonar-testpoint systemctl status apache2` shows active
- [ ] HTTPS port 443 listening: `sudo podman exec perfsonar-testpoint ss -tlnp | grep 443`
- [ ] Apache config valid: `sudo podman exec perfsonar-testpoint apache2ctl -t` shows no errors
- [ ] Initialization marker exists: `sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized`
- [ ] Let's Encrypt patched (if using LE): `sudo podman exec perfsonar-testpoint grep /etc/letsencrypt /etc/apache2/sites-available/default-ssl.conf`
- [ ] Can access HTTPS: `curl -kv https://your-fqdn/` returns 200 OK
- [ ] pScheduler accessible: Check web interface or pScheduler API endpoints

---

## Rollback Instructions

If you need to revert to the previous version:

```bash
# 1. Restore from backup
sudo cp /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh.XXXXXXXX \
       /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh

# 2. Clean Apache state
sudo podman exec perfsonar-testpoint rm -f /etc/apache2/.initialized

# 3. Restart container
cd /opt/perfsonar-tp
sudo podman-compose restart perfsonar-testpoint
```

---

## Getting Help

### Collect Diagnostic Information

If you need help from the perfSONAR team:

```bash
# Generate diagnostic report
sudo /opt/perfsonar-tp/tools_scripts/perfSONAR-diagnostic-report.sh > /tmp/diag.txt

# Check container logs
sudo podman logs perfsonar-testpoint 2>&1 > /tmp/container-logs.txt

# Check Apache error log
sudo podman exec perfsonar-testpoint cat /var/log/apache2/error.log > /tmp/apache-error.log

# Include in your support request
```

### Key Information to Report

When asking for help, include:
- Output of diagnostic report
- Apache error logs
- Container logs from startup
- Docker-compose or podman run command you used
- Error messages you're seeing
- What you've already tried

### References

- [perfSONAR Documentation](https://docs.perfsonar.net/)
- [OSG/HTC Networking docs](https://github.com/osg-htc/networking)
- [Apache HTTP Server](https://httpd.apache.org/docs/2.4/)
- [Let's Encrypt SSL Certificates](https://letsencrypt.org/)

---

## Summary

| Aspect | Details |
|--------|---------|
| **What's Fixed** | Apache configuration initialization on container startup |
| **How to Apply** | Run `update-perfsonar-deployment.sh --apply --restart` |
| **Time to Apply** | 5-10 minutes |
| **Risk Level** | Low (no changes unless needed, fully reversible) |
| **Downtime** | 1-2 minutes (container restart) |
| **Verification** | See verification checklist above |

---

**Last Updated**: March 20, 2026  
**For latest updates**: Check [networking repository CHANGELOG](https://github.com/osg-htc/networking/blob/master/docs/perfsonar/tools_scripts/CHANGELOG.md)
