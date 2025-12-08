#!/usr/bin/env python3
"""Patch MD040 (fenced-code-language) occurrences using markdownlint JSON and heuristics.

This script uses the JSON output from markdownlint with MD040 occurrences and attempts to set a sensible
language on the opening fence using the heuristic detect_lang function.

Usage: python3 scripts/fix_md040_from_json.py tmp/markdownlint_round8.json
"""
import json
import sys
import re
from pathlib import Path


def detect_lang(lines):
    joined = '\n'.join(lines).strip()
    if not joined:
        return 'text'
    if re.search(r'(^|\n)\s*(sudo |\$ |#\!|apt-get|yum |dnf |systemctl |service |curl |wget )', joined):
        return 'bash'
    if re.search(r'(^|\n)\s*(apiVersion:|kind:|metadata:|---\n|: )', joined):
        return 'yaml'
    if re.search(r'["\{\}\[\]]', joined) and re.search(r':\s*"', joined):
        return 'json'
    if re.search(r'<\/?[a-zA-Z]+[^>]*>', joined):
        return 'html'
    if re.search(r'(npm install|pip install|python -m|node -v|npm -v)', joined):
        return 'bash'
    return 'text'


def find_opening_fence_index(lines, closing_idx):
    fence_re = re.compile(r'^(\s*)(`{3,}|~{3,})(\s*)(\S+)?\s*$')
    # find nearest previous fence that is an opening fence (i.e. matches and not currently inside a fence when scanning backward)
    in_fence = False
    for i in range(closing_idx - 1, -1, -1):
        m = fence_re.match(lines[i])
        if m:
            indent, fence, spaces, lang = m.groups()
            if not in_fence:
                # this is an opening fence candidate
                return i
            else:
                # we are inside a fence and found another fence; flip state
                in_fence = False
    return None


def patch_file_for_md040(fname, lineno):
    p = Path(fname)
    lines = p.read_text(encoding='utf-8').splitlines()
    closing_idx = lineno - 1
    opening_idx = find_opening_fence_index(lines, closing_idx)
    if opening_idx is None:
        return False
    # check if opening already has a language
    m = re.match(r'^(\s*)(`{3,}|~{3,})(\s*)(\S+)?\s*$', lines[opening_idx])
    if not m:
        return False
    indent, fence, spaces, lang = m.groups()
    if lang:
        return False
    # gather block content lines to detect language
    content_lines = []
    j = opening_idx + 1
    fence_end_re = re.compile(r'^\s*(`{3,}|~{3,})\s*$')
    while j < len(lines) and not fence_end_re.match(lines[j]):
        content_lines.append(lines[j])
        j += 1
    guessed = detect_lang(content_lines)
    # apply patch by inserting language after opening fence
    lines[opening_idx] = f"{indent}{fence} {guessed}"
    p.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('Patched md040 in', fname, 'line', opening_idx + 1, '->', guessed)
    return True


def main():
    if len(sys.argv) != 2:
        print('Usage: fix_md040_from_json.py <markdownlint-json>')
        sys.exit(1)
    data = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
    md040s = [ rec for rec in data if ('MD040' in rec.get('ruleNames', []) or 'fenced-code-language' in rec.get('ruleNames', []) ) ]
    patched_files = []
    for rec in md040s:
        fname = rec['fileName']
        ln = rec['lineNumber']
        try:
            if patch_file_for_md040(fname, ln):
                patched_files.append(fname)
        except Exception as e:
            print('Error processing', fname, ln, e)
    if patched_files:
        print('Patched files:')
        for f in sorted(set(patched_files)):
            print(' -', f)


if __name__ == '__main__':
    main()
