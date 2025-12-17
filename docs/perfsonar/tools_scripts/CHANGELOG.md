## [1.3.2] - 2025-12-16

### Fixed

- **Critical JSON state save corruption fix**: Fixed invalid JSON generation in `--save-state` that caused `--restore-state` to fail
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

## [Unreleased] - 2025-12-16

### Changed

- **Installer:** `install_tools_scripts.sh` bumped to `1.0.1` and updated to fetch a fuller set of helper scripts and docs, and attempt to fetch accompanying `.sha256` checksum files when available.
- **lsregistration helper:** `perfSONAR-update-lsregistration.sh` now supports non-container (RPM) installs more robustly by attempting to restart the `perfsonar-lsregistrationdaemon` service name where present and falling back to `lsregistrationdaemon`, and will prefer the `perfsonar-` prefixed unit when restarting.
- **lsregistration helper:** Clarified `save` vs `extract` usage (save writes a raw `.conf` file; extract produces an executable restore script), and the `extract` output now attempts to apply `restorecon` to fix SELinux labels when run on hosts. The updater will attempt a `restorecon` after writing configuration locally or into a container when `restorecon` is available.

### Notes

- The `docs/perfsonar/tools_scripts` directory now includes updated `.sha256` checksum files for modified scripts. See the PR for details.

## [1.1.3] - 2025-12-06

### Fixed

- Corrected IOMMU audit messaging to suggest `grubby` for BLS systems (EL9+) and `grub2-mkconfig`/`update-grub` for legacy systems. Also bumped `fasterdata-tuning.sh` to v1.1.3 and updated site copy + checksums.

### Notes

- This is a minor documentation & diagnostic improvement; no new behavioral changes beyond clearer messaging and version bump.
