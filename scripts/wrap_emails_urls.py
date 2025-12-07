#!/usr/bin/env python3
"""Wrap bare http(s) URLs and emails in angle brackets outside fenced code blocks.
Usage: python3 scripts/wrap_emails_urls.py docs
"""

import re
import sys
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
    changed = False

    url_re = re.compile(r'(?<![\(<\[])https?://[^\s)\]>]+')
    email_re = re.compile(r'(?<![<\w/])([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})')
    for line in lines:
        if fence_re.match(line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        new_line = url_re.sub(lambda m: '<'+m.group(0)+'>', line)
        new_line = email_re.sub(lambda m: '<'+m.group(0)+'>', new_line)
        if new_line != line:
            changed = True
        out.append(new_line)
    final = '\n'.join(out)+"\n"
    if final != s:
        path.write_text(final)
        print('Wrapped emails/urls in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: wrap_emails_urls.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
