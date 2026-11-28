---
title: Website Management & Ops
description: Guidance for maintaining the OSG networking site and personae workflow
---

# Website Management & Operations

This page outlines recommended processes for building, publishing and managing the OSG Networking site (MkDocs) with a
focus on persona-based documentation. The goal is to maintain `docs/` as the single source of truth and manage generated
`site/` through CI.

## Overview

- Use `docs/` as canonical source of content.

- Build & verify with `mkdocs build` locally or via CI.

- Use CI to deploy to `gh-pages` or a hosted platform; avoid committing generated `site/` to the repo when possible.

## Local development & testing

1. Create a Python virtualenv and install dependencies:

~~~bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install mkdocs mkdocs-material pymdown-extensions
~~~

1. Run a local preview server:

~~~bash
mkdocs serve -a 0.0.0.0:8000
~~~

1. Build the site for local verification:

~~~bash
mkdocs build --clean -d site
~~~

## CI & Publishing

1. CI should run the following steps on PRs and pushes to `master`:

- `mkdocs build --clean` (fail on build errors)

- Run link checks and `verify-site-scripts.sh` (script checksums and version headers)

- Run `bash .github/scripts/update-script-checksums.sh` to update the `*.sha256` files and `scripts.sha256` when scripts change in docs, and commit them with the script.

1. CI publish step (if you want to auto-deploy): use `peaceiris/actions-gh-pages` or `JamesIves/github-pages-deploy-action` to publish the `site/` directory to the `gh-pages` branch or a host.

## Keep `docs/` canonical

- Prefer editing and reviewing changes to files under `docs/`.

- If you must edit `site/` (e.g., for manual content patches), follow the same review process and back-propagate changes into `docs/`.

## Persona content & operational workflow

- Persona pages live under `docs/personas/<persona>/` and should include the canonical `landing.md`, `intro.md`, and other materials.

- Owners and status metadata should be included in frontmatter (owner email or team, status: proposed/draft/stable). This helps review and governance.

## Actions we automated

- CI verification: `.github/scripts/verify-site-scripts.sh` (workflow `verify-site-scripts.yml`, on every PR and push to master) — checks every script in `docs/perfsonar/tools_scripts`: its `<script>.sha256` (`<sha256>  <script>`), the entries in `scripts.sha256`, and that the `# Version:` header matches a `VERSION=` variable. It only reads; it never commits.

- Checksum update (run locally): after changing a script, run `bash .github/scripts/update-script-checksums.sh` and commit the updated `*.sha256` files and `scripts.sha256` with the script. CI fails, and prints this command, when they are out of date.

## Migration / Next steps

1. Consider removing `site/` from the repo if CI deployment is configured and stable; commit `site/` removal with a PR that updates CI to publish built site to `gh-pages`.

1. Add a `web-site-management.md` page (this page) with step-by-step instructions for maintainers.

1. Add code owners for `docs/` and `personas` to ensure consistent review.

---

If anything in this workflow should be changed (e.g., we continue to check in site), we can adapt the CI accordingly to
keep both the ease of `site/` updates and code reviewing safeguards.
