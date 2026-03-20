# perfSONAR Testpoint Apache Configuration Fix

## Problem Summary

When deploying the perfSONAR testpoint container automatically with Let's Encrypt, the container fails to start because **Apache cannot find its main configuration file** (`/etc/apache2/apache2.conf`).

### Error Message
```
Mar 19 21:31:31 bdw-nibi.alliancecan.ca apachectl[33]: apache2: Could not open configuration file /etc/apache2/apache2.conf: No such file or directory
```

### Symptoms
- Container starts but Apache service fails immediately
- Only `/etc/apache2/sites-available/default-ssl.conf` exists
- Other Apache configuration files are missing
- Container appears to start but has no web interface
- systemctl status shows Apache failed with "Result: exit-code"

---

## Root Cause Analysis

### The Configuration Setup Issue

The perfSONAR testpoint installation uses **bind mounts** from the host filesystem to provide persistent storage for configuration:

```bash
-v /etc/apache2:/etc/apache2:z                # Bind mount host /etc/apache2 into container
-v /etc/letsencrypt:/etc/letsencrypt:z        # Bind mount Let's Encrypt certs
-v /var/www/html:/var/www/html:z              # Bind mount web content
```

### Why This Creates a Problem

1. **Fresh Installation**: On a fresh install, the host's `/etc/apache2` directory is **empty**
2. **Bind Mount Overlay**: The empty host directory overlays the container's `/etc/apache2`, hiding the properly configured Apache files that come with the container image
3. **Container Package Install**: The `perfsonar-testpoint` package is installed in the container image, which includes Apache2. Those configuration files exist inside the container at `/etc/apache2/`
4. **Bind Mount Effects**: When the bind mount is applied, those container files become invisible - they're replaced by the empty host directory
5. **First Startup Failure**: When the container starts for the first time, Apache tries to read `/etc/apache2/apache2.conf` but finds only the (now visible) empty host directory

### Affected Deployment Scenarios

- **Automatic Installation Script**: When running `docker-compose up` or `podman run` with bind mounts on a fresh host
- **Let's Encrypt Integration**: When using the testpoint-entrypoint-wrapper.sh with Let's Encrypt certificates
- **Production Images**: The OSG production image (`hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production`) with automated deployment

---

## The Fix

### What Was Changed

The `testpoint-entrypoint-wrapper.sh` script was updated (Version 1.2.0) to initialize Apache configuration on container startup:

#### Key Improvements

1. **Configuration Initialization Check**
   ```bash
   if [[ ! -f "$APACHE_INIT_MARKER" ]]; then
       # Initialize Apache on first run
   fi
   ```

2. **Restore Missing Main Configuration**
   - Attempts to restore `/etc/apache2/apache2.conf` using `dpkg --configure -a`
   - Falls back to creating a minimal but valid Apache configuration if needed

3. **Create Required Directories**
   ```bash
   mkdir -p "${APACHE_CONF_DIR}/sites-available"
   mkdir -p "${APACHE_CONF_DIR}/sites-enabled"
   mkdir -p "${APACHE_CONF_DIR}/conf-available"
   mkdir -p "${APACHE_CONF_DIR}/conf-enabled"
   mkdir -p "${APACHE_CONF_DIR}/mods-available"
   mkdir -p "${APACHE_CONF_DIR}/mods-enabled"
   ```

4. **Enable Required Modules**
   - Automatically enables `proxy`, `proxy_http`, and `ssl` modules
   - Creates symlinks in `mods-enabled` pointing to `mods-available`

5. **Idempotent Initialization**
   - Uses initialization marker file (`.initialized`) to prevent re-running on container restarts
   - Checks already work on restart

6. **Validation**
   - Runs `apache2ctl -t` to verify configuration syntax
   - Provides clear error messages if validation fails

### Modified File

**Location**: `/root/Git-Repositories/networking/docs/perfsonar/tools_scripts/testpoint-entrypoint-wrapper.sh`

**Version Changed**: 1.0.0 → 1.2.0

---

## How The Fix Works

### Initialization Flow

```
Container Startup
    ↓
testpoint-entrypoint-wrapper.sh runs
    ↓
initialize_apache_config() is called
    ↓
Check: Does /etc/apache2/.initialized exist?
    ├─ YES → Skip initialization (already done)
    └─ NO  → Proceed with init:
    
        Create /etc/apache2 directory structure
        
        Check: Does /etc/apache2/apache2.conf exist?
        ├─ YES → Apache ready
        └─ NO  → Restore/Create it
        
        Create required subdirectories
        Enable required modules
        Validate configuration with apache2ctl
        Create /etc/apache2/.initialized marker
    ↓
Process Let's Encrypt certificates (existing code)
    ↓
Start container (systemd, supervisord, etc.)
    ↓
Apache starts successfully!
```

### Why This Is Robust

1. **Idempotent**: Safe to run multiple times (checks marker file)
2. **Graceful Degradation**: If dpkg-reconfigure fails, creates minimal config
3. **Progressive Enhancement**: Starts Apache with default config, then patches certificates
4. **Non-Destructive**: Doesn't remove existing configs, only creates missing ones
5. **Transparent**: Provides clear logging of what it's doing

---

## Installation/Deployment

### For New Installations

1. **Update the Entrypoint Script**
   - Replace your current `testpoint-entrypoint-wrapper.sh` with the updated version

