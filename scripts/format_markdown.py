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


def normalize_list_marker(line, is_perfsonar=False):
    m = re.match(r"^(\s*)(\d+)\.(\s+)(.*)$", line)
    if m:
        indent, _num, spaces, rest = m.groups()
        return f"{indent}1. {rest.rstrip()}\n"
    # unordered list marker spacing
    m2 = re.match(r"^(\s*)([-*+])(\s+)(.*)$", line)
    if m2:
        indent, marker, spaces, rest = m2.groups()
        # normalize to a single space after the marker
        marker_to_use = marker
        # convert dash lists to asterisk lists for perfsonar files
        if is_perfsonar and marker == '-':
            marker_to_use = '*'
        return f"{indent}{marker_to_use} {rest.rstrip()}\n"
    return line


def enforce_list_marker_spacing(line):
    # Convert instances of '-   ' or '*   ' to single space after marker
    return re.sub(r"^(\s*[-*+])(\s{2,})(.*)$", r"\1 \3", line)


def add_fence_language(fence_line, inner_lines):
    # If fence_line already has a language, keep it
    # allow optional whitespace between fence and language
    if re.match(r"^\s*(`{3,}|~{3,})\s*\w+", fence_line):
        return fence_line
    # If inner lines look like shell commands, use 'bash'
    shell_sig = re.compile(r"^(\s*[$#]|\s*(sudo|curl|systemctl|podman|dnf|ls|ip|nmcli|pscheduler|psconfig|sed|awk|grep|cat)\b)")
    for l in inner_lines[:6]:
        if shell_sig.search(l):
            # include a single space before the language if missing
            return fence_line.rstrip() + ' bash'
    # default to 'text' to satisfy markdownlint
    return fence_line.rstrip() + ' text'


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
        # Skip wrapping if a paragraph contains a URL or an email address to avoid breaking links
        if re.search(r"https?://|mailto:|@\w+\.", para):
            out_lines.append(para)
        else:
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
    # Pre-scan file to detect base list indentation used in this file (skip frontmatter and fenced blocks)
    base_indent = None
    scan_in_fence = False
    for ln in lines:
        l = ln.rstrip('\n')
        if l.strip() == '---' and lines.index(ln) == 0:
            # simplistic frontmatter skip: ignore first '---'
            continue
        if is_fence(l):
            scan_in_fence = not scan_in_fence
            continue
        if scan_in_fence:
            continue
        if is_list_item(l):
            mm = re.match(r"^(\s*)([-*+]|\d+\.)\s+", l)
            if mm:
                indent = len(mm.groups()[0])
                if base_indent is None or indent < base_indent:
                    base_indent = indent
    if base_indent is None:
        base_indent = 0
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
                    k = i + 1
                    while k < len(lines) and not is_fence(lines[k]):
                        inner_lines.append(lines[k])
                        k += 1
                    # add fence language only once after collecting inner lines
                    # If the opening fence has content after the language (e.g., "```bash cd /opt/..."),
                    # move the extra content to the first inner line so we don't lose commands.
                    m_f = re.match(r"^(\s*(`{3,}|~{3,}))(\s*\w+)?\s*(.*)$", line)
                    extra = ''
                    if m_f:
                        extra = m_f.groups()[3]
                        if extra.strip():
                            # push extra content into the inner lines as the first line
                            inner_lines.insert(0, extra.strip())
                            # regenerate the opening fence line: include language if present (strip whitespace)
                            lang = m_f.group(3).strip() if m_f.group(3) else ''
                            if lang:
                                line = f"{m_f.group(1)} {lang}"
                            else:
                                line = m_f.group(1)
                    append_lang = add_fence_language(line, inner_lines)
                    if ("/perfsonar/" in path) and not re.match(r"^\s*(`{3,}|~{3,})\s*\w+", append_lang):
                        append_lang = append_lang.rstrip() + ' text'
                    new_lines.append(append_lang.rstrip())
            else:
                in_fence = False
                new_lines.append(line.rstrip())
                # add a single blank line after fence (avoid adding duplicate blanks)
                if not (new_lines and new_lines[-1].strip() == ''):
                    new_lines.append('')
                # If next non-empty line in original file is a list item, ensure we have a blank line after the fence
                next_non_empty = None
                j = i + 1
                while j < len(lines):
                    if lines[j].strip() != '':
                        next_non_empty = lines[j].rstrip('\n')
                        break
                    j += 1
                if next_non_empty and is_list_item(next_non_empty):
                    if not (new_lines and new_lines[-1].strip() == ''):
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
            # strip leading whitespace before a heading so it starts on column 0
            line = line.lstrip()
            # remove trailing punctuation like '.' from headings (MD026)
            # Be conservative: only remove a trailing '.' at the end of heading line
            line = re.sub(r"\s+[\.]+$", '', line)
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
            # first ensure spacing after marker is normalized
            line = enforce_list_marker_spacing(line)
            normalized = normalize_list_marker(line + '\n', is_perfsonar=("/perfsonar/" in path))
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
                # Determine the previous list indent to align this item with
                prev_indent = 0
                if prev_non_empty and is_list_item(prev_non_empty):
                    pm = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", prev_non_empty)
                    if pm:
                        prev_indent = len(pm.groups()[0])
                # If indentation is too large, reduce to prev_indent + 2
                if indent_len >= prev_indent + 4:
                    new_indent = ' ' * (prev_indent + 2)
                    normalized = f"{new_indent}{marker} {rest}"
                # If indentation suggests nested list but not aligned, align to prev + 2
                elif indent_len > prev_indent and indent_len != prev_indent + 2:
                    new_indent = ' ' * (prev_indent + 2)
                    normalized = f"{new_indent}{marker} {rest}"
                elif indent_len == 1:
                    # adjust 1-space indent to 0
                    new_indent = ''
                    normalized = f"{new_indent}{marker} {rest}"
                # Align the indentation to the file's base indent if this is a top-level list under a heading
                # If the previous non-empty element is a heading, align to base_indent
                if prev_non_empty and is_heading(prev_non_empty):
                    # When a list immediately follows a heading, prefer a top-level list (0 indent)
                    desired_indent = 0
                elif prev_non_empty and prev_non_empty.strip() == '':
                    desired_indent = base_indent
                elif prev_non_empty and not is_list_item(prev_non_empty):
                    desired_indent = 0
                else:
                    desired_indent = base_indent
                    if indent_len != desired_indent:
                        normalized = f"{' ' * desired_indent}{marker} {rest}"
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

        # Replace common inline HTML break tags with markdown line breaks (two spaces + newline)
        # We intentionally do this only for explicit <br> tags to avoid altering inline spans or layout
        line = re.sub(r"<br\s*/?>", "  ", line, flags=re.IGNORECASE)

        # Remove twiki 'span' macro tags and other empty 'span' wrappers used by imported twiki content
        # This handles patterns like: <span class="twiki-macro LINKCSS"></span>
        line = re.sub(r"<span\s+class=\"twiki-macro[^\"]*\">", "", line)
        line = re.sub(r"</span>", "", line)

        # Convert simple <img src="..."> to markdown images if possible
        img_match = re.search(r"<img\s+[^>]*src=\"([^\"]+)\"[^>]*alt=\"([^\"]*)\"[^>]*>", line)
        if img_match:
            src, alt = img_match.groups()
            mdimg = f"![{alt}]({src})"
            line = re.sub(r"<img\s+[^>]*src=\"[^\"]+\"[^>]*alt=\"[^\"]*\"[^>]*>", mdimg, line)
        else:
            # fallback: if only src is present
            img_match2 = re.search(r"<img\s+[^>]*src=\"([^\"]+)\"[^>]*>", line)
            if img_match2:
                src = img_match2.groups()[0]
                line = re.sub(r"<img\s+[^>]*src=\"[^\"]+\"[^>]*>", f"![]({src})", line)

        # reduce multiple spaces after list markers globally
        if re.match(r"^\s*([-*+]\s{2,})", line) or re.match(r"^\s*\d+\.\s{2,}", line):
            line = re.sub(r"^(\s*([-*+]|\d+\.))\s{2,}", r"\1 ", line)

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
    # Final pass: ensure opening fences have a language; this targets lines like '```' or '   ```' where no
    # language is specified. We only set a language for opening fences (not closing ones) by examining the
    # next non-empty line.
    def ensure_fence_languages(s):
        # Only add languages to opening fence lines (not closing ones) by toggling in_fence state.
        out_lines_local = []
        lines_local = s.split('\n')
        in_f = False
        fence_open_re = re.compile(r"^(\s*)(`{3,}|~{3,})\s*(\w+)?\s*$")
        for l in lines_local:
            m = fence_open_re.match(l)
            if m:
                indent, fence_chars, lang = m.groups()
                # normalize fence indentation: reduce leading indent to a maximum of 3 spaces
                if len(indent) > 3:
                    indent = indent[:3]
                if not in_f:
                    # opening fence; ensure a language is present
                    if not lang:
                        l = f"{indent}{fence_chars} text"
                    in_f = True
                else:
                    # closing fence; strip any language so it remains a bare fence
                    l = f"{indent}{fence_chars}"
                    in_f = False
            out_lines_local.append(l)
        return '\n'.join(out_lines_local)

    final = ensure_fence_languages(final)
    # Extra pass: some backticks may be present with up to 3 leading spaces - ensure we attach a default language on opens
    def ensure_fence_languages_simple(s):
        lines_local = s.split('\n')
        out = []
        in_f = False
        for l in lines_local:
            if re.match(r"^\s{0,6}`{3,}\s*(\w+)?\s*$", l):
                if not in_f:
                    # opening fence with optional language: ensure language present
                    if re.search(r"\S`{3,}\s*$", l):
                        # if a language exists already, keep it
                        out.append(l)
                    else:
                        out.append(re.sub(r"^\s{0,6}`{3,}\s*$", "```text", l))
                    in_f = True
                    continue
                else:
                    # closing fence: remove any trailing language tokens
                    indent = re.match(r"^(\s{0,6})`{3,}", l).groups()[0]
                    out.append(indent + "```")
                    in_f = False
                    continue
            out.append(l)
        return '\n'.join(out)

    final = ensure_fence_languages_simple(final)
    # Collapse multiple blank lines (2 or more) to a single blank line
    final = re.sub(r"(\n\s*){2,}", "\n\n", final)
    final = re.sub(r"\n{3,}", "\n\n", final)
    final = re.sub(r"\n\s*\n{1,}", "\n\n", final)
    # Extra perfsonar-specific whitespace fixes: ensure blank lines between list items and code fences
    if "/perfsonar/" in path:
        # Insert a blank line between a list item and an opening fence (allow more leading spaces on the fence)
        final = re.sub(r"(^\s*(?:[-*+]|\d+\.)[^\n]*?)\n(\s{0,6}`{3,}.*)", r"\1\n\n\2", final, flags=re.M)
        # Insert a blank line after a closing fence if followed by a list item (allow fence to have trailing language)
        final = re.sub(r"(\s{0,6}`{3,}.*)\s*\n(\s*(?:[-*+]|\d+\.)\s)", r"\1\n\n\2", final, flags=re.M)
        # Ensure a blank line after the end of a list block if the following line is not a list or blank
        final = re.sub(r"(^\s*(?:[-*+]|\d+\.)[^\n]*?)\n(?!\s*(?:[-*+]|\d+\.)|\s*$)([^\n])", r"\1\n\n\2", final, flags=re.M)
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
