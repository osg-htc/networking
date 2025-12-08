#!/usr/bin/env python3
"""Normalize indentation of fenced code block openings and closings.

This script ensures that opening and closing fences have matching indentation.
It is conservative and only adjusts closing fences to match the last unmatched opening fence.

Usage: python3 scripts/normalize_fence_indent.py docs
"""
import sys
import os
import re
from pathlib import Path


def process_file(path: Path):
    changed = False
    lines = path.read_text(encoding='utf-8').splitlines()
    out = []
    fence_re = re.compile(r'^(\s*)(`{3,}|~{3,})(.*)$')
    stack = []  # list of (indent, fence)
    for line in lines:
        m = fence_re.match(line)
        if m:
            indent, fence, rest = m.groups()
            if not stack:
                # opening fence
                stack.append((indent, fence))
                out.append(line)
            else:
                # We might be closing if fence equals the opening fence string (``` or ~~~)
                open_indent, open_fence = stack[-1]
                if fence == open_fence:
                    # this is closing fence — normalize indentation to match opening indent
                    if indent != open_indent:
                        out.append(open_indent + fence + rest)
                        changed = True
                    else:
                        out.append(line)
                    stack.pop()
                else:
                    # found a new opening fence while already in one
                    stack.append((indent, fence))
                    out.append(line)
        else:
            out.append(line)
    if changed:
        path.write_text('\n'.join(out) + '\n', encoding='utf-8')
        print('Normalized fence indentation in', path)
    return changed


def main():
    if len(sys.argv) < 2:
        print('Usage: normalize_fence_indent.py <docs-root>')
        sys.exit(1)
    root = Path(sys.argv[1])
    changed_files = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if not f.endswith('.md'):
                continue
            p = Path(dirpath) / f
            try:
                if process_file(p):
                    changed_files.append(str(p))
            except Exception as e:
                print('Error processing', p, e)
    if changed_files:
        print('Files modified:')
        for c in changed_files:
            print(' -', c)


if __name__ == '__main__':
    main()