2. **In docker-compose.yml**
   ```yaml
   services:
     testpoint:
       image: hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production
       entrypoint: ["/opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh"]
       environment:
         - SERVER_FQDN=your-domain.example.com  # Optional for auto-discovery
         - HTTPS_PORT=443
       volumes:
         - /etc/apache2:/etc/apache2:z
         - /etc/letsencrypt:/etc/letsencrypt:z
         - /var/www/html:/var/www/html:z
         - /opt/perfsonar-tp/tools_scripts:/opt/perfsonar-tp/tools_scripts:ro
         # ... other volumes
   ```

3. **Or with podman/docker run**
   ```bash
   podman run \
     --entrypoint=/opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh \
     -e SERVER_FQDN=your-domain.example.com \
     -v /etc/apache2:/etc/apache2:z \
     -v /etc/letsencrypt:/etc/letsencrypt:z \
     # ... other options
     hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production
   ```

### For Existing Installations

1. **Backup existing Apache configs** (optional but recommended):
   ```bash
   sudo cp -r /etc/apache2 /etc/apache2.backup.$(date +%s)
   ```

2. **Update the wrapper script** in your installation

3. **Restart the container** - the script will initialize on next startup

### Post-Fix Verification

After applying the fix, verify Apache is working:

```bash
# Check Apache service status
podman exec perfsonar-testpoint systemctl status apache2

# Check if Apache is listening
podman exec perfsonar-testpoint ss -tlnp | grep 443

# Test Apache configuration
podman exec perfsonar-testpoint apache2ctl -t

# Check the initialization marker
podman exec perfsonar-testpoint test -f /etc/apache2/.initialized && echo "Initialized" || echo "Not initialized"

# Verify Let's Encrypt patch was applied
podman exec perfsonar-testpoint grep -i "/etc/letsencrypt" /etc/apache2/sites-available/default-ssl.conf
```

---

## Troubleshooting

### Apache still fails to start after fix

1. **Check the initialization marker**:
   ```bash
   podman exec perfsonar-testpoint ls -la /etc/apache2/.initialized
   ```
   If missing, initialization didn't complete.

2. **Check Apache configuration syntax**:
   ```bash
   podman exec perfsonar-testpoint apache2ctl -t
   ```
   This shows the exact error if the config is invalid.

3. **Check container logs**:
   ```bash
   podman logs perfsonar-testpoint 2>&1 | grep -A5 "Apache"
   ```

4. **Verify main config exists**:
   ```bash
   podman exec perfsonar-testpoint ls -la /etc/apache2/apache2.conf
   ```

### Apache starts but Let's Encrypt certificates not patched

1. **Verify certs exist**:
   ```bash
   podman exec perfsonar-testpoint ls -la /etc/letsencrypt/live/
   ```

2. **Check wrapper script output**:
   ```bash
   podman logs perfsonar-testpoint 2>&1 | grep "Let's Encrypt"
   ```

3. **Verify the patch was applied**:
   ```bash
   podman exec perfsonar-testpoint grep "fullchain.pem\|privkey.pem" \
     /etc/apache2/sites-available/default-ssl.conf
   ```

### Configuration gets reset after container restart

This **should not happen** with the fix. The initialization marker prevents re-initialization. However:

1. **If `/etc/apache2` is cleared** (e.g., recreated with `--rm`), the marker is lost and re-initialization will occur
2. **This is expected behavior** - it ensures Apache is always properly initialized
3. **To preserve state**: Use named volumes or bind mounts (already recommended)

---

## Related Issues

### Why This Happens with Bind Mounts

Bind mounts copy the state of the directory at container runtime:
- If host directory is empty → container sees empty
- If host directory has files → container sees those files
- Container's own files at that path are hidden

This is different from Docker volumes which are managed by Docker/Podman.

### Alternative Solutions Considered

1. **Don't use bind mounts** - Not viable because we need persistence for certificates and Apache config changes
2. **Initialize Apache on host before running** - Not practical for automated deployments
3. **Use Docker volumes instead** - Feasible but changes deployment model
4. **Include config in container** - Not viable with dynamic certificates
5. **Fix in this startup script** - ✅ **Chosen solution** - Robust and requires no host-side configuration

---

## Testing

The fix was validated with:
- Fresh container deployments
- Multiple container restarts
- Let's Encrypt certificate patching
- Apache configuration configuration validation
- Minimal config creation fallback

---

## Version History

- **v1.2.0** (Current): Added Apache configuration initialization
  - Auto-restore main /etc/apache2/apache2.conf
  - Create required directory structure
  - Enable necessary Apache modules
  - Idempotent initialization with marker file

- **v1.1.0**: Original Let's Encrypt patching functionality

- **v1.0.0**: Initial entrypoint wrapper

---

## References

- Apache2 Configuration: https://httpd.apache.org/docs/2.4/configuring.html
- Debian Bind Mounts: https://wiki.debian.org/Bind
- Docker Volumes vs Bind Mounts: https://docs.docker.com/storage/
- perfSONAR Documentation: https://docs.perfsonar.net/

---

## Support

If you encounter issues after applying this fix:

1. Collect the diagnostic information:
   ```bash
   /opt/perfsonar-tp/tools_scripts/perfsonar-diag.sh > diag-$(date +%s).txt
   ```

2. Include in bug report:
   - Diagnostic file
   - Container startup logs
   - Apache error log (`/var/log/apache2/error.log` in container)
   - Docker-compose or podman run command used

3. Report to: OSG perfSONAR deployment team
