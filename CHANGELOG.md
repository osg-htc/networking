
# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this repository will be documented in this file.

## [1.3.3] - 2025-12-16
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
