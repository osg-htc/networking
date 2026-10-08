## [Unreleased] - 2026-10-08

### Fixed

- **Parallel A/AAAA DNS query stall** (`check-perfsonar-dns.sh` v1.1.0): new `--check-resolver` and `--fix-resolver`
  modes. On some hosts (seen on AlmaLinux 10 behind our nftables ruleset) one of the two parallel DNS replies is
  dropped, so every dual-stack lookup waits for the 5 s resolver timeout and `pscheduler troubleshoot` reports the
  host as "Not resolvable or timed out". The check times a dual-stack `getaddrinfo()` with and without
  `single-request-reopen`; the fix sets that option persistently on the active NetworkManager connections
  (`nmcli device reapply`, falling back to `connection up`), verifies it, and restarts a running testpoint.
  Before re-applying, it saves the DNS servers in use into any profile that has none (re-applying a static profile
  without DNS would remove DHCP-learned servers), and skips a connection when neither has DNS.
- `perfSONAR-orchestrator.sh` v1.1.7: new step 7.5 runs `--fix-resolver` after the nftables/SELinux step.
- `update-perfsonar-deployment.sh` v1.7.0: checks for the stall; `--apply` fixes it and `--restart` restarts the
  testpoint container.
- `perfSONAR-diagnostic-report.sh` v1.2.0: known-issue check for the stall.
- **Published DNS records vs. configured addresses** (`check-perfsonar-dns.sh` v1.2.0): the default mode now also
  checks every A/AAAA record published for the host's names (PTR names of configured addresses and `hostname -f`).
  A record pointing to an address no local interface has is an error (e.g. an AAAA record while IPv6 was never
  configured, as found on test01.swt2.uta.edu); a host with global IPv6 but no AAAA record gets a warning. The
  diagnostic report and orchestrator step 6 pick this up automatically.

## [Unreleased] - 2026-09-29

### Fixed

- **Fresh-host container start failure (EL9/EL10)** (`install-systemd-units.sh` v1.4.0): the generated
  `perfsonar-testpoint.service` bind-mounted `/var/www/html`, the whole `/etc/apache2` and `/etc/letsencrypt`
  for every deployment, but `seed_testpoint_host_dirs.sh` v2 (Option A) no longer creates them. On a fresh
  host podman exited 125 (`Error: statfs /var/www/html: no such file or directory`), systemd restart-looped,
  and the orchestrator's pSConfig enrollment failed with `no such container`. Mounts now match the compose
  files: Option A mounts psconfig/tools_scripts/cgroup/dbus/node_exporter only; Option B (`--with-certbot`)
  adds `/var/www/html`, `/etc/letsencrypt` and only `/etc/apache2/sites-available/default-ssl.conf`. The
  installer pre-creates/seeds every host path and refuses to write a unit whose mount sources are missing.
  New `--force` and `--no-certbot` options; LE mode is preserved automatically on re-runs.
- **LE SSL patch killed the container with a single-file mount** (`testpoint-entrypoint-wrapper.sh` v1.3.0):
  `sed -i`/`mv` cannot replace a bind-mounted file ("Device or resource busy"), which under `set -e` exited
  the wrapper. The file is now rewritten in place.
- **SELinux MCS lockout**: certbot unit and orchestrator certbot runs use `:z` instead of `:Z` on
  `/etc/letsencrypt` and `/var/www/html`; the installer resets stale private MCS labels.
- **EL10**: orchestrator enables CodeReady Builder for the running RHEL major version (was hard-coded to 9).

### Changed

- `perfSONAR-orchestrator.sh` v1.1.6: waits for the testpoint container to be running and prints the service
  journal on failure; skips enrollment with a clear message if the container does not exist.
- `update-perfsonar-deployment.sh` v1.5.0: detects stale unit mounts and regenerates the unit with `--apply`.
- `update-perfsonar-deployment.sh` v1.6.0: on hosts managed by systemd (`perfsonar-testpoint.service` present),
  `--restart` always restarts through systemd instead of `podman-compose down/up`, which started the testpoint
  without `--systemd=always`/`--cgroupns host` and competed with the unit for the container. It waits for the
  container to be running and shows the journal on failure; restart hints print the systemd commands.
- `perfSONAR-diagnostic-report.sh` v1.1.0: new known-issue check for missing bind-mount sources.

## [1.3.2] - 2025-12-16

### Fixed

- **Critical JSON state save corruption fix**: Fixed invalid JSON generation in `--save-state` that caused `--restore-state` to fail
- **Fix (1.3.6)**: Respect `--dry-run` in packet pacing application and ensure audit logic checks actual qdisc state; prevent `--mode apply --dry-run` from changing system qdisc or sysctl state.
  - Properly quote non-numeric ring buffer values (e.g., `Mini:`, `push`, `n/a`)
  - Properly quote non-numeric `nm_mtu` values (e.g., `auto`)
  - Sanitize ring buffer values to ensure numeric-only or properly quoted strings
  - Strip embedded newlines from qdisc strings that corrupted JSON structure
- **Fixed packet pacing audit detection**: `--mode audit` now correctly detects if packet pacing is already applied by checking actual qdisc state instead of relying on command-line flags
- Added `repair-state-json.sh` utility script to repair existing corrupted JSON state files

### Changed

- Enhanced JSON generation in `capture_interface_state()` with proper type validation
- Ring buffer values now validated as numeric before embedding in JSON
- Non-numeric values are quoted as strings
- Summary now checks system state for packet pacing instead of flag state

### Notes

- Users with existing corrupted state files can repair them using `repair-state-json.sh <file.json>`
- The script creates backups before repair and validates output with `jq` or Python

## [Unreleased] - 2026-03-20

### Fixed

- **Apache configuration initialization** (testpoint-entrypoint-wrapper.sh v1.2.0): Fixed container startup failure when using bind-mounted `/etc/apache2` with Let's Encrypt certificates. The wrapper script now initializes missing Apache configuration files on container startup, ensuring Apache can start properly. Includes automatic directory structure creation, module enablement, and configuration validation. Resolves issue where fresh deployments would fail with "Could not open configuration file /etc/apache2/apache2.conf: No such file or directory".

### Changed

- **Installer:** `install_tools_scripts.sh` bumped to `1.0.1` and updated to fetch a fuller set of helper scripts and docs, and attempt to fetch accompanying `.sha256` checksum files when available.
- **lsregistration helper:** `perfSONAR-update-lsregistration.sh` now supports non-container (RPM) installs more robustly by attempting to restart the `perfsonar-lsregistrationdaemon` service name where present and falling back to `lsregistrationdaemon`, and will prefer the `perfsonar-` prefixed unit when restarting.
- **lsregistration helper:** Clarified `save` vs `extract` usage (save writes a raw `.conf` file; extract produces an executable restore script), and the `extract` output now attempts to apply `restorecon` to fix SELinux labels when run on hosts. The updater will attempt a `restorecon` after writing configuration locally or into a container when `restorecon` is available.

### Notes

- The `docs/perfsonar/tools_scripts` directory now includes updated `.sha256` checksum files for modified scripts. See the PR for details.
- testpoint-entrypoint-wrapper.sh checksum updated: `76f49ce6... → abf71262...`

## [1.1.3] - 2025-12-06

### Fixed

- Corrected IOMMU audit messaging to suggest `grubby` for BLS systems (EL9+) and `grub2-mkconfig`/`update-grub` for legacy systems. Also bumped `fasterdata-tuning.sh` to v1.1.3 and updated site copy + checksums.

### Notes

- This is a minor documentation & diagnostic improvement; no new behavioral changes beyond clearer messaging and version bump.
