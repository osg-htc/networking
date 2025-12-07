#!/usr/bin/env python3
"""Join hyphenated URLs incorrectly split across lines, inside or outside angle brackets.
Example: <https://domain/path/long-
part>  -> make it <https://domain/path/long-part>

Usage: python3 scripts/join_hyphenated_urls.py docs/perfsonar
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    i = 0
    changed = False
    while i < len(lines):
        line = lines[i]
        # find hyphenated URLs at end of line (within angle brackets or plain)
        # pattern: end with 'https://...-' or '...-'
        hyphen_url = re.search(r"(https?://[^\s<>]*(?:-)$)", line)
        if hyphen_url:
            base = line[:hyphen_url.start(1)] + hyphen_url.group(1)[:-1]
            # gather next lines until we see a continuation part (start with ascii char)
            j = i + 1
            rest = ''
            while j < len(lines) and lines[j].strip() != '':
                # take the first token on next line
                token = lines[j].strip()
                # append the token until it completes the URL (ends with '/ >' or similar)
                rest += token
                j += 1
                break
            if rest:
                new_line = base + rest
                # re-add trailing content if angle-bracket wrapper present
                out.append(new_line)
                i = j
                changed = True
                continue
        out.append(line)
        i += 1
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Joined hyphenated URL in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: join_hyphenated_urls.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
