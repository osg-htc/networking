#!/usr/bin/env python3
"""Apply simple fixes suggested in markdownlint JSON results.

This script reads the JSON output from markdownlint (--json) and applies the 'fixInfo' operations
where possible (e.g., insertText at lineNumber). Only applies insertText to the specified lines, which will
be empty lines to fix MD031/MD032 mostly.

Usage: python3 scripts/apply_markdownlint_fixes.py /path/to/markdownlint.json
"""

import json
import sys
from collections import defaultdict
from pathlib import Path


def apply_fixes(json_file):
    with open(json_file, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    # Collect insertions per file
    insertions = defaultdict(list)  # file -> list of (lineNumber, insertText)
    for rec in data:
        if 'fixInfo' not in rec or not rec['fixInfo']:
            continue
        fix = rec['fixInfo']
        if 'lineNumber' in fix and 'insertText' in fix:
            insertions[rec['fileName']].append((fix['lineNumber'], fix['insertText']))
    changed_files = []
    for fname, ops in insertions.items():
        path = Path(fname)
        if not path.exists():
            continue
        # sort descending so line number insertions don't invalidate subsequent offsets
        ops_sorted = sorted(ops, key=lambda x: x[0], reverse=True)
        content = path.read_text()
        lines = content.splitlines()
        for ln, insertText in ops_sorted:
            # markdownlint uses 1-indexed lines; we will insert before that line number, or at end
            idx = ln - 1
            if idx < 0:
                idx = 0
            if idx > len(lines):
                idx = len(lines)
            # only insert if line isn't already blank
            if idx < len(lines) and lines[idx].strip() == '':
                continue
            # insert the given text as a line (some fixes want '\n' only)
            t = insertText
            if t.endswith('\n'):
                t = t[:-1]
            if t == '':
                lines.insert(idx, '')
            else:
                # If insertText contains multiple lines (rare), insert them split
                for ins in reversed(t.split('\n')):
                    lines.insert(idx, ins)
        new_content = '\n'.join(lines) + '\n'
        if new_content != content:
            path.write_text(new_content)
            changed_files.append(str(path))
            print('Patched', path)
    return changed_files

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: apply_markdownlint_fixes.py <markdownlint-json>')
        sys.exit(1)
    changed = apply_fixes(sys.argv[1])
    if changed:
        print('Files changed:')
        for c in changed:
            print(' -', c)
