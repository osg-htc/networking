#!/usr/bin/env python3
"""Fix split words across lines inside paragraphs.
Heuristic: when a non-fenced/non-list line ends in a letter and the next non-empty line begins with a letter (no punctuation), join them without space.

Usage: python3 scripts/fix_split_words.py docs/perfsonar
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
    in_fence = False
    i = 0
    changed = False
    while i < len(lines):
        line = lines[i]
        if fence_re.match(line):
            out.append(line)
            in_fence = not in_fence
            i += 1
            continue
        if in_fence:
            out.append(line)
            i += 1
            continue
        # if this line ends with a letter and the next line starts with a letter, join them
        if i+1 < len(lines) and line.strip() and not re.match(r"^\s*([-*+]\s+|\d+\.\s+|#)", line):
            next_line = lines[i+1]
            if next_line.strip() and not re.match(r"^\s*([-*+]\s+|\d+\.\s+|#)", next_line):
                last_char = line.rstrip()[-1] if line.rstrip() else ''
                first_char = next_line.lstrip()[0] if next_line.lstrip() else ''
                if last_char.isalpha() and first_char.isalpha():
                    # merge lines without spaces
                    merged = line.rstrip() + next_line.lstrip()
                    out.append(merged)
                    i += 2
                    changed = True
                    continue
        out.append(line)
        i += 1
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Fixed split words in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: fix_split_words.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
