# Title: docs: fix broken links using automated mapping

## Body

### Summary

Applied `docs/tools/link_mapping.json` to replace BROKEN-LINK markers with updated targets. Backups were created under
`docs/.link_check_backups/`. This branch contains changes to documentation where broken links were replaced with mapped
targets or annotated when the resource requires authentication.

### Files changed

- `docs/index.md`

- `docs/network-troubleshooting/osg-debugging-document.md`

- `docs/perfsonar/install-testpoint.md`

- `docs/perfsonar/psetf.md`

- `docs/perfsonar/tools_scripts/README.md`

- `docs/perfsonar/tools_scripts/perfSONAR-pbr-nm.sh`

### Details

- Replaced internal placeholders and gated links with public or stable alternatives where possible using the mapping file `docs/tools/link_mapping.json`.

- For external links that returned 401/403 the script replaced them with plain text indicating "link requires authentication" rather than removing them.

- Mailto entries were handled according to the mapping; the applier was run with `--remove-mailto` earlier to remove leftover mailto links, and mapping can re-add them if desired.

### Backups

Each modified file has a timestamped backup under `docs/.link_check_backups/` with suffix `.bak.YYYYMMDDTHHMMSSZ`.

### Testing

1. Preview the site locally (mkdocs) to ensure no rendering regressions.

1. Run the docs link-check tool in dry-run to find remaining issues:

```bash python docs/tools/find_and_remove_broken_links.py --check-externals
```text

### Notes / Next steps

- Please review replaced URLs for accuracy; some mappings point to public equivalents (e.g., kernel docs) that may not be the preferred internal references.

- If any replacements are incorrect, they can be changed by editing `docs/tools/link_mapping.json` and re-running the applier.

- Consider adding a GitHub Actions workflow to run the link-checker on PRs to prevent regressions.

### Reviewer suggestions

- Confirm the chosen public replacements for gated resources (Red Hat docs, internal dashboards).

- Verify that the perfSONAR psetf and ETF references point to appropriate public pages or internal artifacts depending on access requirements.
