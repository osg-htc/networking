# Quick Deploy documentation — v1.0.1

Release date: 2025-11-08

This release contains small but important documentation fixes and housekeeping for the Quick Deploy guide.

Highlights

- Marked the current site build as version 1.0.1 (`docs/versions.json`).
- Cleaned `docs/versions.json` formatting so the versions list is valid JSON.
- Several doc improvements and clarifications were retained from the v1.00 work: the `seed_testpoint_host_dirs.sh` helper is referenced in the Quick Deploy Step 5 instructions, container image references were updated to `hub.opensciencegrid.org/osg-htc/perfsonar-testpoint:5.2.3-systemd`, and Step 6 enrollment guidance was consolidated and clarified.

Notes for operators

- The helper script `docs/perfsonar/tools_scripts/seed_testpoint_host_dirs.sh` remains available in the docs tree and is recommended when seeding host directories during deployment.
- The psconfig auto-enroll helper (`perfSONAR-auto-enroll-psconfig.sh`) skips RFC1918 addresses and logs discovered FQDNs — see Step 6 for sample usage.

If you need an actual release artifact (tag or site snapshot) created, tell me whether to create a tag (git tag) and/or prepare a static site snapshot for upload.
