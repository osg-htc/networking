#!/usr/bin/env python3
"""Collapse multiple blank lines (2+) to single blank line everywhere, including inside fences.

Usage: python3 scripts/collapse_blank_lines_global.py docs
"""

import sys
from pathlib import Path
import re


def process_file(path: Path):
    s = path.read_text()
    # collapse multiple blank lines globally
    final = re.sub(r"(\n\s*){2,}", "\n\n", s)
    if final != s:
        path.write_text(final)
        print('Global collapsed blanks in', path)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: collapse_blank_lines_global.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
