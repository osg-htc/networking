#!/usr/bin/env python3
"""
Conservative fix for overly-indented lines inside admonitions that cause fenced code blocks
to render as literal backticks in the generated HTML.

Behavior:
- For each Markdown file under docs/, find lines starting with >=8 spaces that are followed by a
  fenced-code start (```... or ```). If the candidate line is within an admonition (a line containing
  '!!!' within the previous 8 lines), reduce leading spaces to exactly 4 spaces.
- For safety, this script creates backups under docs/.indent_fix_backups/

This is intentionally conservative and only adjusts narrative lines that likely caused preformatted
blocks to be created unintentionally.
"""
import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'docs'
BACKUP_DIR = ROOT / '.indent_fix_backups'
BACKUP_DIR.mkdir(parents=True, exist_ok=True)

LEADING_8_OR_MORE = re.compile(r'^(?P<space>\s{8,})(?P<content>\S.*)$')
FENCE_START = re.compile(r'^\s*```')
ADMON_LOOKBACK = 8

def is_inside_admon(lines, idx):
    # look back up to ADMON_LOOKBACK lines for a line starting with '!!!'
    start = max(0, idx-ADMON_LOOKBACK)
    for i in range(idx-1, start-1, -1):
        if lines[i].strip().startswith('!!!'):
            return True
    return False

def fix_file(path: Path) -> int:
    changed = 0
    with path.open('r', encoding='utf-8') as fh:
        lines = fh.readlines()

    new_lines = list(lines)
    i = 0
    while i < len(lines):
        line = lines[i]
        # match fenced code fence lines that are indented by >=4
        fence_m = re.match(r'^(?P<space>\s{4,})(?P<fence>```.*)$', line)
        if not fence_m:
            i += 1
            continue
        # find next non-empty line _after_ current
        j = i+1
        while j < len(lines) and lines[j].strip() == '':
            j += 1
        if j >= len(lines):
            i += 1
            continue
        # we already matched a fence; j is the next non-empty line after the fence
        # Check if this fence is inside an admonition
        if not is_inside_admon(lines, i+1):
            i += 1
            continue
        fence_start = i
        k = fence_start + 1
        fence_end = None
        while k < len(lines):
            if re.match(r'^\s*```', lines[k]):
                fence_end = k
                break
            k += 1
        if fence_end is None:
            i = k
            continue
        # For the region from fence_start..fence_end, compute minimal leading indent (excluding blank lines)
        min_indent = None
        for idx in range(fence_start, fence_end+1):
            s = lines[idx]
            if s.strip() == '':
                continue
            leading = len(s) - len(s.lstrip(' '))
            if min_indent is None or leading < min_indent:
                min_indent = leading
        if min_indent is None or min_indent < 4:
            i = fence_end + 1
            continue
        # Determine target indentation: inside admonition we want 4 spaces
        target_indent = 4
        delta = min_indent - target_indent
        if delta <= 0:
            i = fence_end + 1
            continue
        # Unindent the block by delta spaces
        for idx in range(i, fence_end+1):
            s = new_lines[idx]
            if s.startswith(' ' * delta):
                new_lines[idx] = s[delta:]
                changed += 1
        i = fence_end + 1
    if changed:
        # backup
        backup_path = BACKUP_DIR / (path.name + '.bak')
        shutil.copy2(path, backup_path)
        with path.open('w', encoding='utf-8') as fh:
            fh.writelines(new_lines)
    return changed

def find_md_files():
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if f.endswith('.md'):
                yield Path(dirpath) / f

def main():
    total_changes = 0
    for md in find_md_files():
        c = fix_file(md)
        if c:
            print(f"Adjusted {c} lines in {md}")
            total_changes += c
    print(f"Total changes: {total_changes}")

if __name__ == '__main__':
    main()
