#!/usr/bin/env python3
"""
Apply fixes listed in docs/BROKEN_LINKS_REPORT.md.

Behavior:
- Reads the report and for each entry replaces the markdown link in the listed source
  file with plain text and a short note (e.g. "[BROKEN-LINK: href]").
- Skips mailto: links by default. Use --remove-mailto to also replace mailto links.
- If a mapping JSON file is provided (--map map.json) it will update links to the
  provided new href instead of removing them.

Backups are stored under docs/.link_check_backups with timestamped suffixes.

Usage examples:
  python docs/tools/apply_link_report_fixes.py
  python docs/tools/apply_link_report_fixes.py --remove-mailto
  python docs/tools/apply_link_report_fixes.py --map mymap.json

"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

MD_ROOT = Path(__file__).parents[1]
REPORT = MD_ROOT / "BROKEN_LINKS_REPORT.md"
BACKUP_DIR = MD_ROOT / ".link_check_backups"
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def parse_report() -> Dict[Path, List[Tuple[str, str, str]]]:
    # returns mapping: file -> list of (link_text, href, raw_note)
    if not REPORT.exists():
        raise SystemExit(f"Report not found: {REPORT}")
    content = REPORT.read_text(encoding="utf-8")
    lines = content.splitlines()
    cur_file = None
    out: Dict[Path, List[Tuple[str, str, str]]] = {}
    entry_re = re.compile(r"- Link text: `([^`]+)` — href: `([^`]+)` — (.*)")
    file_re = re.compile(r"##\s+(.*)")
    for ln in lines:
        mfile = file_re.match(ln)
        if mfile:
            cur_file = (MD_ROOT / mfile.group(1)).resolve()
            out.setdefault(cur_file, [])
            continue
        m = entry_re.match(ln)
        if m and cur_file is not None:
            txt = m.group(1)
            href = m.group(2)
            note = m.group(3)
            out[cur_file].append((txt, href, note))
    return out


def backup_file(path: Path) -> Path:
    rel = path.relative_to(MD_ROOT)
    dst = BACKUP_DIR / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    backup = dst.with_suffix(dst.suffix + f".bak.{ts}")
    shutil.copy2(path, backup)
    return backup


def apply_changes(report_map: Dict[Path, List[Tuple[str, str, str]]], remove_mailto: bool, mapping: Dict[str, str]) -> None:
    for md_file, entries in report_map.items():
        if not md_file.exists():
            print(f"Warning: source file not found: {md_file}")
            continue
        text = md_file.read_text(encoding="utf-8")
        original = text

        def repl(m: re.Match) -> str:
            link_text = m.group(1).strip()
            href_raw = m.group(2).strip()
            href = href_raw
            # find matching entry
            matched = None
            for (txt, h, note) in entries:
                # allow match by href or by link text
                if h == href or txt == link_text:
                    matched = (txt, h, note)
                    break
            if not matched:
                return m.group(0)
            txt, h, note = matched
            # if mapping provided, update
            if h in mapping:
                new_href = mapping[h]
                return f"[{txt}]({new_href})"
            # mailto handling
            if href.startswith("mailto:") and not remove_mailto:
                return m.group(0)
            # if note indicates 401/403, mark requires auth
            if "HTTP Error 401" in note or "HTTP Error 403" in note:
                return f"{txt} (link requires authentication: {href})"
            # default: replace with plain text and BROKEN-LINK marker
            return f"{txt} [BROKEN-LINK: {href}]"

        new_text = LINK_RE.sub(repl, text)
        if new_text != original:
            bkp = backup_file(md_file)
            md_file.write_text(new_text, encoding="utf-8")
            print(f"Patched {md_file} (backup: {bkp})")


def load_mapping(path: Path) -> Dict[str, str]:
    if not path.exists():
        raise SystemExit(f"Mapping file not found: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: v for k, v in data.items()}


def main() -> None:
    p = argparse.ArgumentParser(description="Apply fixes from BROKEN_LINKS_REPORT.md")
    p.add_argument("--remove-mailto", action="store_true", help="Also remove mailto links listed in the report")
    p.add_argument("--map", type=str, help="JSON file mapping old_href -> new_href to update links instead of removing")
    args = p.parse_args()

    mapping = {}
    if args.map:
        mapping = load_mapping(Path(args.map))

    report_map = parse_report()
    if not any(report_map.values()):
        print("No entries found in report. Nothing to do.")
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    apply_changes(report_map, args.remove_mailto, mapping)


if __name__ == "__main__":
    main()
