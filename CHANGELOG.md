
# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this repository will be documented in this file.

## [1.5.3] - 2026-02-26

### Fixed

- **`update-perfsonar-deployment.sh` v1.3.0**: Fixes a crash-on-self-update bug. When Phase 1 downloaded a newer version of the script into `tools_scripts/`, bash would continue executing from the overwritten file at the wrong offset, producing `syntax error near unexpected token '('` on the first line of new content. The script now captures its original arguments before parsing, and after Phase 1 compares the version embedded in the newly-installed `tools_scripts/` copy against `$VERSION`. If they differ, it calls `exec` on the new script with the original arguments — replacing the current process entirely so the updated version runs cleanly from line 1. The user no longer needs to re-run manually.

## [1.5.2] - 2026-02-26

### Fixed

- **`update-perfsonar-deployment.sh` v1.2.0**: Automatically detects and corrects stale SELinux MCS labels on `/etc/letsencrypt` and `/var/www/html` for Let's Encrypt container deployments when run with `--apply`. A prior certbot `:Z` volume mount bug (fixed in v1.5.1) stamped private MCS categories onto these shared directories on every certbot container recreation. The script now runs `chcon -R -t container_file_t -l s0` to restore shared `container_file_t:s0` labels, then restarts Apache inside the running container immediately when possible — eliminating the need for a full container restart to restore service.
- **`install-perfsonar-testpoint.md`**: Corrected the SELinux volume label reference table in the LE deployment section (`:Z` → `:z` for certbot-shared paths); added `??? failure` troubleshooting entry for the Apache 403 / connection-refused-after-update scenario; added SELinux auto-fix row to the "What the updater does" table.

## [1.5.1] - 2026-02-26

### Fixed

- **`docker-compose.testpoint-le.yml` and `docker-compose.testpoint-le-auto.yml`**: Changed the `certbot` service volume mounts for `/etc/letsencrypt` and `/var/www/html` from `:Z` (private SELinux MCS relabeling) to `:z` (shared). The `:Z` flag stamped the certbot container's MCS categories onto those host directories on every container recreation. `/etc/letsencrypt:Z` caused Apache to fail (`SSLCertificateFile does not exist`, connection refused on port 443). `/var/www/html:Z` caused Apache to return 403 on all endpoints (`Permission denied: search permissions are missing on a component of the path`). Immediate recovery on affected hosts: `chcon -R -t container_file_t -l s0 /etc/letsencrypt /var/www/html`, then `podman exec perfsonar-testpoint systemctl start apache2`.

## [1.5.0] - 2026-02-26

### Added

- **Container healthchecks upgraded** in all four compose templates (`docker-compose.yml`, `docker-compose.testpoint.yml`, `docker-compose.testpoint-le.yml`, `docker-compose.testpoint-le-auto.yml`): replaced the shallow `curl https://localhost/` test with `pscheduler troubleshoot --quick`, which validates the full pScheduler service stack (Ticker, Scheduler, Runner, Archiver) in under 1 second. Interval reduced from 30 s to 60 s; `start_period` increased to 120 s for reliable pScheduler startup; `timeout` set to 30 s.
- **`perfSONAR-health-monitor.sh` v1.0.0**: New watchdog script that inspects the container health state every 5 minutes via a systemd timer and automatically restarts `perfsonar-testpoint.service` when the container is marked `unhealthy` (after 3 consecutive failed health checks). Logs to `/var/log/perfsonar-health-monitor.log`. Also restarts if the container is missing while the service is active.
- **`install-systemd-units.sh` v1.2.0**: New `--health-monitor` flag installs `perfSONAR-health-monitor.sh` to `/usr/local/bin/` and creates `perfsonar-health-monitor.service` + `perfsonar-health-monitor.timer` (runs 3 minutes after boot, then every 5 minutes).
- `install_tools_scripts.sh` v1.0.4: Bootstrap now also downloads `perfSONAR-health-monitor.sh`.

## [1.4.0] - 2026-02-26

### Added

- **`update-perfsonar-deployment.sh` v1.1.0**: Update script now supports both **container** and **RPM toolkit** deployments. New `--type` flag (`container` | `toolkit`) with auto-detection when omitted. Toolkit mode adds Phase 3 RPM updates via `dnf`, Phase 4 native service restarts (pscheduler, httpd, etc.), and skips Phase 5 (systemd units). Container mode unchanged from v1.0.0.
- Documentation: "Updating an Existing Deployment" section added to both the container and toolkit Quick Deploy install guides with quick-start one-liners, phase tables, and flags references.
- `install_tools_scripts.sh` v1.0.3: Bootstrap now downloads `update-perfsonar-deployment.sh` and `node_exporter.defaults` so the full deployment toolkit is available after initial install.

## [1.3.10] - 2026-01-27

### Fixed

- `fasterdata-tuning.sh` v1.3.10: Ensure all state management functions (`--restore-state`, `--diff-state`, `--list-states`) explicitly return 0 on successful completion so they exit with code 0 instead of inheriting non-zero exit codes from sub-commands.

## [1.3.9] - 2026-01-27

### Fixed

- `fasterdata-tuning.sh` v1.3.9: Fix `--restore-state` to properly reset interface qdisc settings when saved state lacks qdisc or has "unknown" qdisc. Ensures packet pacing is disabled when restoring to pre-apply state (fixes issue where qdisc=fq remains active after restore).

## [1.3.8] - 2026-01-26

