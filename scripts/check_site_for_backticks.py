#!/usr/bin/env python3
"""
Check the built mkdocs site for visible "```" sequences by stripping HTML tags
and reporting any matches along with filenames/line numbers.

Usage:
  ./scripts/check_site_for_backticks.py [--build]

Options:
  --build  : Run `mkdocs build --clean` before checking. Defaults to off.

Exit codes:
  0: No matches found (clean)
  1: Matches found
  2: Error during build or processing
"""

import argparse
import os
import re
import subprocess
import sys


def build_site():
    try:
        subprocess.check_call(["mkdocs", "build", "--clean"])
        return True
    except Exception as e:
        print(f"ERROR: mkdocs build failed: {e}")
        return False


def strip_tags_and_find(file_path, needle='```'):
    """Return list of (line_no, line_text) where needle appears in the stripped text."""
    out = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            html = f.read()
    except Exception as e:
        print(f"ERROR: Could not read {file_path}: {e}")
        return out
    # Replace tags
    text = re.sub(r'<[^>]*>', '', html)
    for i, line in enumerate(text.splitlines(), 1):
        if '```' in line:
            out.append((i, line))
    return out


def main():
    parser = argparse.ArgumentParser(description='Build and check site HTML for visible ``` sequences')
    parser.add_argument('--build', action='store_true', help='Run mkdocs build --clean before checking')
    parser.add_argument('--site-dir', default='site', help='Directory of built site (default: site)')
    args = parser.parse_args()

    if args.build:
        print('Building site with: mkdocs build --clean')
        if not build_site():
            sys.exit(2)

    if not os.path.isdir(args.site_dir):
        print(f"ERROR: site directory '{args.site_dir}' not found. Run mkdocs build first or use --build")
        sys.exit(2)

    matches = []
    for root, dirs, files in os.walk(args.site_dir):
        for name in files:
            if name.endswith('.html'):
                path = os.path.join(root, name)
                hits = strip_tags_and_find(path)
                if hits:
                    matches.append((path, hits))

    if not matches:
        print('OK: No visible triple backticks found in generated site HTML.')
        sys.exit(0)

    print('ERROR: Found visible triple backticks in generated HTML:')
    for path, hits in matches:
        print('\nFile:', path)
        for line_no, line in hits:
            preview = (line.strip()[:120] + '...') if len(line.strip()) > 120 else line.strip()
            print(f'  line {line_no}: {preview}')
    print('\nPlease inspect associated Markdown files in docs/ to remove stray fences or fix indentation (e.g., dedent code blocks in admonitions).')
    sys.exit(1)


if __name__ == '__main__':
    main()
