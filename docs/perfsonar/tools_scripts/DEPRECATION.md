# DEPRECATED: perfSONAR-extract-lsregistration.sh

This helper script, `perfSONAR-extract-lsregistration.sh`, is deprecated and has been removed from active maintenance as
of the quick-deploy docs release v1.0.1.

## Why deprecated

* The functionality provided by this script is better covered by

`perfSONAR-update-lsregistration.sh` and by using the explicit configuration and restore workflow described in the
quick-deploy documentation and release notes.

## What to use instead

* For programmatic restores or to re-apply settings, use

`perfSONAR-update-lsregistration.sh` directly. See its `--help` output for supported flags and examples.

* The Quick Deploy release notes describe the recommended workflows and the

location of the updater script in the tools bundle: `docs/release-notes/quick-deploy-1.0.1.md` and `CHANGELOG.md` in the
repo root.

If you still depend on the old extractor script, please migrate to the updater-based workflow or open an issue in the
repository to discuss use cases that aren't covered.

## Contact

If you need assistance migrating, open an issue on the repository or contact the maintainers listed in the project's
`CHANGELOG.md` and release notes.
