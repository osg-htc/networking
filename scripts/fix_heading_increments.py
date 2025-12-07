#!/usr/bin/env python3
"""Normalize heading increments in markdown files by ensuring heading levels only increase by one.
- If we see a jump from level N to level M where M > N+1, we adjust M to N+1.
- This is safer than global modifications and preserves structure.
Usage: python3 scripts/fix_heading_increments.py <file> [file...]
"""

import sys
import re
from pathlib import Path


heading_re = re.compile(r'^(\s*)(#{1,6})(\s+.*)$')


def fix_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    prev_level = 0
    for l in lines:
        m = heading_re.match(l)
        if m:
            indent, hashes, rest = m.groups()
            level = len(hashes)
            # If jumping more than one level, reduce it
            if prev_level and level > prev_level + 1:
                new_level = prev_level + 1
                out.append(f"{indent}{'#' * new_level}{rest}")
                prev_level = new_level
            else:
                out.append(l)
                prev_level = level
        else:
            out.append(l)
    new = '\n'.join(out) + '\n'
    if new != s:
        p.write_text(new)
        print('Adjusted headings in', p)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: fix_heading_increments.py <file> [file ...]')
        sys.exit(1)
    for arg in sys.argv[1:]:
        fix_file(Path(arg))
