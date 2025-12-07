#!/usr/bin/env python3
"""Reflow paragraph text in list items to a given width preserving list markers.
Usage: python3 scripts/reflow_list_paragraphs.py <files...>
"""

import re
import sys
from pathlib import Path
import textwrap


def reflow(path: Path, width=120):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    i = 0
    fence_re = re.compile(r"^\s*(`{3,}|~{3,})")
    in_fence = False
    while i < len(lines):
        line = lines[i]
        if fence_re.match(line):
            out.append(line)
            in_fence = not in_fence
            i += 1
            continue
        if in_fence:
            out.append(line)
            i += 1
            continue
        m = re.match(r"^(\s*)([-*+]|\d+\.)(\s+)(.+)$", line)
        if m:
            indent, marker, sp, rest = m.groups()
            # collect continuation lines that belong to the list item (indented or not starting a new marker)
            item_lines = [rest]
            j = i+1
            while j < len(lines) and lines[j].strip() != '':
                if re.match(r"^\s*([-*+]|\d+\.)\s+", lines[j]):
                    break
                # strip leading indentation for continuation line
                item_lines.append(lines[j].strip())
                j += 1
            para_text = ' '.join(l.strip() for l in item_lines)
            if len(para_text) > 120:
                # wrap with initial indent marker + space, subsequent indent align with marker
                initial = f"{indent}{marker} "
                subsequent = ' ' * len(initial)
                wrapped = textwrap.fill(para_text, width=width, initial_indent=initial, subsequent_indent=subsequent)
                out.extend(wrapped.splitlines())
            else:
                out.append(line)
                for k in range(i+1, j):
                    out.append(lines[k])
            i = j
            continue
        out.append(line)
        i += 1
    final = '\n'.join(out) + '\n'
    if final != s:
        path.write_text(final)
        print('Reflowed list paragraphs in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: reflow_list_paragraphs.py <file> [file ..]')
        sys.exit(1)
    for f in sys.argv[1:]:
        reflow(Path(f))
