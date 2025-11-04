# perfSONAR lsregistration helpers

This directory includes two helpers for managing the perfSONAR Lookup Service (LS)
registration configuration in `lsregistrationdaemon.conf`.

- `perfSONAR-update-lsregistration.sh` — updates configuration either inside the
  perfSONAR testpoint container or directly on the host (local mode).
- `perfSONAR-extract-lsregistration.sh` — reads an existing
  `lsregistrationdaemon.conf` and generates a self-contained restore script that
  invokes the updater with all equivalent flags. This is useful after an upgrade
  or rebuild to re-apply your previous configuration in one step.

## Update existing configuration (container or local)

Script: `perfSONAR-update-lsregistration.sh`

- Container mode (default): copies `/etc/perfsonar/lsregistrationdaemon.conf`
  into a temp area, applies requested changes, writes it back into the
  container, and restarts `lsregistrationdaemon` inside the container.
  - Key flags: `--container NAME` (default: `perfsonar-testpoint`),
    `--engine auto|docker|podman` (default: `auto`).
- Local mode: operates directly on the host filesystem without a container.
  - Key flags: `--local`, `--conf PATH` (default:
    `/etc/perfsonar/lsregistrationdaemon.conf`).
  - Attempts a best-effort restart of `lsregistrationdaemon` on the host.

Examples:

```bash
# Update a few fields inside the container
sudo ./perfSONAR-update-lsregistration.sh \
  --container perfsonar-testpoint \
  --site-name "Acme Co." --domain example.org \
  --project WLCG --project OSG \
  --admin-name "pS Admin" --admin-email admin@example.org

# Update the host file directly (non-container use)
sudo ./perfSONAR-update-lsregistration.sh --local \
  --conf /etc/perfsonar/lsregistrationdaemon.conf \
  --city Berkeley --region CA --country US
```

## Generate a restore script from an existing conf

Script: `perfSONAR-extract-lsregistration.sh`

- Reads values from an existing `lsregistrationdaemon.conf` (by default
  `/etc/perfsonar/lsregistrationdaemon.conf`).
- Writes an executable restore script to `/tmp/` that invokes
  `perfSONAR-update-lsregistration.sh` with the equivalent flags.
- Supports generating for container restore (default) or local restore.

Common options:

- `--conf PATH` — source conf to parse (default: `/etc/perfsonar/lsregistrationdaemon.conf`).
- `--script PATH` — path the restore script will call (default: `./perfSONAR-update-lsregistration.sh`).
- `--local` or `--container NAME` — choose local vs container restore target.
- `--engine auto|docker|podman` — include engine selection in container mode.
- `--out PATH` — where to write the restore script (default: `/tmp/perfSONAR-restore-lsregistration-<timestamp>.sh`).
- `--no-sudo` — omit `sudo` in the generated command.

Examples:

```bash
# Build a container restore script (default container name)
./perfSONAR-extract-lsregistration.sh \
  --conf /etc/perfsonar/lsregistrationdaemon.conf \
  --script ./perfSONAR-update-lsregistration.sh

# Build a local restore script that targets the host file directly
./perfSONAR-extract-lsregistration.sh --local \
  --target-conf /etc/perfsonar/lsregistrationdaemon.conf \
  --out /tmp/perfSONAR-restore-local.sh
```

After generation, run the restore script to re-apply your configuration:

```bash
sudo /tmp/perfSONAR-restore-lsregistration-YYYYmmddTHHMMSSZ.sh
```

## Notes

- Both scripts are Bash and require a modern Bash (4+). Use `shellcheck` for
  linting if making changes.
- In container mode, the updater restarts services inside the container; in
  local mode, it attempts to restart the host service.
