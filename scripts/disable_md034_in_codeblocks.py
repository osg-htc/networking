#!/usr/bin/env python3
"""Detect code blocks containing bare URLs and wrap them with markdownlint disable/enable comments for MD034.
Usage: python3 scripts/disable_md034_in_codeblocks.py docs
"""

import re
import sys
from pathlib import Path


def has_bare_url(line):
    # simple detection of http(s) URLs not wrapped with angle brackets
    return bool(re.search(r'(?<![<\(\[])(https?://[^\s\)\]>]+)', line))


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    i = 0
    changed = False
    fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
    while i < len(lines):
        line = lines[i]
        if fence_re.match(line):
            # start of a code block
            fence_start = i
            fence_line = line
            out.append(line)
            i += 1
            found_bare_url = False
            # check inner lines
            inner_start = i
            while i < len(lines) and not fence_re.match(lines[i]):
                if has_bare_url(lines[i]):
                    found_bare_url = True
                out.append(lines[i])
                i += 1
            if i < len(lines):
                # closing fence
                if found_bare_url:
                    # insert disable comment before opening fence and enable after closing fence
                    out.insert(len(out) - (i - inner_start) - 1, '<!-- markdownlint-disable MD034 -->')
                    out.append('<!-- markdownlint-enable MD034 -->')
                    changed = True
                out.append(lines[i])
                i += 1
            continue
        out.append(line)
        i += 1
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Disabled MD034 for code blocks with bare URLs in', path)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: disable_md034_in_codeblocks.py <dir>')
        sys.exit(1)
    import os
    changed_files = []
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    if process_file(Path(os.path.join(dirpath, file))):
                        changed_files.append(Path(os.path.join(dirpath, file)))
    if changed_files:
        print('Files changed:', changed_files)
