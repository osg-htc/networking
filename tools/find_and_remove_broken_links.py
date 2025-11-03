#!/usr/bin/env python3
"""
Scan Markdown files under docs/ for broken links and optionally remove them.

Behavior:
- By default, scans and writes a report to docs/BROKEN_LINKS_REPORT.md but does not modify files.
- Use --remove to backup and modify files (backups stored in --backup-dir).
- External links (http/https/mailto) are not checked unless --check-externals is provided.

This script intentionally avoids network checks by default to be safe in restricted
environments. It focuses on local relative links and obvious malformed URLs.

Usage:
  python docs/tools/find_and_remove_broken_links.py [--remove] [--backup-dir BACKUP] [--check-externals]

Output:
- docs/BROKEN_LINKS_REPORT.md : human-readable report with notes and suggested fixes.

"""
from __future__ import annotations

import argparse
import shutil
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

MD_ROOT = Path(__file__).parents[1]  # docs/
REPORT_PATH = MD_ROOT / "BROKEN_LINKS_REPORT.md"
BACKUP_DEFAULT = MD_ROOT / ".link_check_backups"

LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def normalize_href(href: str) -> str:
    href = href.strip()
    if href.startswith("<") and href.endswith(">"):
        href = href[1:-1].strip()
    return href


def is_external(href: str) -> bool:
    return href.startswith("http://") or href.startswith("https://") or href.startswith("mailto:")


def resolve_local_target(md_file: Path, href: str) -> Path:
    # Strip anchor
    href_no_anchor = href.split("#", 1)[0].split("?", 1)[0]
    if href_no_anchor == "":
        return Path("")
    href_path = Path(href_no_anchor)
    if href_path.is_absolute():
        # treat as repo-root relative
        repo_root = Path.cwd()
        return (repo_root / href_path.relative_to(href_path.anchor)).resolve()
    return (md_file.parent / href_path).resolve()


def scan_docs(check_externals: bool = False) -> Dict[Path, List[Tuple[str, str]]]:
    """Return mapping: md_file -> list of (link_text, href, reason) for broken/malformed links."""
    broken: Dict[Path, List[Tuple[str, str]]] = {}
    for md in MD_ROOT.rglob("*.md"):
        try:
            text = md.read_text(encoding="utf-8")
        except Exception:
            continue
        for m in LINK_RE.finditer(text):
            txt = m.group(1).strip()
            href_raw = m.group(2).strip()
            href = normalize_href(href_raw)

            # Obvious malformed
            if href == "" or href in ("http://", "https://", "http://)"):
                reason = "malformed or empty URL"
                broken.setdefault(md, []).append((txt, href + " (malformed)"))
                continue

            if is_external(href):
                if check_externals:
                    # Try a HEAD request if user asked for external checks.
                    # We avoid adding third-party deps; use urllib with timeout.
                    import urllib.request

                    try:
                        req = urllib.request.Request(href, method="HEAD")
                        with urllib.request.urlopen(req, timeout=5) as resp:
                            code = resp.getcode()
                        if code >= 400:
                            broken.setdefault(md, []).append((txt, f"{href} (HTTP {code})"))
                    except Exception as e:
                        broken.setdefault(md, []).append((txt, f"{href} (external check failed: {e})"))
                else:
                    # Mark as external - not checked. Not considered broken for automatic removal.
                    continue
            else:
                target = resolve_local_target(md, href)
                if not target or not target.exists():
                    broken.setdefault(md, []).append((txt, href))

    return broken


def make_backup(md: Path, backup_dir: Path) -> Path:
    rel = md.relative_to(MD_ROOT)
    dst = backup_dir / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    backup_path = dst.with_suffix(dst.suffix + f".bak.{ts}")
    shutil.copy2(md, backup_path)
    return backup_path


def remove_broken_links(broken_map: Dict[Path, List[Tuple[str, str]]], backup_dir: Path) -> None:
    for md, entries in broken_map.items():
        text = md.read_text(encoding="utf-8")
        # Build a set of hrefs to treat as broken in this file for quick checks
        broken_hrefs = {e[1] for e in entries}

        def repl(m: re.Match) -> str:
            txt = m.group(1).strip()
            href_raw = m.group(2).strip()
            href = normalize_href(href_raw)
            tag = href
            # For entries marked with '(malformed)' we keep original
            if any(href in bh or (href + " (malformed)") in bh for bh in broken_hrefs):
                # Replace the markdown link with plain text and append a note
                return f"{txt} [BROKEN-LINK: {href}]"
            return m.group(0)

        # backup
        backup_path = make_backup(md, backup_dir)
        new_text = LINK_RE.sub(repl, text)
        if new_text != text:
            md.write_text(new_text, encoding="utf-8")
            print(f"Patched {md} (backup: {backup_path})")


def write_report(broken_map: Dict[Path, List[Tuple[str, str]]]) -> None:
    lines: List[str] = []
    lines.append("# Broken Links Report\n")
    lines.append(f"Generated: {datetime.utcnow().isoformat()}Z\n")
    if not broken_map:
        lines.append("No broken local links detected (external links were not checked).\n")
        REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")
        print(f"Wrote report: {REPORT_PATH}")
        return

    for md, entries in sorted(broken_map.items()):
        rel = md.relative_to(MD_ROOT)
        lines.append(f"## {rel}\n")
        for txt, href in entries:
            suggestion = "Check target path or update to correct URL. If external, run script with --check-externals to test HTTP status."
            lines.append(f"- Link text: `{txt}` — href: `{href}` — {suggestion}\n")

    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote report: {REPORT_PATH}")


def main() -> None:
    p = argparse.ArgumentParser(description="Find and optionally remove broken links in docs/")
    p.add_argument("--remove", action="store_true", help="Backup and remove/replace broken links in-place")
    p.add_argument("--backup-dir", default=str(BACKUP_DEFAULT), help="Directory to store backups when --remove is used")
    p.add_argument("--check-externals", action="store_true", help="Attempt HTTP HEAD checks for external links (slow/network required)")
    args = p.parse_args()

    backup_dir = Path(args.backup_dir)
    if args.remove:
        backup_dir.mkdir(parents=True, exist_ok=True)

    print("Scanning markdown files under:", MD_ROOT)
    broken = scan_docs(check_externals=args.check_externals)
    write_report(broken)

    if args.remove and broken:
        remove_broken_links(broken, backup_dir)


if __name__ == "__main__":
    main()
