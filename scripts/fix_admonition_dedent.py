#!/usr/bin/env python3
"""
Dedent code fences inside MkDocs admonitions to 4 spaces where they are over-indented (e.g., 5 spaces).

Runs in dry-run by default; use --apply to write changes.
"""
import argparse
import re
from pathlib import Path

ADMON_RE = re.compile(r"^!!!\s+(note|warning|tip|info|caution|important)\b")
FENCE_RE = re.compile(r"^(\s*)```(\w+)?\s*$")


def fix_file(path: Path, apply: bool = False):
    text = path.read_text(encoding='utf-8')
    lines = text.splitlines()
    changed = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if ADMON_RE.match(line):
            # Process admonition block
            i += 1
            # inside admonition: lines must be indented. Continue until we encounter a top-level line (no leading spaces) or next heading '##' or '!!!' block
            while i < len(lines) and (lines[i].startswith(' ') or lines[i].strip()==''):
                m = FENCE_RE.match(lines[i])
                if m:
                    leading = m.group(1)
                    if len(leading) >= 5:
                        new_line = ' ' * 4 + '```' + (m.group(2) or '')
                        changed.append((i+1, lines[i], new_line))
                        lines[i] = new_line
                i += 1
            continue
        i += 1
    if apply and changed:
        backup = path.parent / '.indent_fix_backups'
        backup.mkdir(exist_ok=True)
        bakfile = backup / (path.name + '.bak.auto')
        if not bakfile.exists():
            bakfile.write_text(text, encoding='utf-8')
        path.write_text('\n'.join(lines)+"\n", encoding='utf-8')
    return {'path': str(path), 'changes': changed}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('files', nargs='+')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    for f in args.files:
        r = fix_file(Path(f), apply=args.apply)
        print(r['path'])
        if not r['changes']:
            print('  no changes')
        else:
            print('  changes:')
            for ln, old, new in r['changes']:
                print(f"   - line {ln}: '{old}' -> '{new}'")

if __name__ == '__main__':
    main()
