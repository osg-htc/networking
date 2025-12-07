#!/usr/bin/env python3
"""
Safer conversion of setext headings (underlines with ===/---) to ATX headings using multiline regex.
This script reads each file and converts any setext heading not inside YAML frontmatter or fenced code blocks.
"""

import sys
import os
import re


FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
SETEXT_RE = re.compile(r"(?m)^(?P<h>[^#\n>\-\*\d].+?)\r?\n(?P<u>={3,}|-{3,})\s*$")


def in_frontmatter_ranges(text):
    ranges = []
    if text.startswith('---'):
        # find closing '---' that marks the end of front matter
        # skip the first '---'
        idx = text.find('\n', 3)
        if idx == -1:
            return ranges
        # find the second '---' line
        m = re.search(r"^---\s*$", text[idx+1:], re.M)
        if m:
            start = 0
            end = idx+1 + m.end()
            ranges.append((start, end))
    return ranges


def in_fenced_block_ranges(text):
    ranges = []
    stack = []
    for m in re.finditer(r"(?m)^(?P<fence>`{3,}|~{3,}).*$", text):
        fence = m.group('fence')
        pos = m.start()
        if stack and stack[-1][0] == fence:
            # close
            start_pos = stack[-1][1]
            ranges.append((start_pos, m.end()))
            stack.pop()
        else:
            stack.append((fence, pos))
    return ranges


def pos_in_ranges(pos, ranges):
    for (s, e) in ranges:
        if s <= pos < e:
            return True
    return False


def convert_text(text):
    fm_ranges = in_frontmatter_ranges(text)
    fence_ranges = in_fenced_block_ranges(text)

    converted = False

    def repl(m):
        nonlocal converted
        start_pos = m.start()
        if pos_in_ranges(start_pos, fm_ranges):
            return m.group(0)
        if pos_in_ranges(start_pos, fence_ranges):
            return m.group(0)
        heading_text = m.group('h').rstrip()
        underline = m.group('u')
        if underline.startswith('='):
            converted = True
            return '# ' + heading_text + '\n'
        else:
            converted = True
            return '## ' + heading_text + '\n'

    new_text = SETEXT_RE.sub(repl, text)
    return new_text, converted


def convert_file(path):
    with open(path, 'r', encoding='utf-8') as fh:
        text = fh.read()
    new_text, converted = convert_text(text)
    if converted and new_text != text:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(new_text)
        return True
    return False


def walk_and_convert(root):
    changed_files = []
    for dirpath, dirs, files in os.walk(root):
        for file in files:
            if not file.endswith('.md'):
                continue
            path = os.path.join(dirpath, file)
            try:
                if convert_file(path):
                    changed_files.append(path)
            except Exception as e:
                print(f"Error converting {path}: {e}")
    return changed_files


def main():
    if len(sys.argv) < 2:
        print("Usage: convert_setext_to_atx2.py <root-dir>")
        sys.exit(1)
    root = sys.argv[1]
    changed = walk_and_convert(root)
    for f in changed:
        print('Converted:', f)
    if not changed:
        print('No conversions performed.')


if __name__ == '__main__':
    main()
