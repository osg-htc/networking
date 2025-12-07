#!/usr/bin/env python3
"""Collapse multiple blank lines (2+) to single blank line outside fenced code blocks.

Usage: python3 scripts/collapse_blank_lines.py docs/perfsonar
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fence_pattern = re.compile(r"^\s*(`{3,}|~{3,})")
    prev_blank = False
    for line in lines:
        if fence_pattern.match(line):
            # toggle
            in_fence = not in_fence
            out.append(line)
            prev_blank = False
            continue
        if in_fence:
            out.append(line)
            prev_blank = False
            continue
        # Not in code fence
        if line.strip() == '':
            if prev_blank:
                # skip
                continue
            out.append('')
            prev_blank = True
            continue
        out.append(line)
        prev_blank = False
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Collapsed blanks in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: collapse_blank_lines.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
