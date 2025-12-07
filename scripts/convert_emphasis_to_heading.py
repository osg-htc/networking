#!/usr/bin/env python3
"""Convert emphasis-only lines like '*Edited by: someone*' to headings (H3) where safe.
Usage: python3 scripts/convert_emphasis_to_heading.py docs/network-troubleshooting/osg-debugging-document.md
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    changed = False
    for line in lines:
        # if a line is solely enclosed in emphasis markers like *text* or _text_, convert
        m = re.match(r"^\s*([*_])([^*_].*?)\1\s*$", line)
        if m:
            content = m.group(2).strip()
            # Only convert if the content is short and not code-like
            if len(content) < 120 and not content.startswith('http') and '<' not in content:
                out.append('### ' + content)
                changed = True
                continue
        out.append(line)
    final = '\n'.join(out)+"\n"
    if final != s:
        path.write_text(final)
        print('Converted emphasis to headings in', path)
    return changed

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: convert_emphasis_to_heading.py <file> [file ...]')
        sys.exit(1)
    for arg in sys.argv[1:]:
        process_file(Path(arg))
