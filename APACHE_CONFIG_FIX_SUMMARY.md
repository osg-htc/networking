# perfSONAR Apache Configuration Fix - Implementation Summary

**Date**: March 20, 2026  
**Issue**: Container fails to start when using Let's Encrypt with bind-mounted Apache configuration  
**Status**: ✅ **READY FOR DEPLOYMENT**

---

## What Was Fixed

### The Issue
Fresh perfSONAR testpoint container installations with Let's Encrypt fail on startup with:
```
apache2: Could not open configuration file /etc/apache2/apache2.conf: No such file or directory
```

**Root Cause**: Bind-mounted empty `/etc/apache2` directory hides the container's properly-configured Apache files.

### The Solution
Updated `testpoint-entrypoint-wrapper.sh` (v1.2.0) now automatically:
- ✅ Initializes missing Apache configuration files on container startup
- ✅ Creates required directory structure (sites-enabled, mods-enabled, etc.)
- ✅ Enables required Apache modules (proxy, proxy_http, ssl)
- ✅ Validates Apache configuration syntax
- ✅ Prevents re-initialization on container restarts (idempotent)
- ✅ Falls back to minimal valid config if original unavailable

---

## What Changed in the Repository

### 1. Modified Script
- **File**: `docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh`
- **Version**: 1.0.0 → 1.2.0
- **Key Changes**:
  - Added `initialize_apache_config()` function
  - Auto-detects missing apache2.conf
  - Creates required Apache directories
  - Enables proxy and SSL modules
  - Validates configuration with apache2ctl
  - Uses initialization marker to prevent re-running

### 2. Updated Checksums
- **File**: `docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh.sha256`
  - Old: `76f49ce6...`
  - New: `abf71262...`

- **File**: `docs/perfsonar/tools_scripts/scripts.sha256`
  - Updated testpoint-entrypoint-wrapper.sh checksum for master checksum file

### 3. Documentation
- **Created**: `docs/perfsonar/APACHE_CONFIG_FIX_DEPLOYMENT.md`
  - User deployment guide with step-by-step instructions
  - Troubleshooting section
  - Verification checklist
  - Rollback procedures

- **Updated**: `docs/perfsonar/tools_scripts/CHANGELOG.md`
  - Added entry in [Unreleased] section documenting the fix
  - Includes checksum update reference

- **Created**: Technical analysis at `/root/Git-Repositories/networking/PERFSONAR_APACHE_CONFIG_FIX.md`
  - Detailed root cause analysis
  - Architecture and design documentation
  - Testing methodology

---

## User Deployment Path

### For Users With EXISTING Deployments

**Option A: Recommended - Full Update**

Users should run the update script which:
1. Automatically downloads all latest helper scripts (including the fix)
2. Shows what will change before applying
3. Optionally restarts services
4. Handles both container and RPM toolkit deployments

```bash
# Step 1: View changes (safe, read-only)
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh

# Step 2: Apply changes and restart (when ready)
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart
```

**Does this require `update-perfsonar-deployment.sh`?** ✅ **YES - Strongly Recommended**

**Why:**
- It's the proper, supported update mechanism
- Phase 1 downloads the fixed script automatically
- Phase 4 restarts container to apply fixes
- It's idempotent (safe to run multiple times)
- It handles both container and RPM toolkit deployments
- Users can review changes before applying with `--apply`

### For NEW Installations

Use the orchestrator script which includes the fix automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh \
  | sudo bash -s -- --option B --fqdn ps.example.org --email admin@example.org \
      --experiment-id 2 --non-interactive
```

**Does this require `update-perfsonar-deployment.sh`?** ❌ **NO** - Fix is automatically included

---

## User Instructions

### Quick Reference

```bash
# 1. SSH to perfSONAR host
ssh user@perfsonar-host

# 2. View what will change (SAFE - read-only)
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh

# 3. Reviews output, then apply when ready
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart

# 4. Verify the fix was applied (30-60 seconds after restart)
sudo podman exec perfsonar-testpoint systemctl status apache2
sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "✓ Fixed"
```

### What Happens

1. **Phase 1** (update-perfsonar-deployment.sh):
   - Downloads latest scripts including testpoint-entrypoint-wrapper.sh v1.2.0
   - Shows testpoint-entrypoint-wrapper.sh version change: 1.0.0 → 1.2.0

2. **Phase 2-4**:
   - Applies any config changes needed
   - Restarts the container

3. **On Container Startup**:
   - testpoint-entrypoint-wrapper.sh runs
   - `initialize_apache_config()` checks if apache2.conf missing
   - Creates Apache structure and config if needed
   - Creates `/etc/apache2/.initialized` marker
   - Processes Let's Encrypt certificates
   - Container starts normally

4. **Subsequent Restarts**:
   - Marker file prevents re-initialization
   - Container starts normally

### Verification Steps

After deployment, verify the fix:

```bash
# Wait 30-60 seconds for container to restart
sleep 60

# 1. Check Apache status
sudo podman exec perfsonar-testpoint systemctl status apache2

# 2. Check HTTPS listening
sudo podman exec perfsonar-testpoint ss -tlnp | grep 443

# 3. Check initialization marker
sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "✓ Fixed" || echo "✗ Not fixed"

# 4. Check Apache config valid
sudo podman exec perfsonar-testpoint apache2ctl -t

