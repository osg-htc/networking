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
    replacements = defaultdict(list)  # file -> list of (lineNumber, editColumn, deleteCount, insertText)
    deletions = defaultdict(list)  # file -> list of (lineNumber, deleteCount)
    for rec in data:
        if 'fixInfo' not in rec or not rec['fixInfo']:
            continue
        fix = rec['fixInfo']
        # handle insertText-only fixes (e.g. MD031 blank-line insertions)
        # lineNumber is at the record level; prefer that
        lineNumber = rec.get('lineNumber')
        if lineNumber and 'insertText' in fix and 'editColumn' not in fix:
            insertions[rec['fileName']].append((lineNumber, fix['insertText']))
        # handle replacements with editColumn and deleteCount (e.g. MD034)
        elif lineNumber and 'editColumn' in fix and 'deleteCount' in fix and 'insertText' in fix:
            # store replacement operations as (lineNumber, editColumn, deleteCount, insertText)
            replacements[rec['fileName']].append((lineNumber, fix['editColumn'], fix['deleteCount'], fix['insertText']))
        # handle delete-only operations (e.g. MD012 delete extra blank lines)
        elif lineNumber and 'deleteCount' in fix and 'editColumn' not in fix:
            deletions[rec['fileName']].append((lineNumber, fix['deleteCount']))
    changed_files = []
    all_files = set(insertions.keys()) | set(replacements.keys()) | set(deletions.keys())
    for fname in all_files:
        ops = insertions.get(fname, [])
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
        # Now apply replacements and deletions if any
        # replacements: (line, col, deleteCount, insertText)
        repls = replacements.get(fname, [])
        if repls:
            # sort descending line numbers to avoid index shifts
            for ln, editCol, deleteCount, insertText in sorted(repls, key=lambda x: (x[0], x[1]), reverse=True):
                idx = ln - 1
                if idx < 0 or idx >= len(lines):
                    continue
                line = lines[idx]
                col = max(editCol - 1, 0)
                if deleteCount > 0:
                    new_line = line[:col] + insertText + line[col + deleteCount:]
                else:
                    # negative deleteCount: interpret as special case to replace a substring starting at col
                    new_line = line[:col] + insertText + line[col:]
                lines[idx] = new_line
        del_ops = deletions.get(fname, [])
        if del_ops:
            # For negative deleteCount we will collapse consecutive blank lines into a single blank line
            for ln, deleteCount in sorted(del_ops, key=lambda x: x[0], reverse=True):
                if deleteCount < 0:
                    new_lines = []
                    in_code = False
                    blank_run = 0
                    for l in lines:
                        if l.strip().startswith('```'):
                            # toggle code fence state
                            in_code = not in_code
                            new_lines.append(l)
                            blank_run = 0
                            continue
                        if in_code:
                            new_lines.append(l)
                            continue
                        if l.strip() == '':
                            blank_run += 1
                            if blank_run <= 1:
                                new_lines.append(l)
                            else:
                                # skip extra blank line
                                continue
                        else:
                            blank_run = 0
                            new_lines.append(l)
                    lines = new_lines
                elif deleteCount > 0:
                    idx = ln - 1
                    # remove 'deleteCount' characters from the line starting at idx
                    if 0 <= idx < len(lines):
                        line = lines[idx]
                        lines[idx] = line[:0] + line[deleteCount:]
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
