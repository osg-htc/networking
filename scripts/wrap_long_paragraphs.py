#!/usr/bin/env python3
"""Wrap paragraph lines exceeding a threshold (default 120) for safety, ignoring code fences and lists.
Usage: python3 scripts/wrap_long_paragraphs.py <files...>
"""

import sys
import textwrap
import re
from pathlib import Path


def process_file(path: Path, width=120, threshold=200):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
    i = 0
    changed = False
    while i < len(lines):
        line = lines[i]
        if fence_re.match(line):
            # toggle and copy until closing fence
            out.append(line)
            in_fence = not in_fence
            i += 1
            continue
        if in_fence:
            out.append(line)
            i += 1
            continue
        # skip list items and headings
        if re.match(r"^\s*([-*+]\s+|\d+\.\s+|#)", line):
            out.append(line)
            i += 1
            continue
        # collect a paragraph
        para = [line]
        j = i + 1
        while j < len(lines) and lines[j].strip() and not fence_re.match(lines[j]) and not re.match(r"^\s*([-*+]\s+|\d+\.\s+|#)", lines[j]):
            para.append(lines[j])
            j += 1
        para_joined = ' '.join(l.strip() for l in para)
        if len(para_joined) > threshold:
            wrapped = textwrap.fill(para_joined, width=width)
            out.extend(wrapped.split('\n'))
            changed = True
        else:
            out.extend(para)
        i = j
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Wrapped paragraphs in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: wrap_long_paragraphs.py <file> [file ...]')
        sys.exit(1)
    for arg in sys.argv[1:]:
        process_file(Path(arg))
