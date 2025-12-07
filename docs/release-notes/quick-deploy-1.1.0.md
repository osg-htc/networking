---
title: Quick Deploy 1.1.0
---

# Release 1.1.0 — 2025-11-08

This release collects small documentation/tooling updates to the Quick Deploy guide and the perfSONAR tools bundle.

## Highlights

- Deprecation: `perfSONAR-extract-lsregistration.sh` has been deprecated and
removed from active maintenance. A short DEPRECATION.md explains the rationale and points users to `perfSONAR-update-
lsregistration.sh` for restores.

- New helper: `seed_testpoint_host_dirs.sh` (added previously) is the
recommended helper for seeding host directories from a short-lived perfSONAR testpoint container and certbot container.

- Versioning: the docs site `docs/versions.json` has been updated and the
  current site version is `1.1.0`.

- Installer update: `install_tools_scripts.sh` was updated to avoid fetching
the deprecated extractor and includes a comment pointing to the deprecation doc.

- Container image references in the Quick Deploy examples continue to point
  at `hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:production`.

## Notes for maintainers

- The repository now contains a `DEPRECATION.md` alongside the deprecated
script (which is replaced by a stub that emits the warning). If you want to preserve the full extractor implementation
for archival reasons, consider moving it to an `archive/` or `legacy/` folder and referencing it from the deprecation
doc.

- If you want a signed snapshot of the generated site attached to the GitHub
release, create the site build (`mkdocs build`), tar/gzip the `site/` directory, create a SHA256 (and optionally a GPG
detached signature), and upload the assets to the release.

## How to publish this release (suggested sequence)

1. Review the unstaged changes locally. If you accept them, commit them:

git add docs/versions.json docs/release-notes/quick-deploy-1.1.0.md docs/perfsonar/tools_scripts/DEPRECATION.md
docs/perfsonar/tools_scripts/perfSONAR-extract-lsregistration.sh docs/perfsonar/tools_scripts/install_tools_scripts.sh
CHANGELOG.md git commit -m "chore(release): prepare Quick Deploy v1.1.0; deprecate extractor"

1. Create an annotated tag for the release (replace DATE and notes as desired):

git tag -a v1.1.0 -m "Quick Deploy v1.1.0 — 2025-11-08"

1. Push commits and tags:

git push origin master git push origin v1.1.0

1. Build the site and create a snapshot (optional but recommended):

mkdocs build tar -czf site-quick-deploy-v1.1.0-$(date -u +%Y%m%dT%H%M%SZ).tar.gz site/ sha256sum site-quick-
deploy-v1.1.0-*.tar.gz > site-quick-deploy-v1.1.0.sha256

1. Create a GitHub release for `v1.1.0` and upload the snapshot and checksum.

If you want, I can perform the tagging and release creation for you — but you said you'll commit and push manually, so
I'm leaving those final steps to you.
