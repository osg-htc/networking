# perfSONAR lsregistration helpers

This directory includes a helper for managing the perfSONAR Lookup Service (LS) registration configuration in
`lsregistrationdaemon.conf`.

- `perfSONAR-update-lsregistration.sh` — a combined helper that can update,
save, restore, create, and extract a `lsregistrationdaemon.conf`. Use the commands `update`, `save`, `restore`,
`create`, and `extract` (see examples below).

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

- Save vs Extract: `save --output FILE` writes the raw `lsregistrationdaemon.conf` to `FILE` (recommended suffix `.conf`). `extract --output SCRIPT` produces a self-contained, executable restore script that writes the conf into `/etc/perfsonar/lsregistrationdaemon.conf` and tries to apply `restorecon` when executed on a host (recommended suffix `.sh`).

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

- `save --output FILE` writes the raw `lsregistrationdaemon.conf` content to `FILE` (recommended suffix: `.conf`).
- `extract --output FILE` produces an executable script that will write the conf to `/etc/perfsonar/lsregistrationdaemon.conf` and attempt to fix SELinux labels (recommended suffix: `.sh`).

Examples:

```bash
# Save the raw conf file
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh save --output /tmp/lsreg.conf

# Produce a self-contained restore script suitable for host restore
/opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh extract --output /tmp/restore-lsreg.sh
/tmp/restore-lsreg.sh
```

## Notes

- Both scripts are Bash and require a modern Bash (4+). Use `shellcheck` for
  linting if making changes.

- In container mode, the updater restarts services inside the container; in
  local mode, it attempts to restart the host service.