# 5. Test HTTPS access
curl -kv https://your-perfsonar-fqdn.org/
```

---

## Implementation Timeline

| Phase | Timeline | Status |
|-------|----------|--------|
| Fix Development & Testing | ✅ Complete | READY |
| Repository Updates | ✅ Complete | READY |
| Documentation | ✅ Complete | READY |
| User Deployment | 🔄 In Progress | READY |
| Timebox: User Adoption | ~2-4 weeks | EXPECTED |

---

## Risk Assessment

### Deployment Risk: **LOW**

✅ **Low Risk Because:**
- Changes are isolated to initialization phase only
- Fully backward compatible (existing configs preserved)
- Idempotent design (safe to run/restart multiple times)
- Includes validation with `apache2ctl -t`
- Marker file prevents redundant operations
- Clear error messages if problems occur
- Can be disabled or rolled back if needed

### Impact Assessment

| Aspect | Impact |
|--------|--------|
| **Downtime** | ~1-2 min (container restart) |
| **Existing Configs** | Not modified (only initializes missing) |
| **Let's Encrypt Certs** | No impact (still patched as before) |
| **Performance** | No impact (init only runs on first start) |
| **Rollback** | Easy (revert script, no config impact) |

---

## Support & Troubleshooting

### If Apache Still Won't Start

1. Check if initialization ran:
   ```bash
   sudo podman logs perfsonar-testpoint 2>&1 | grep -A5 "Apache"
   ```

2. Check Apache config:
   ```bash
   sudo podman exec perfsonar-testpoint apache2ctl -t
   ```

3. Check initialization marker:
   ```bash
   sudo podman exec perfsonar-testpoint ls -la /etc/apache2/.initialized
   ```

4. See full troubleshooting guide: `APACHE_CONFIG_FIX_DEPLOYMENT.md`

### If Let's Encrypt Not Working

1. Check certificates exist:
   ```bash
   sudo podman exec perfsonar-testpoint ls -la /etc/letsencrypt/live/
   ```

2. Check Apache config patched:
   ```bash
   sudo podman exec perfsonar-testpoint grep -i fullchain /etc/apache2/sites-available/default-ssl.conf
   ```

3. See Let's Encrypt section in deployment guide

### Escalation Path

For unresolved issues:
1. Collect diagnostic report: `perfSONAR-diagnostic-report.sh`
2. Attach Apache logs
3. Provide container startup logs
4. Report to: osg-htc/networking repository issues

---

## Repository References

### Files Changed
- [testpoint-entrypoint-wrapper.sh](../docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh) (v1.2.0)
- [testpoint-entrypoint-wrapper.sh.sha256](../docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh.sha256)
- [scripts.sha256](../docs/perfsonar/tools_scripts/scripts.sha256)
- [CHANGELOG.md](../docs/perfsonar/tools_scripts/CHANGELOG.md)

### Documentation
- [Deployment Guide](./APACHE_CONFIG_FIX_DEPLOYMENT.md) - Step-by-step user instructions
- [Technical Analysis](../PERFSONAR_APACHE_CONFIG_FIX.md) - Root cause and design details

---

## Update Mechanism

### How update-perfsonar-deployment.sh Works

The deployment script (v1.4.0) has this update flow:

```
Phase 1: Download latest scripts
  ├─ Fetches install_tools_scripts.sh
  └─ Which downloads all tools including testpoint-entrypoint-wrapper.sh
  
Phase 2: Compare configurations
  └─ Shows what changed (v1.0.0 → v1.2.0)

Phase 3: Update compose/config
  └─ Updates docker-compose.yml if needed

Phase 4: Restart services
  └─ Restarts container (fix takes effect here)

Phase 5: Validate
  └─ (Optional) verify changes applied
```

**User sees:**
```
[CHANGED] UPDATED: testpoint-entrypoint-wrapper.sh (1.0.0 → 1.2.0)
```

Then container restarts, and Apache initializes properly on next startup.

---

## Summary for Users

| Question | Answer |
|----------|--------|
| **Do I need this fix?** | If running container with Let's Encrypt and Apache won't start: YES |
| **Is it automatic?** | No, users must run `update-perfsonar-deployment.sh` |
| **Do I need to rerun install?** | No, just run the update script |
| **Will it disrupt my deployment?** | ~1-2 min downtime for container restart |
| **Is it reversible?** | Yes, easy rollback available |
| **What if I don't update?** | Fresh deployments will fail on startup |
| **When should I update?** | ASAP if experiencing Apache startup issues |

---

## Deployment Checklist

- [ ] Review this summary document
- [ ] Read deployment guide: `APACHE_CONFIG_FIX_DEPLOYMENT.md`
- [ ] Identify affected deployments (container + Let's Encrypt)
- [ ] Schedule maintenance window (1-2 minutes downtime)
- [ ] Backup /etc/apache2 directory (on host)
- [ ] Run update-perfsonar-deployment.sh (non-apply mode first)
- [ ] Review proposed changes
- [ ] Run update-perfsonar-deployment.sh --apply --restart
- [ ] Wait 60 seconds for container startup
- [ ] Verify Apache is running
- [ ] Verify HTTPS access works
- [ ] Test pScheduler functionality
- [ ] Document completion

---

**For Questions or Issues:**
- See troubleshooting section in `APACHE_CONFIG_FIX_DEPLOYMENT.md`
- Reference technical analysis in `PERFSONAR_APACHE_CONFIG_FIX.md`
- Check CHANGELOG for version history

**Last Updated**: March 20, 2026
