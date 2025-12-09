#!/usr/bin/env python3
"""Fix indentation of content following `???` or `!!!` admonitions in a markdown file.

This script conservatively indents the immediate subsequent lines by 4 spaces until a block boundary is reached.
It is intentionally conservative: it forbids changing headings, top-level lists, fences, or other admonitions.

Usage: python3 scripts/fix_admonition_indent.py <file.md>
"""
import sys
import re
from pathlib import Path


def is_boundary(line):
    """Return True if the line marks the end of the admonition block (e.g., top-level heading, top-level list, top-level fence).
    We consider the line a boundary if it starts (after possible leading whitespace) with: '#', '---', '```', '???', '!!!', or a top-level numbered/bulleted list.
    """
    s = line.rstrip('\n')
    # remove leading spaces
    L = s.lstrip()
    if not L:
        # if empty: not a boundary by itself
        return False
    if L.startswith('#'):
        return True
    if L.startswith('---'):
        return True
    if L.startswith('```'):
        # top-level fence; stop.
        # If it is indented (i.e., line not equal to L), we'll consider it part of the admonition
        # but only stop if the fence is at column 0, which means L==s
        if s == L:
            return True
        return False
    if L.startswith('???') or L.startswith('!!!'):
        return True
    if re.match(r'^\d+\.\s', L):
        return True
    if re.match(r'^[-\*+]\s', L) and s == L:  # top-level bullet
        return True
    return False


def run(filepath: Path):
    text = filepath.read_text(encoding='utf-8')
    lines = text.splitlines()
    changed = False
    out_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out_lines.append(line)
        m = re.match(r'^(\s*)(\?\?\?|!\!\!)\s+', line)
        if m:
            # Found an admonition marker. Indent subsequent non-boundary lines by 4 spaces
            indent = m.group(1) or ''
            j = i + 1
            while j < len(lines):
                nxt = lines[j]
                # if this is a boundary at column 0 (no leading spaces), break
                if is_boundary(nxt):
                    break
                # if the line is already indented beyond admonition indent -> it's likely fine
                if nxt.startswith(indent + '    '):
                    out_lines.append(nxt)
                else:
                    # add 4 spaces to indent
                    out_lines.append(indent + '    ' + nxt)
                    changed = True
                j += 1
            # skip j lines we've just processed
            i = j
            continue
        i += 1
    if changed:
        filepath.write_text('\n'.join(out_lines) + '\n', encoding='utf-8')
        print('Patched admonition indentation in:', filepath)
    else:
        print('No changes needed for', filepath)
    return changed


def main():
    if len(sys.argv) < 2:
        print('Usage: fix_admonition_indent.py <file.md>')
        sys.exit(1)
    p = Path(sys.argv[1])
    if not p.exists():
        print('File not found:', p)
        sys.exit(2)
    run(p)


if __name__ == '__main__':
    main()
