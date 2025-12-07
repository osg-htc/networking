#!/usr/bin/env python3
"""Convert multi-line <img> tags into markdown image syntax across perfsonar docs.
Usage: python3 scripts/convert_multiline_imgs.py docs/perfsonar/<file> ...
"""
import re
import sys
from pathlib import Path


def convert_file(p:Path):
    s = p.read_text()
    if '<img' not in s:
        return False
    # rejoin multi-line img tags first
    s = re.sub(r'<img\s+([^>]*?)\s+\n\s*([^>]*?)>', lambda m: f"<img {m.group(1)} {m.group(2)}>" , s, flags=re.IGNORECASE)
    # convert single-line img tags to markdown: capture src and alt
    def img_to_md(m):
        attrs = m.group(1)
        # find src
        src_m = re.search(r'src\s*=\s*"([^"]+)"', attrs)
        alt_m = re.search(r'alt\s*=\s*"([^"]*)"', attrs)
        src = src_m.group(1) if src_m else ''
        alt = alt_m.group(1) if alt_m else ''
        return f'![{alt}]({src})' if src else m.group(0)
    s_new = re.sub(r'<img\s+([^>]+)>', img_to_md, s, flags=re.IGNORECASE)
    if s_new != s:
        p.write_text(s_new)
        print('Converted images in', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: convert_multiline_imgs.py <file> [file...]')
        sys.exit(1)
    changed = False
    for arg in sys.argv[1:]:
        if convert_file(Path(arg)):
            changed = True
    if changed:
        print('Done')
    else:
        print('No changes')
