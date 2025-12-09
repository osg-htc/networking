#!/usr/bin/env python3
"""
Map a generated site HTML file back to one or more possible source Markdown files in docs/.

Usage: ./scripts/map_html_to_source.py site/path/to/index.html

It prints candidate docs paths which are the most likely Markdown sources for the given HTML file.
"""

import os
import sys


def candidates_for_site_html(path):
    # path: site/..../index.html or site/....html
    if not path.startswith('site/'):
        raise SystemExit("Provide a site path under site/")
    rel = path[len('site/'):]  # remove site/
    parts = rel.split('/')

    cands = []
    # if ends with index.html -> e.g., 'foo/bar/index.html' -> docs/foo/bar.md
    if rel.endswith('index.html'):
        base = rel[:-len('/index.html')]
        cands.append(os.path.join('docs', base + '.md'))
        cands.append(os.path.join('docs', base, 'index.md'))
        # also consider top-level md
        if base == 'index':
            cands.append('docs/index.md')
    else:
        # if file is something else: 'foo/bar.html' -> docs/foo/bar.md
        name = rel[:-len('.html')]
        cands.append(os.path.join('docs', name + '.md'))
        cands.append(os.path.join('docs', name, 'index.md'))

    return [c for c in cands if os.path.exists(c)]


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: map_html_to_source.py site/.../index.html')
        sys.exit(2)
    path = sys.argv[1]
    cands = candidates_for_site_html(path)
    if not cands:
        print('No candidates found; file may be an asset or built from multiple inputs')
        sys.exit(1)
    for c in cands:
        print(c)
    sys.exit(0)
