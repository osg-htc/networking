# perfSONAR lsregistration helpers

This directory includes a helper for managing the perfSONAR Lookup Service (LS) registration configuration in
`lsregistrationdaemon.conf`.

- `perfSONAR-update-lsregistration.sh` — a combined helper that can update,
save, restore, create, and extract a `lsregistrationdaemon.conf`. Use the commands `update`, `save`, `restore`,
`create`, `extract` and `multi-nic` (see examples below).

## Update existing configuration (container or local)

Script: `perfSONAR-update-lsregistration.sh`

- Container mode (default): copies `/etc/perfsonar/lsregistrationdaemon.conf`
into a temp area, applies requested changes, writes it back into the container, and restarts `lsregistrationdaemon`
inside the container.

- Key flags: `--container NAME` (default: `perfsonar-testpoint`),
      `--engine auto|docker|podman` (default: `auto`).

- Local mode: operates directly on the host filesystem without a container.

- Key flags: `--local`, `--conf PATH` (default: `/etc/perfsonar/lsregistrationdaemon.conf`).

- Attempts a best-effort restart of `lsregistrationdaemon` on the host.

- Restart behavior: the script now attempts to restart the `perfsonar-lsregistrationdaemon` unit first (common in RPM installs), falls back to `lsregistrationdaemon` if that unit is not present, and finally falls back to signalling the process via `pkill -HUP` when `systemctl` is not available.

- SELinux: when writing configuration to a host or into a container the updater will attempt to apply `restorecon` (if available) to the target path to ensure SELinux labels are usable after an automated restore. For manual restores that fail due to SELinux, run: `sudo /sbin/restorecon -v /etc/perfsonar/lsregistrationdaemon.conf`.

- **Save vs Extract:** `save --output FILE` writes the raw `lsregistrationdaemon.conf` to `FILE` (recommended suffix
  `.conf`). `extract --output SCRIPT` produces an **executable restore script that embeds the full
  configuration**—when run, the script writes the conf into `/etc/perfsonar/lsregistrationdaemon.conf` and applies
  `restorecon` if available. The extracted script is portable and can be used to restore the configuration on any
  system (recommended suffix `.sh`).

Examples:

```bash
# Update a few fields inside the container (from installed tools path)
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh \
  --container perfsonar-testpoint \
  --site-name "Acme Co." --domain example.org \
  --project WLCG --project OSG \
  --admin-name "pS Admin" --admin-email admin@example.org

# Update the host file directly (non-container use)
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh --local \
  --conf /etc/perfsonar/lsregistrationdaemon.conf \
  --city Berkeley --region CA --country US
```

## Generate a restore script from an existing conf

Script: `perfSONAR-update-lsregistration.sh` (see above)

The combined helper contains an `extract` command that produces a self-contained restore script. Note the distinction:

- `save --output FILE` writes the raw `lsregistrationdaemon.conf` content to `FILE` (recommended suffix: `.conf`). The output is a plain configuration file that must be manually installed.
- `extract --output FILE` produces an **executable script** that **embeds the full configuration** and will write the conf to `/etc/perfsonar/lsregistrationdaemon.conf` and attempt to fix SELinux labels when executed (recommended suffix: `.sh`). The generated script is portable and can be run on any system to restore the configuration.

Examples:

```bash
# Save the raw conf file (must be manually placed and configured)
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh save --output /tmp/lsreg.conf

# Produce a self-contained restore script that embeds the configuration (can be run directly)
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh extract --output /tmp/restore-lsreg.sh
/tmp/restore-lsreg.sh
```

## Notes

- Both scripts are Bash and require a modern Bash (4+). Use `shellcheck` for
  linting if making changes.

- In container mode, the updater restarts services inside the container; in
  local mode, it attempts to restart the host service.

## Hosts with several perfSONAR NICs (`multi-nic`, v1.1.0+)

By default the daemon registers one host record for one autodiscovered primary address, so a host with several
perfSONAR NICs and DNS names is only visible in the Lookup Service under one of them. `multi-nic` registers one host
record per public NIC instead, based on `/etc/perfSONAR-multi-nic-config.conf`:

```bash
# Container testpoint (default): preview, then apply and restart the daemon
perfSONAR-update-lsregistration.sh multi-nic --dry-run
perfSONAR-update-lsregistration.sh multi-nic

# RPM toolkit, or a different NIC file
perfSONAR-update-lsregistration.sh multi-nic --local
perfSONAR-update-lsregistration.sh multi-nic --nic-conf /path/to/perfSONAR-multi-nic-config.conf
```

- One `<host>` per public NIC, default-route NIC first: `host_name` = IPv4 address and DNS name, its own
  `<interface>`, and the existing `<service>` blocks with explicit addresses (name, IPv4, IPv6).
- Private addresses are skipped unless `--allow-internal 1`. Each public NIC needs a reverse-DNS name that resolves
  back to its IPv4 address.
- Everything outside the `<host>` blocks (site, location, administrator, `ls_instance`) is kept. Running it again
  regenerates the hosts from the current NIC file.
- In container testpoints the file is not bind-mounted, so a container re-create brings back the default; re-run the
  command after updates. See [multiple-nic-guidance.md](../multiple-nic-guidance.md).

## Note on `ls_lease_duration` with the 2026 Lookup Service

Since June 2026 the global Lookup Service no longer accepts the v1 bulk renew (keepalive) requests that
`lsregistrationdaemon` sends, so records expire after the server's default lifetime and are registered again.
Raising `ls_lease_duration` (`--ls-lease-duration`) does not help with perfSONAR 5.2.x: the daemon sends that value
only in bulk renew requests, not with new registrations. Longer record lifetimes have to come from the server side.
