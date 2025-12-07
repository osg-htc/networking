#!/usr/bin/env python3
"""
Convert setext-style headings (underlines using === or ---) to ATX (# / ##) headings.

Rules:
- Convert "Title\n===" -> "# Title"
- Convert "Title\n---" -> "## Title"
- Do not convert if the underline line is YAML front matter (i.e., the first '---' at file start) or if it's a horizontal rule intentionally placed (we check by seeing if the line is a single '---' with no previous non-empty line or used as horizontal rule).
- Skip lines within fenced code blocks and skip lines when previous line begins with '>' or list markers.

Run with: python3 scripts/convert_setext_to_atx.py docs
This will modify files in place and report changed files.
"""

import os
import sys
import re


def is_fence(line):
    return bool(re.match(r"^\s*`{3,}|^\s*~{3,}", line))


def convert_file(path):
    changed = False
    with open(path, 'r', encoding='utf-8') as fh:
        lines = fh.readlines()

    out = []
    i = 0
    in_fence = False
    yaml_frontmatter = False

    # Detect if file starts with YAML frontmatter '---' and track its bounds
    if len(lines) > 0 and lines[0].strip() == '---':
        yaml_frontmatter = True
    fm_closed = not yaml_frontmatter

    while i < len(lines):
        line = lines[i]
        if yaml_frontmatter and not fm_closed:
            if line.strip() == '---' and i != 0:
                fm_closed = True
            out.append(line)
            i += 1
            continue

        # Toggle fenced code blocks
        if is_fence(line):
            in_fence = not in_fence
            out.append(line)
            i += 1
            continue

        if in_fence:
            out.append(line)
            i += 1
            continue

        # Look ahead to the next line to see if it's a setext underline
        if i + 1 < len(lines):
            next_line = lines[i+1]
            # match a line of === or --- (three or more chars) and no other content
            if re.match(r"^\s*={2,}\s*$", next_line):
                # Convert to H1 (ATX)
                # Ensure the current line is not empty and not a list or blockquote
                if line.strip() and not re.match(r"^[>\-\*\d].*", line):
                    new_line = '# ' + line.lstrip('#').rstrip('\n') + '\n'
                    out.append(new_line)
                    i += 2
                    changed = True
                    continue
            elif re.match(r"^\s*-{2,}\s*$", next_line):
                # Ensure not a horizontal rule intentionally at top of file or blank line
                # Skip if previous line is empty (horizontal rule), or prev char is '\n' alone
                if line.strip() and not re.match(r"^[>\-\*\d].*", line):
                    new_line = '## ' + line.lstrip('#').rstrip('\n') + '\n'
                    out.append(new_line)
                    i += 2
                    changed = True
                    continue

        out.append(line)
        i += 1

    if changed:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.writelines(out)
    return changed


def walk_and_convert(root):
    files_changed = []
    for dirpath, _, filenames in os.walk(root):
        for file in filenames:
            if not file.endswith('.md'):
                continue
            path = os.path.join(dirpath, file)
            try:
                if convert_file(path):
                    files_changed.append(path)
            except Exception as e:
                print(f"Error converting {path}: {e}")
    return files_changed


def main():
    if len(sys.argv) < 2:
        print("Usage: convert_setext_to_atx.py <path>\nExample: python3 scripts/convert_setext_to_atx.py docs")
        sys.exit(1)
    root = sys.argv[1]
    changed = walk_and_convert(root)
    if changed:
        print("Converted headings in files:")
        for c in changed:
            print(" - " + c)
    else:
        print("No setext headings found or changed.")


if __name__ == '__main__':
    main()
