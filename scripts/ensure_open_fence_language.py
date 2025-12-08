#!/usr/bin/env python3
"""Ensure opening fenced code blocks have a language (defaults to 'text').

This script will toggle through fences and add 'text' to opening fences where no
language was specified. It works conservatively and doesn't change closing fence lines.

Usage: python3 scripts/ensure_open_fence_language.py docs
"""
import sys
import os
import re
from pathlib import Path


def process_file(path: Path) -> bool:
    with path.open('r', encoding='utf-8') as fh:
        lines = fh.readlines()
    changed = False
    out = []
    in_fence = False
    fence_chars = None
    for line in lines:
        m = re.match(r"^(\s*)(`{3,}|~{3,})(\s*)(\w+)?\s*$", line)
        if m:
            indent, fence, spaces, lang = m.groups()
            if not in_fence:
                # opening fence
                if not lang:
                    out.append(f"{indent}{fence} text\n")
                    changed = True
                else:
                    out.append(line)
                in_fence = True
                fence_chars = fence
                continue
            else:
                # closing fence
                out.append(f"{indent}{fence}\n")
                in_fence = False
                fence_chars = None
                continue
        out.append(line)
    if changed:
        path.write_text(''.join(out), encoding='utf-8')
    return changed


def main():
    if len(sys.argv) < 2:
        print('Usage: ensure_open_fence_language.py <docs-root>')
        sys.exit(1)
    root = sys.argv[1]
    changed_files = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if not f.endswith('.md'):
                continue
            p = Path(dirpath) / f
            try:
                if process_file(p):
                    changed_files.append(str(p))
                    print('Patched fence opening language in', p)
            except Exception as e:
                print('Error processing', p, e)
    if changed_files:
        print('Modified files:')
        for f in changed_files:
            print(' -', f)


if __name__ == '__main__':
    main()
