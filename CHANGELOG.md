
# Changelog

All notable changes to this repository will be documented in this file.

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

- Updated container image references in Quick Deploy to `hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:5.2.3-systemd`
- Replaced inline seeding snippet with helper invocation in `docs/personas/quick-deploy/install-perfsonar-testpoint.md`

## [0.9] - previous

- Prior quick-deploy documentation state preserved as `0.9` in `docs/versions.json`.
