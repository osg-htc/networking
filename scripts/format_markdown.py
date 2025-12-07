#!/usr/bin/env python3
"""
Small formatter for Markdown files in 'docs/' to address common markdownlint warnings:
- Trim trailing whitespace
- Remove excessive blanklines (reduce >1 to 1)
- Ensure a blank line before and after headings
- Ensure a blank line before and after fenced code blocks
- Ensure a blank line before lists (unordered or ordered)
- Normalize list marker spacing (one space after marker)
- Wrap paragraph lines to 120 columns (not inside code blocks, lists, or YAML front matter)

Usage: python3 scripts/format_markdown.py docs
"""

import os
import sys
import textwrap
import re


def is_heading(line):
    return bool(re.match(r"^#{1,6}\s+", line))


def is_fence(line):
    return bool(re.match(r"^\s*(`{3,}|~{3,})", line))


def is_list_item(line):
    return bool(re.match(r"^\s*([-*+]\s+|\d+\.\s+)", line))


def normalize_list_marker(line):
    m = re.match(r"^(\s*)(\d+)\.(\s+)(.*)$", line)
    if m:
        indent, _num, spaces, rest = m.groups()
        return f"{indent}1. {rest.rstrip()}\n"
    # unordered list marker spacing
    m2 = re.match(r"^(\s*)([-*+])(\s+)(.*)$", line)
    if m2:
        indent, marker, spaces, rest = m2.groups()
        return f"{indent}{marker} {rest.rstrip()}\n"
    return line


def add_fence_language(fence_line, inner_lines):
    # If fence_line already has a language, keep it
    if re.match(r"^\s*(`{3,}|~{3,})\w+", fence_line):
        return fence_line
    # If inner lines look like shell commands, use 'bash'
    shell_sig = re.compile(r"^(\s*[$#]|\s*(sudo|curl|systemctl|podman|dnf|ls|ip|nmcli|pscheduler|psconfig|sed|awk|grep|cat)\b)")
    for l in inner_lines[:6]:
        if shell_sig.search(l):
            return fence_line + 'bash'
    # default to 'text' to satisfy markdownlint
    return fence_line + 'text'


def wrap_paragraph(text, width=120):
    # Use textwrap to wrap paragraphs preserving leading indentation for nested blocks
    # Support multiple paragraphs separated by blank lines inside text
    out_lines = []
    paragraphs = text.split('\n')
    # We'll process continuous non-blank lines as a paragraph
    buf = []
    for line in paragraphs:
        if not line.strip():
            if buf:
                para = ' '.join(l.strip() for l in buf)
                out_lines.append(textwrap.fill(para, width=width))
                buf = []
            out_lines.append('')
        else:
            buf.append(line)
    if buf:
        para = ' '.join(l.strip() for l in buf)
        out_lines.append(textwrap.fill(para, width=width))
    return '\n'.join(out_lines)


