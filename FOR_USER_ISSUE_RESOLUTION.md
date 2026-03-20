# Fix Applied: perfSONAR Apache Configuration Initialization

**For**: perfSONAR user reporting Apache config issues with Let's Encrypt  
**Status**: ✅ Ready to Deploy  
**Date**: March 20, 2026

---

## Your Issue: FIXED ✅

You reported:
> "I was trying the automatic installation of the perfsonar testpoint container again, and for some reason the container comes up with no apache config. I was trying it with Let's Encrypt, and /etc/apache2/sites-available/default-ssl.conf was there, but nothing else."

### What Was Wrong

When using bind-mounted Apache configuration with Let's Encrypt:
- Fresh `/etc/apache2` directory on host was **empty**
- Empty host directory **hid** the container's properly-configured Apache files
- Apache couldn't find `/etc/apache2/apache2.conf`
- Container **failed to start** with: `Could not open configuration file /etc/apache2/apache2.conf`

### What's Fixed

The entrypoint wrapper script now:
1. **Detects** if Apache configuration is missing
2. **Initializes** Apache files automatically on container startup
3. **Creates** required directory structure
4. **Enables** necessary modules
5. **Validates** configuration before starting Apache
6. **Prevents** re-initialization on restarts

---

## For Your Next Deployment

### Quick Steps

```bash
# 1. SSH to your host
ssh user@your-perfsonar-host

# 2. Run the update (view what will change)
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh

# 3. Apply when ready
sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart

# 4. Wait 60 seconds, then verify
sleep 60
sudo podman exec perfsonar-testpoint systemctl status apache2
```

### What This Does

The `update-perfsonar-deployment.sh` script will:
1. Download the latest version of `testpoint-entrypoint-wrapper.sh` (now v1.2.0 with the fix)
2. Show you what changed
3. Restart the container to apply the fix
4. Apache will initialize properly on the new startup

### Do I Really Need To Run the Update Script?

**Yes, here's why:**

The `update-perfsonar-deployment.sh` script is the **proper, supported mechanism** for updating deployments. It:

- ✅ Downloads script updates automatically
- ✅ Lets you review changes before applying (safe)
- ✅ Validates everything is correct
- ✅ Restarts services properly
- ✅ Works for both container and RPM deployments
- ✅ Is idempotent (safe to run multiple times)

**There's no simpler way.** Even if you manually copied the script, you'd still need to restart the container, so using the update script is more efficient.

---

## What Changes Are In Place

### The Fixed Script
- **File**: `testpoint-entrypoint-wrapper.sh`
- **New Version**: 1.2.0
- **What it does**: Initializes Apache config automatically on startup
- **Location**: `/opt/perfsonar-tp/tools_scripts/` (on your host)

### Updated Checksums
- Script versions have been updated in the repository
- Ensures integrity and consistency across deployments

### Documentation
- Comprehensive deployment guide created
- Troubleshooting section included
- Verification checklist provided

---

## Verification After Applying Fix

After you run the update and restart:

```bash
# Should show Apache is running
sudo podman exec perfsonar-testpoint systemctl status apache2

# Should show 443 listening
sudo podman exec perfsonar-testpoint ss -tlnp | grep 443

# Should show initialization completed
sudo podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "✓ Fixed"

# Should show config is valid
sudo podman exec perfsonar-testpoint apache2ctl -t
```

---

## For Your NEXT FRESH INSTALLATION

If you deploy a **new** perfSONAR testpoint with Let's Encrypt, the fix is already included:

```bash
# Use this command for new installations
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh \
  | sudo bash -s -- --option B --fqdn ps.example.org --email admin@example.org \
      --experiment-id 2 --non-interactive
```

The orchestrator script automatically includes the v1.2.0 wrapper, so Apache will initialize correctly from the start.

---

## Questions & Troubleshooting

### "What if Apache still won't start?"

