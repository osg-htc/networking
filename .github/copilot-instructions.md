# Copilot Coding Agent Instructions

This repo is a MkDocs site for OSG Networking. Most work involves authoring Markdown in `docs/`, maintaining MkDocs config/theme, and managing perfSONAR-related shell tooling under `docs/perfsonar/tools_scripts/`. These instructions capture project-specific workflows and conventions to help you be immediately productive.

## Big Picture
- **Docs site:** Built with MkDocs Material. Config in `mkdocs.yml`; custom theme assets in `osgthedocs/` and extra CSS in `docs/css/extra.css`.
- **Content structure:** Primary docs live under `docs/` and are published to `site/` via CI (`gh-pages`). Do not edit `site/` manually; it is generated.
- **perfSONAR tooling:** Bash scripts and helpers under `docs/perfsonar/tools_scripts/` used by operators (e.g., multi-NIC config, systemd installer). Treat these as first-class code: lint with ShellCheck and keep usage docs in the adjacent `README.md`.
- **Automation & personas:** Task guides under `docs/personas/**` (Quick Deploy, Troubleshooter, Researcher). Keep nav in `mkdocs.yml` in sync with new/renamed pages.

## Core Workflows
- **Local preview:** Build and serve the site locally to verify nav and links.
  - Build: `mkdocs build`
  - Serve: `mkdocs serve -a 0.0.0.0:8000`
- **CI deploy:** GitHub Action `deploy-mkdocs.yml` deploys on pushes to `master` using `mkdocs gh-deploy`. No manual steps are required beyond committing changes.
- **Quality checks:** On PRs/pushes to `master`, `code-quality.yml` runs:
  - Markdown lint: `markdownlint` against `docs/**/*.md` and `DEPRECATION.md` using `.markdownlint.json`.
  - ShellCheck: targeted Bash scripts under `docs/perfsonar/tools_scripts/*.sh` and `scripts/*.sh` (excluding `check-deps.sh`). Keep scripts POSIX/Bash-clean.
- **Broken links tooling:** Use `docs/tools/find_and_remove_broken_links.py` to scan and optionally patch broken relative links.
  - Report only: `python docs/tools/find_and_remove_broken_links.py`
  - Patch with backups: `python docs/tools/find_and_remove_broken_links.py --remove --backup-dir docs/.link_check_backups`
  - Mapping and PR draft live under `docs/tools/`.

## Conventions & Patterns
- **Do not edit `site/`:** It is an output folder; changes will be overwritten by builds.
- **Navigation canonical source:** Add/remove pages in `mkdocs.yml` under `nav:`. Use human-friendly titles and correct paths in `docs/`.
- **Docs organization:** Prefer topical folders (e.g., `docs/perfsonar/`, `docs/network-troubleshooting/`, `docs/personas/...`). Keep filenames stable to avoid link rot; when moving, update links and run the broken link tool.
- **Examples in docs:** When referencing scripts or commands, use bash code fences and repository-relative paths (e.g., ``bash docs/perfsonar/tools_scripts/install_tools_scripts.sh``). Mirror usage examples found in `docs/perfsonar/tools_scripts/README.md`.
- **Bash scripts:**
  - Must be non-interactive-friendly (support flags like `--dry-run`, `--yes`).
  - Enforce root where required (this project’s scripts often assume root and do not invoke `sudo` internally).
  - Prefer NetworkManager (`nmcli`) for network config; provide fallbacks to `ip route`/`ip rule` when needed.
  - Document dependencies and distro-specific package names in the README adjacent to the script.
- **Ansible skeleton:** Under `ansible/` are example playbooks and roles used by personas/automation docs. If you change file paths relied on by docs (e.g., `creates:` for `tools_scripts/README.md`), update both the playbooks and the referenced docs.

## Key Integration Points
- **MkDocs Material:** Installed in CI; local devs should `pip install mkdocs mkdocs-material` if not present. Theme overrides live in `osgthedocs/`; keep Jinja-compatible structure if editing templates.
- **GitHub Pages:** Deployment uses `gh-pages` via `mkdocs gh-deploy`. Ensure the repository remote is set correctly; CI sets `safe.directory` and remote URL automatically.
- **External dependencies in docs:** Some pages reference tools like `podman`, `docker`, `NetworkManager`, `nftables`, etc. Keep instructions accurate for both RHEL/Fedora (`dnf`) and Debian/Ubuntu (`apt`) with tested install commands.

## Common Tasks (Examples)
- Add a new persona page and expose it in navigation:
  1. Create `docs/personas/quick-deploy/my-new-guide.md`.
  2. Add it under `nav:` in `mkdocs.yml` beneath the appropriate persona.
  3. Run `mkdocs build` and scan for broken links.
- Update a perfSONAR helper and its docs:
  1. Edit `docs/perfsonar/tools_scripts/install-systemd-service.sh`.
  2. Update `docs/perfsonar/tools_scripts/README.md` usage and requirements.
  3. Run ShellCheck locally: `shellcheck -S warning docs/perfsonar/tools_scripts/install-systemd-service.sh`.

## Gotchas
- `docs/` is the source of truth; `site/` mirrors the last build. If you see discrepancies, rebuild locally.
- ShellCheck in CI excludes `check-deps.sh`; do not rely on that for dependency validation in other scripts.
- Some docs pages reference auth-gated links; if a link cannot be made public, annotate it clearly rather than removing context. Use `docs/tools/link_mapping.json` to manage replacements.

## Pointers to Canonical Files
- `mkdocs.yml` — navigation, theme, and plugin config.
- `docs/perfsonar/tools_scripts/README.md` — authoritative usage and patterns for Bash helpers.
- `.github/workflows/deploy-mkdocs.yml` — CI deployment details.
- `.github/workflows/code-quality.yml` — linting for Markdown and Shell.
- `docs/tools/README.md` — broken link checker tooling.

If any of the above feels incomplete or unclear, tell us which section needs more detail (e.g., local dev environment setup, theme customization specifics, or Ansible workflow examples), and I’ll refine it.