def format_file(path):
    changed = False
    with open(path, 'r', encoding='utf-8') as fh:
        lines = fh.readlines()

    out = []
    in_fence = False
    fence_tag = None
    in_frontmatter = False
    fm_closed = True
    # detect YAML frontmatter first
    if len(lines) > 0 and lines[0].strip() == '---':
        in_frontmatter = True
        fm_closed = False

    i = 0
    # We'll produce new_lines with paragraph wrapping post-processing
    new_lines = []
    while i < len(lines):
        line = lines[i].rstrip('\n')
        # handle frontmatter
        if in_frontmatter and not fm_closed:
            new_lines.append(line.rstrip())
            if line.strip() == '---' and i != 0:
                fm_closed = True
                in_frontmatter = False
            i += 1
            continue

        # fenced code block toggle
        if is_fence(line):
            if not in_fence:
                # ensure blank line before fence
                if new_lines and new_lines[-1].strip() != '':
                    new_lines.append('')
                in_fence = True
                fence_tag = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line).groups()[0]
                # collect inner lines to analyze and decide if language should be appended
                inner_lines = []
                # look ahead but don't pass beyond the end; we'll add language after collecting
                k = i + 1
                while k < len(lines) and not is_fence(lines[k]):
                    inner_lines.append(lines[k])
                    k += 1
                append_lang = add_fence_language(line, inner_lines)
                new_lines.append(append_lang.rstrip())
            else:
                in_fence = False
                new_lines.append(line.rstrip())
                # add a blank line after fence
                new_lines.append('')
            i += 1
            continue

        # within fenced code block, don't change the content other than trimming trailing spaces
        if in_fence:
            new_lines.append(line.rstrip())
            i += 1
            continue

        # trim trailing whitespace
        line = re.sub(r"[\t ]+$", '', line)

        # remove multiple blank lines: limit to one
        if not line.strip():
            if new_lines and new_lines[-1] == '':
                # skip duplicate blank
                i += 1
                continue
            else:
                new_lines.append('')
                i += 1
                continue

        # headings: ensure blank line before; will ensure one blank after too by handling next iteration
        if is_heading(line):
            if new_lines and new_lines[-1].strip() != '':
                new_lines.append('')
            new_lines.append(line.rstrip())
            # Add blank after heading, if next non-blank isn't a list or code fence, we want a blank line
            # We'll enforce a blank in next iteration as needed
            if i + 1 < len(lines):
                next_line = lines[i+1]
                if next_line.strip() == '' and not (i+2 < len(lines) and is_fence(lines[i+2])):
                    # keep as-is
                    pass
                else:
                    # add a blank line after heading
                    new_lines.append('')
            i += 1
            continue

        # ensure blank line before lists
        if is_list_item(line):
            if new_lines and new_lines[-1].strip() != '':
                new_lines.append('')
            # normalize the list marker spacing and ordered list prefix
            normalized = normalize_list_marker(line + '\n')
            # reduce excessive top-level indentation: if indent >= 4 and previous non-blank is a heading or blank, set to 2 spaces
            m = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", normalized)
            if m:
                indent_str, marker, rest = m.groups()
                indent_len = len(indent_str)
                # find the previous non-empty line
                prev_non_empty = None
                for ln in reversed(new_lines):
                    if ln.strip() != '':
                        prev_non_empty = ln
                        break
                # If any indent >= 4, reduce to 2 (avoid excessive indent levels)
                if indent_len >= 4:
                    new_indent = ' ' * 2
                elif indent_len == 1:
                    # adjust 1-space indent to 0
                    new_indent = ''
                    normalized = f"{new_indent}{marker} {rest}"
            new_lines.append(normalized.rstrip())
            i += 1
            continue
        # Replace bare URLs in a safe way: wrap with angle brackets if not in a markdown link
        # Use a simple regex to detect http(s):// patterns not immediately prefixed by '(' or '['.
        def wrap_bare_urls(s):
                    pattern = re.compile(r'(?<![\(<\[])(https?://[^\s,);]+)')
                    s = pattern.sub(r'<\1>', s)
                    # wrap email addresses too (basic detection)
                    email_pat = re.compile(r'(?<![<\w/])([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})')
                    s = email_pat.sub(r'<\1>', s)
                    return s
        line = wrap_bare_urls(line)

        # for normal paragraph lines, collect contiguous lines and wrap them
        # gather lines until blank or heading or list or fence
        para_buf = [line]
        j = i + 1
        while j < len(lines) and not is_heading(lines[j]) and not is_list_item(lines[j]) and not is_fence(lines[j]) and lines[j].strip() != '':
            para_buf.append(lines[j].rstrip('\n'))
            j += 1
        if len(para_buf) > 1 or (len(para_buf) == 1 and len(para_buf[0]) > 120):
            # wrap paragraph
            paragraph = '\n'.join(para_buf)
            wrapped = textwrap.fill(' '.join(l.strip() for l in para_buf), width=120)
            new_lines.extend(wrapped.split('\n'))
            i = j
            continue
        else:
            new_lines.append(line)
            i += 1

    # Post-processing: ensure no blank at start or end
    while new_lines and new_lines[0].strip() == '':
        new_lines.pop(0)
    while new_lines and new_lines[-1].strip() == '':
        new_lines.pop()

    final = '\n'.join(new_lines) + '\n'
    with open(path, 'r', encoding='utf-8') as fh:
        original = fh.read()
    if final != original:
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(final)
        changed = True
    return changed


def walk_and_format(root):
    changed_files = []
    for dirpath, _, filenames in os.walk(root):
        for file in filenames:
            if not file.endswith('.md'):
                continue
            path = os.path.join(dirpath, file)
            try:
                if format_file(path):
                    changed_files.append(path)
                    print("Formatted:", path)
            except Exception as e:
                print(f"Error formatting {path}: {e}")
    return changed_files


def main():
    if len(sys.argv) < 2:
        print("Usage: format_markdown.py <docs-root>")
        sys.exit(1)
    root = sys.argv[1]
    changed = walk_and_format(root)
    if changed:
        print("Changed files:")
        for c in changed:
            print(" - ", c)
    else:
        print("No changes required.")


if __name__ == '__main__':
    main()
