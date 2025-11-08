# Quick Deploy — v1.0.0 (Quick Deploy docs)

Release date: 2025-11-08

Summary
-------

This release packages the Quick Deploy documentation for perfSONAR Testpoint into a
formal v1.0.0 release. It contains the following user-facing changes and quality-of-life
improvements:

- Update container image references to use the OSG registry:
  - `hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:5.2.3-systemd` (replaced earlier ghcr.io references)
- Add `seed_testpoint_host_dirs.sh` helper to seed host directories from temporary containers
  - Installed at `docs/perfsonar/tools_scripts/seed_testpoint_host_dirs.sh` (also referenced in the Quick Deploy doc)
- Replace the inline host-directory seeding snippet in Step 5 (Option B) with a reference and usage examples for the helper script.
- Add site versions metadata (`docs/versions.json`) and make this release available as `1.00` in the version selector.
- Minor doc fixes and mkdocs rebuild to ensure consistent rendering.

Testing and verification
------------------------

- The site was rebuilt locally with `mkdocs build` and previewed to verify the Quick Deploy page renders and the helper script is linked.
- The helper script was tested for basic execution path (no destructive operations) by ensuring it can be created and marked executable.

Notes for reviewers
-------------------

- The release touches documentation only; there are no code or runtime behavior changes beyond helper scripts intended for operator convenience.
- Reviewers should confirm the image reference change and the helper script usage are correct for site deployment processes.

How to roll back
----------------

If you need to revert to the prior doc state, checkout the `master` commit prior to this branch and reapply changes selectively. The previous documented build is available as version `0.9` in `docs/versions.json`.
