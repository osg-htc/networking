#!/usr/bin/env python3
"""Ensure blank lines around headings and fenced code blocks outside frontmatter and inside/outside fence blocks.
Usage: python3 scripts/ensure_blank_around_headings_and_fences.py docs
"""

import re
import sys
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    in_frontmatter = False
    i = 0
    changed = False
    if len(lines)>0 and lines[0].strip() == '---':
        in_frontmatter = True
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if in_frontmatter:
            out.append(line)
            if stripped == '---' and i != 0:
                in_frontmatter = False
            i += 1
            continue
        # fence detection
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            # ensure blank line before opening fence
            if out and out[-1].strip() != '':
                out.append('')
                changed = True
            out.append(line)
            i += 1
            in_fence = not in_fence
            # copy inner lines unchanged until closing fence
            while i < len(lines) and not re.match(r"^\s*(`{3,}|~{3,})", lines[i]):
                out.append(lines[i])
                i += 1
            # closing fence
            if i < len(lines):
                out.append(lines[i])
                i += 1
            # add blank line after closing fence
            if i < len(lines) and lines[i].strip() != '':
                out.append('')
                changed = True
            continue
        # heading detection
        m = re.match(r"^\s*#{1,6}\s+", line)
        if m:
            # ensure blank before heading unless first line
            if out and len(out) > 0 and out[-1].strip() != '':
                out.append('')
                changed = True
            out.append(line)
            # ensure blank after heading if next non-empty is not heading/fence/list
            next_i = i+1
            while next_i < len(lines) and lines[next_i].strip() == '':
                next_i += 1
            if next_i < len(lines):
                nl = lines[next_i]
                if not re.match(r"^\s*(#{1,6}|(`{3,}|~{3,})|[*\-+]|\d+\.)", nl):
                    # we want a blank line after heading
                    out.append('')
                    changed = True
            i += 1
            continue
        # normal line
        out.append(line)
        i += 1
    final = '\n'.join(out)+"\n"
    if final != s:
        path.write_text(final)
        print('Added blank lines around headings/fences in', path)
        changed = True
    return changed

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: ensure_blank_around_headings_and_fences.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
