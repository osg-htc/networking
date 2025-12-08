#!/usr/bin/env python3
"""Fix code block closing fences that accidentally include a language name (e.g. "```text").

This script scans markdown files and replaces closing fences that include a language with a plain closing fence (e.g. '```').
This avoids broken blocks when people accidentally copy/paste or type the closing fence with language.
"""

import re
import sys
from pathlib import Path

FENCE_RE = re.compile(r"^(?P<indent>\s*)(?P<fence>(`{3,}|~{3,}))(?:\s*(?P<lang>\S+))?\s*$")


def process_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fence_char = None
    fence_re = None
    changed = False

    for i, line in enumerate(lines):
        m = FENCE_RE.match(line)
        if m:
            # fence delimiter
            indent = m.group('indent') or ''
            fence = m.group('fence')
            lang = m.group('lang')
            # if not in a fence, this starts a fence (lang may be present)
            if not in_fence:
                in_fence = True
                fence_char = fence[0]  # '`' or '~'
                fence_re = re.compile(rf"^\s*{re.escape(fence)}")
                out.append(line)
                continue
            else:
                # inside fence: this is the closing fence line
                # if the closing fence has language/text after it, replace with plain closing fence
                if lang:
                    out.append(f"{indent}{fence}")
                    changed = True
                else:
                    out.append(line)
                in_fence = False
                fence_char = None
                fence_re = None
                continue
        out.append(line)

    final = '\n'.join(out) + '\n'
    if final != s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: fix_code_fence_closing_language.py <dir>')
        sys.exit(1)
    import os
    changed = False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    p = Path(os.path.join(dirpath, f))
                    if process_file(p):
                        changed = True
    if not changed:
        print('No changes')
        sys.exit(0)
    sys.exit(0)
