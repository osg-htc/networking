#!/usr/bin/env python3
"""Insert blank lines between lists and fenced code blocks.

Rules covered:
- If a list item is immediately followed by a code fence (indented or not), ensure there's a blank line between them.
- If a code fence is immediately followed by a list item, ensure there's a blank line between them.
- Normalize so CI's MD031/MD032 rules are satisfied where possible.

This script tries to be conservative: only inserts blank lines, never removes content or reflows lines.
"""

import re
import sys
from pathlib import Path

LIST_RE = re.compile(r"^\s*([-*+]\s+|\d+\.\s+)")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")


def process_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    changed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        # if this line is a list item
        if LIST_RE.match(line):
            out.append(line)
            # peek next line
            if i + 1 < len(lines) and lines[i + 1].strip() != "" and FENCE_RE.match(lines[i + 1]):
                # ensure a blank line after the list item
                out.append('')
                changed = True
            i += 1
            continue
        # if this line is a fence and the previous non-blank line was a list item
        if FENCE_RE.match(line):
            # ensure there's at least one blank line before this fence
            if out and out[-1].strip() != "" and not LIST_RE.match(out[-1]):
                # previous non-blank line was not a list item but also not blank -> insert blank
                # However, don't add extra blank if it's a heading separation script will handle it
                out.append('')
                changed = True
            out.append(line)
            i += 1
            # copy the fence body until we find a closing fence
            while i < len(lines) and not FENCE_RE.match(lines[i]):
                out.append(lines[i])
                i += 1
            if i < len(lines) and FENCE_RE.match(lines[i]):
                out.append(lines[i])
                i += 1
            # ensure blank line after closing fence (so it's separated from lists/paragraphs)
            if i < len(lines) and lines[i].strip() != "":
                out.append('')
                changed = True
            continue
        out.append(line)
        i += 1

    final = '\n'.join(out) + '\n'
    if final != s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: ensure_blank_between_lists_and_fences.py <dir>')
        sys.exit(1)
    import os
    changed = False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    p = Path(os.path.join(dirpath, f))
                    if process_file(p):
                        changed = True
    if changed:
        sys.exit(0)
    sys.exit(0)
