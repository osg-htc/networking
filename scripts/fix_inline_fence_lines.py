#!/usr/bin/env python3
"""Fix inline fence content for opening fences where code appears on same line as fence.
Moves any inline content after the fence language into first inner line for readability.

Usage: python3 scripts/fix_inline_fence_lines.py docs/perfsonar
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    i = 0
    fence_re = re.compile(r"^(\s*)(`{3,}|~{3,})(\s*\w+)?\s+(.*)$")
    while i < len(lines):
        line = lines[i]
        m = fence_re.match(line)
        if m:
            indent, fence_chars, lang, rest = m.groups()
            # If rest exists, we want to split line
            if rest and rest.strip():
                # rebuild the fence line without the rest; keep lang
                new_fence = f"{indent}{fence_chars}"
                if lang:
                    new_fence = f"{indent}{fence_chars} {lang.strip()}"
                out.append(new_fence)
                # add the rest as the next line
                out.append(rest.strip())
                i += 1
                continue
        out.append(line)
        i += 1

    new_content = '\n'.join(out) + '\n'
    if new_content != s:
        path.write_text(new_content)
        print('Fixed inline fence in', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: fix_inline_fence_lines.py <dir>')
        sys.exit(1)
    import os
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for file in filenames:
                if file.endswith('.md'):
                    process_file(Path(os.path.join(dirpath, file)))
