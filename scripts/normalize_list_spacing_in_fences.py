#!/usr/bin/env python3
"""Normalize spaces after list markers both inside and outside fenced blocks.

Usage: python3 scripts/normalize_list_spacing_in_fences.py <path>
"""

import sys
import re
from pathlib import Path


def process(path: Path):
    s = path.read_text()
    # replace '-   ' and '*   ' and '+   ' and '1.   ' with single space
    s2 = re.sub(r"^([ \t]*[-*+])([ \t]{2,})", r"\1 ", s, flags=re.M)
    s2 = re.sub(r"^([ \t]*\d+\.)[ \t]{2,}", r"\1 ", s2, flags=re.M)
    if s2 != s:
        path.write_text(s2)
        print('Normalized list spacing in', path)
        return True
    return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: normalize_list_spacing_in_fences.py <path>')
        sys.exit(1)
    import os
    changed=False
    for root in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(root):
            for f in filenames:
                if f.endswith('.md'):
                    if process(Path(os.path.join(dirpath,f))):
                        changed=True
    if changed:
        sys.exit(0)
    sys.exit(0)
