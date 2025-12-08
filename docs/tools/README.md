# Link-check tools

This folder contains utilities to check and optionally clean up broken links in the `docs/` tree.

find_and_remove_broken_links.py

- Scans Markdown files under `docs/` for broken local links (relative links whose targets are missing).

- Writes a human-readable report to `docs/BROKEN_LINKS_REPORT.md`.

- By default it does not modify files. Use `--remove` to back up and patch files in-place.

- Example (dry run, just report):

```bash
python docs/tools/find_and_remove_broken_links.py
```

- Example (backup and remove broken links):

```bash
python docs/tools/find_and_remove_broken_links.py --remove --backup-dir docs/.link_check_backups
```

Notes:

- External (http/https/mailto) links are not checked by default. To enable external HTTP checks add `--check-externals`. This may be slow and requires network access.

- Backups are created per-file with timestamped `*.bak.YYYYMMDDTHHMMSSZ` suffix under the backup directory.

After running, inspect `docs/BROKEN_LINKS_REPORT.md` for the list of broken links and suggested fixes.