### Fixed

- `fasterdata-tuning.sh` v1.3.8: Guard all flags that require a value so missing arguments fail fast with a helpful error instead of triggering `set -u` unbound variable crashes (e.g., `--restore-state`).

## [1.3.7] - 2025-12-19

### Fixed

- `fasterdata-tuning.sh` v1.3.7: Fix summary display of packet pacing status to correctly detect applied qdisc (fq/tbf) instead of incorrectly reporting "not applied" when pacing was enabled.

## [1.3.6] - 2025-12-18

### Fixed

- `fasterdata-tuning.sh` v1.3.6: Respect --dry-run for packet pacing; audit checks actual qdisc.

## [1.3.3] - 2025-12-16
## [1.3.5] - 2025-12-16

### Fixed

- `fasterdata-tuning.sh` v1.3.5: Sanitize legacy saved-state files during diff/restore by escaping raw tabs/carriage returns before JSON parsing. This allows `--diff-state` and `--restore-state` to consume single-line JSON files created with older versions that contain control characters.

## [1.3.4] - 2025-12-16
## [1.3.5] - 2025-12-16

### Fixed

- `fasterdata-tuning.sh` v1.3.5: Escape tabs and control characters in sysctl values (e.g., `net.ipv4.tcp_rmem`, `net.ipv4.tcp_wmem`) so saved-state JSON is valid and consumable by `--diff-state` and `--restore-state`.


### Fixed

- `fasterdata-tuning.sh` v1.3.4: Prevent corrupted (multi-line) JSON in saved states by quoting and sanitizing all string fields and robustly parsing `tuned-adm active`. This ensures state files are valid single-line JSON and fixes failures like two-line outputs.


### Fixed

- `fasterdata-tuning.sh` v1.3.3: Load saved-state JSON via Python and keep escapes intact so `--diff-state` and `--restore-state` correctly read saved values (no empty Saved fields or JSON validation errors).

## [1.2.0] - 2025-11-10
## [1.3.1] - 2025-12-12

### Fixed

- `fasterdata-tuning.sh` v1.3.1: Skip checksum offload validation on bond and VLAN interfaces (they delegate checksum support to member physical NICs). Prevents false positives in audit reports.

### Added

- `fasterdata-tuning.sh` v1.3.1: Add `--version`/`-v` option to print the script version.

## [1.3.0] - 2025-12-12

### Added

- Packet pacing guide: `docs/perfsonar/packet-pacing.md` (fq vs tbf, tuned interaction, verification steps); linked under Host Tuning in navigation.

### Changed

- `fasterdata-tuning.sh` v1.3.0:
  - Default packet pacing uses `fq` (Linux TCP pacing). New flags add optional interface cap via `tbf`:
    - `--use-tbf-cap` to enable `tbf`
    - `--tbf-cap-rate RATE` to set an explicit cap (deprecated alias: `--packet-pacing-rate`)
    - If `--use-tbf-cap` is set without a rate, a default cap of ~90% of the link speed is applied per interface
  - Audit recognizes both `fq` and `tbf` as “pacing applied”; other qdiscs are flagged
  - Audit output colorization: `fq` shown in green (preferred), `tbf` shown in cyan (acceptable when caps are intentional)
  - Systemd persist service mirrors applied behavior (fq by default; tbf with persisted rate when used)


### Added

- Release notes for Quick Deploy v1.4.0 (`docs/release-notes/quick-deploy-1.4.0.md`).
- New guided installer: `docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh`.
- Non-disruptive mode for PBR script: `docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh` defaults to in-place apply.
- CI: add dedicated code quality workflow for Markdown and Shell scripts.

### Changed

- Streamlined Quick Deploy Steps 1–3 with a single prerequisite install and orchestrator-first flow.
- Removed `sudo` prefixes from documentation examples and fixed markdownlint spacing issues.

### Deprecated

- `docs/perfsonar/tools_scripts/check-deps.sh` — see `DEPRECATION.md` for migration guidance.

## [1.1.0] - 2025-11-08

### Added

- Release notes for Quick Deploy v1.1.0 (`docs/release-notes/quick-deploy-1.1.0.md`)
- `docs/perfsonar/tools_scripts/DEPRECATION.md` (notes about deprecated helper)

### Changed

- Marked the current docs build as version `1.1.0` in `docs/versions.json`.
- Replaced `perfSONAR-extract-lsregistration.sh` with a deprecation stub and
  added guidance to prefer `perfSONAR-update-lsregistration.sh`.

## [1.0.1] - 2025-11-08

### Added

- Release notes for Quick Deploy v1.0.1 (`docs/release-notes/quick-deploy-1.0.1.md`)

### Changed

- Marked the current docs build as version `1.0.1` in `docs/versions.json`.
- Cleaned `docs/versions.json` formatting.

## [1.00] - 2025-11-08

### Added

- Quick Deploy documentation release v1.00 (see `docs/release-notes/quick-deploy-1.0.0.md`)
- `docs/perfsonar/tools_scripts/seed_testpoint_host_dirs.sh` helper script
- `docs/versions.json` updated to include 1.00

### Changed

- Updated container image references in Quick Deploy to `hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production`
- Replaced inline seeding snippet with helper invocation in `docs/personas/quick-deploy/install-perfsonar-testpoint.md`

## [0.9] - previous

- Prior quick-deploy documentation state preserved as `0.9` in `docs/versions.json`.