See the complete troubleshooting guide:
[https://github.com/osg-htc/networking/blob/master/docs/perfsonar/APACHE_CONFIG_FIX_DEPLOYMENT.md](APACHE_CONFIG_FIX_DEPLOYMENT.md)

Specific sections:
- Apache Won't Start → Check logs
- Let's Encrypt Not Working → Verify certificates
- Manual Repair → Last resort options

### "How long does the update take?"

- Viewing changes: < 1 min
- Applying changes: 1-2 min (includes container restart)
- Total: ~5 minutes

### "Is it safe?"

✅ **Yes, very safe:**
- Changes only initialize missing files (don't modify existing)
- Fully reversible (can rollback if needed)
- Idempotent (safe to run multiple times)
- Existing Apache configs are never touched

### "What if something goes wrong?"

Easy rollback:
```bash
# 1. Restore from backup (if you made one)
sudo cp /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh.backup \
       /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh

# 2. Restart container
cd /opt/perfsonar-tp
sudo podman-compose restart

# 3. Or, just restore from repository
curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh \
  | sudo tee /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh > /dev/null
sudo chmod 0755 /opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh
sudo podman-compose restart
```

---

## Next Steps YOU Should Take

### Immediate (Today)

1. **Read** the deployment guide:
   - File: [APACHE_CONFIG_FIX_DEPLOYMENT.md](APACHE_CONFIG_FIX_DEPLOYMENT.md)
   - Location: `docs/perfsonar/` in network repository

2. **If you have a running deployment:**
   ```bash
   sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh
   ```
   (Just view what will change, don't apply yet if you're cautious)

### This Week

3. **Schedule a brief maintenance window** (1-2 minutes downtime)

4. **Apply the fix:**
   ```bash
   sudo /opt/perfsonar-tp/tools_scripts/update-perfsonar-deployment.sh --apply --restart
   ```

5. **Verify** Apache is working (see verification steps above)

### For Your Next Deployment

6. **Use the updated orchestrator script** for new installations
   - It includes the fix automatically
   - No manual steps needed

---

## Summary

| Item | Details |
|------|---------|
| **What was broken** | Apache wouldn't start with Let's Encrypt due to empty bind-mount |
| **What's fixed** | Wrapper script now auto-initializes Apache config |
| **Version** | testpoint-entrypoint-wrapper.sh 1.2.0 |
| **How to get it** | Run `update-perfsonar-deployment.sh --apply --restart` |
| **Time required** | ~5 minutes total |
| **Risk level** | Low (safe, reversible, idempotent) |
| **Downtime** | 1-2 minutes (container restart) |

---

## Resources

- **Deployment Guide**: [APACHE_CONFIG_FIX_DEPLOYMENT.md](APACHE_CONFIG_FIX_DEPLOYMENT.md)
- **Technical Details**: [PERFSONAR_APACHE_CONFIG_FIX.md](../PERFSONAR_APACHE_CONFIG_FIX.md)
- **Implementation Summary**: [APACHE_CONFIG_FIX_SUMMARY.md](../APACHE_CONFIG_FIX_SUMMARY.md)
- **Repository**: [osg-htc/networking](https://github.com/osg-htc/networking)
- **CHANGELOG**: [tools_scripts/CHANGELOG.md](./tools_scripts/CHANGELOG.md)

---

**Your issue should now be resolved. Good luck with your deployment!** 🚀

If you encounter any problems:
1. Check the troubleshooting section in APACHE_CONFIG_FIX_DEPLOYMENT.md
2. Collect diagnostic output: `perfSONAR-diagnostic-report.sh`
3. Report the issue with details from the diagnostic report

**Questions?** Open an issue on the osg-htc/networking repository.

---

*For the user who reported the issue:*
Your problem has been fixed in `testpoint-entrypoint-wrapper.sh` v1.2.0. The fix automatically initializes Apache configuration on container startup, preventing the "no apache config" issue you experienced. Just run the update script provided above, and your next deployment will work smoothly with Let's Encrypt.
