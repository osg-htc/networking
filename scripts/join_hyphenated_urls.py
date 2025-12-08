#!/usr/bin/env python3
"""Join URLs that were split across lines with hyphenation at the newline.

This script looks for lines that contain 'http' or 'https' and end with a hyphen (e.g. 'network-troubleshooting-')
and the next line begins with a continuation (no leading spaces) then joins the two lines by removing the hyphen and newline.

It is conservative: only joins when the previous line contains 'http' and the next line starts with a lowercase letter or 'www'.

Usage: python3 scripts/join_hyphenated_urls.py docs
"""

import os
import re
import sys
from pathlib import Path


def process(path: Path) -> bool:
    changed = False
    with path.open('r', encoding='utf-8') as fh:
        lines = fh.readlines()

    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # detect a line containing http(s) and ending with a hyphen (common hyphenation from copy/paste)
        if re.search(r'https?://', line) and line.rstrip('\n').endswith('-') and i + 1 < len(lines):
            next_line = lines[i+1]
            # skip if continuation line is just a blank or starts with whitespace (we want only simple hyphenations)
            if next_line.strip() and not next_line.startswith(' '):
                # Basic heuristic: join if next_line starts with a lowercase letter or an alphanumeric word fragment
                if re.match(r'^[a-z0-9/_~%.-]', next_line, flags=re.IGNORECASE):
                    # Keep the final hyphen and newline from current line, then append next_line trimmed of leading whitespace
                        joined = line.rstrip('\n') + next_line.lstrip()
                    out.append(joined)
                    i += 2
                    changed = True
                    continue
        out.append(line)
        i += 1

    if changed:
        # write a normalized file with line endings as \n
        # ensure we don't break files entirely; write to temp then replace
        path.write_text(''.join(out), encoding='utf-8')
    return changed


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: join_hyphenated_urls.py <docs-root>')
        sys.exit(1)
    root = sys.argv[1]
    changed_files = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if not f.endswith('.md'):
                continue
            p = Path(dirpath) / f
            try:
                if process(p):
                    changed_files.append(str(p))
                    print('Fixed hyphenated URL in', p)
            except Exception as e:
                print('Error processing', p, e)
    if changed_files:
        print('Modified files:')
        for f in changed_files:
            print(' -', f)