Reorganize docs into persona-driven structure (Quick Deploy, Troubleshooter, Researcher)

Summary
- This branch scaffolds a persona-driven documentation layout under `docs/personas/` and adds templates and feature pages.
- Adds tooling to detect and safely repair broken links (`docs/tools/`). A broken-links report was generated and partially applied; backups are available under `docs/.link_check_backups/`.
- Adds a GitHub Actions workflow to run linting and build the MkDocs site and to run the docs link-check script in dry-run mode.

Files changed / added (high level)
- `docs/personas/` (landing pages and starters)
- `docs/features/` (feature guidance pages)
- `docs/templates/` (author templates)
- `docs/tools/` (link-checker and applier)
- `.github/workflows/docs-ci.yml` (this CI workflow)

Checklist
- [ ] Review content in `docs/personas/` and move or expand Quick Deploy quickstarts as needed
- [ ] Confirm link mapping entries in `docs/tools/link_mapping.json`
- [ ] Review mkdocs nav in `mkdocs.yml` and add any missing pages intentionally omitted
- [ ] Run the link-checker locally for a full (non-dry-run) pass before merging if you want the applier to touch files automatically

Notes
- The CI runs `mkdocs build --strict` so build warnings will fail the job. It also runs the link-checker in dry-run mode so PRs will report issues but not modify files.
- If you want the CI to automatically apply safe mapping changes, we should add a separate job with a bot account and commit permissions (not present in this workflow).

If you'd like, I can (a) open this PR as a draft (attempting now), and (b) add a CI job to run the applier in a non-destructive mode or open a second PR that applies safe fixes.

-- Automated draft created by tooling
