# perfSONAR lsregistration helpers

This directory includes two helpers for managing the perfSONAR Lookup Service (LS)
registration configuration in `lsregistrationdaemon.conf`.

- `perfSONAR-update-lsregistration.sh` — updates configuration either inside the
  perfSONAR testpoint container or directly on the host (local mode).
- `perfSONAR-update-lsregistration.sh` (combined) — updates configuration and
  can also save/restore/extract a configuration. The single helper supports
  the previous updater and extractor workflows via commands: `save`,
  `restore`, `create`, `update`, and `extract`.

## Update existing configuration (container or local)

Script: `perfSONAR-update-lsregistration.sh`

- Container mode (default): copies `/etc/perfsonar/lsregistrationdaemon.conf`
  into a temp area, applies requested changes, writes it back into the
  container, and restarts `lsregistrationdaemon` inside the container.
  - Key flags: `--container NAME` (default: `perfsonar-testpoint`),

    ```
`--engine auto|docker|podman` (default: `auto`).
    ```

- Local mode: operates directly on the host filesystem without a container.
  - Key flags: `--local`, `--conf PATH` (default:

    ```
`/etc/perfsonar/lsregistrationdaemon.conf`).
    ```

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

Script: `perfSONAR-update-lsregistration.sh` (see above)

The combined helper contains an `extract` command that produces a
self-contained restore script. Use `--output`/`--input` to control paths. Example:

```bash
# Produce a self-contained restore script suitable for host restore
sudo ./perfSONAR-update-lsregistration.sh extract --output /tmp/restore-lsreg.sh
sudo /tmp/restore-lsreg.sh
```

## Notes

- Both scripts are Bash and require a modern Bash (4+). Use `shellcheck` for
  linting if making changes.
- In container mode, the updater restarts services inside the container; in
  local mode, it attempts to restart the host service.
