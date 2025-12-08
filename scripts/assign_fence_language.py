#!/usr/bin/env python3
"""Assign a likely language to opening fenced code blocks that have no language.

This is conservative: it uses simple heuristics to detect shell/bash, yaml, json,
html blocks and otherwise defaults to a neutral 'text' language so markdownlint's
MD040 and similar rules will be satisfied without changing semantics.

Usage: python3 scripts/assign_fence_language.py <docs-root>
"""
import sys
import os
import re
from pathlib import Path


def detect_lang(lines):
    """Heuristic detection of language from a list of lines (code block content).
    Returns: language string (bash|yaml|json|html|text)
    """
    joined = '\n'.join(lines).strip()
    if not joined:
        return 'text'
    # Common shell hints
    if re.search(r'(^|\n)\s*(sudo |\$ |#\!|apt-get|yum |dnf |systemctl |service )', joined):
        return 'bash'
    if re.search(r'(^|\n)\s*(apiVersion:|kind:|metadata:|---\n|: )', joined):
        return 'yaml'
    if re.search(r'\{\s*"|"\s*:\s*|}\s*$', joined):
        # naive json detection: contains quotes and colon or braces
        if re.search(r'["\{\}\[\]]', joined):
            return 'json'
    if re.search(r'<\/?[a-zA-Z]+[^>]*>', joined):
        return 'html'
    # detectable code pattern: package.json, npm, etc
    if re.search(r'(npm install|pip install|python -m|node -v|npm -v)', joined):
        return 'bash'
    return 'text'


def process_file(p: Path):
    text = p.read_text(encoding='utf-8')
    lines = text.splitlines()
    out = []
    changed = False
    i = 0
    fence_re = re.compile(r'^(\s*)(`{3,}|~{3,})(\s*)(\w+)?\s*$')
    while i < len(lines):
        line = lines[i]
        m = fence_re.match(line)
        if m:
            indent, fence, spaces, lang = m.groups()
            if lang:
                out.append(line)
                i += 1
                # inside fence until closing
                while i < len(lines) and not fence_re.match(lines[i]):
                    out.append(lines[i])
                    i += 1
                if i < len(lines):
                    # closing fence
                    out.append(lines[i])
                    i += 1
                continue
            else:
                # gather block content until closing fence
                content_lines = []
                j = i + 1
                while j < len(lines) and not fence_re.match(lines[j]):
                    content_lines.append(lines[j])
                    j += 1
                lang_guess = detect_lang(content_lines)
                out.append(f"{indent}{fence} {lang_guess}")
                changed = True
                # append content lines
                while i + 1 < len(lines) and not fence_re.match(lines[i + 1]):
                    i += 1
                    out.append(lines[i])
                # now we expect a closing fence possibly
                if i + 1 < len(lines) and fence_re.match(lines[i + 1]):
                    i += 1
                    out.append(lines[i])
                i += 1
                continue
        out.append(line)
        i += 1
    if changed:
        p.write_text('\n'.join(out) + '\n', encoding='utf-8')
        print('Patched fence languages in', p)
    return changed


def main():
    if len(sys.argv) < 2:
        print('Usage: assign_fence_language.py <docs-root>')
        sys.exit(1)
    root = Path(sys.argv[1])
    changed = []
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if not f.endswith('.md'):
                continue
            p = Path(dirpath) / f
            try:
                if process_file(p):
                    changed.append(str(p))
            except Exception as e:
                print('Error', p, e)
    if changed:
        print('Files changed:')
        for c in changed:
            print(' -', c)


if __name__ == '__main__':
    main()
