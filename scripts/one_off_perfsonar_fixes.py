#!/usr/bin/env python3
"""One-off perfsonar markdown fixes targeting common markdownlint rules.
- Collapse duplicate blank lines outside fenced blocks
- Wrap bare URLs with angle brackets
- Rejoin URLs broken across lines with hyphen
- Add default 'text' language to code fences without language
- Convert simple <br> to markdown spaces
- Convert simple <img> tags to markdown images

Usage: python3 scripts/one_off_perfsonar_fixes.py docs/perfsonar/<file1> docs/perfsonar/<file2> ...
"""

import sys
import re
from pathlib import Path


def process_file(path: Path):
    s = path.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fence_pattern = re.compile(r"^(\s*)(`{3,}|~{3,})(\s*\w+)?\s*(.*)$")

    i = 0
    while i < len(lines):
        line = lines[i]
        # fence detection
        m = fence_pattern.match(line)
        if m:
            # toggle
            if not in_fence:
                # add language if missing
                indent, fence, lang, rest = m.groups()[0], m.groups()[1], m.groups()[2], m.groups()[3]
                if not (lang and lang.strip()):
                    # if we already have extra stuff on same line, treat it as inner content
                    if rest and rest.strip():
                        # rebuild fence with language text and push rest into next line
                        out.append(f"{indent}{fence} text")
                        out.append(rest.strip())
                    else:
                        out.append(f"{indent}{fence} text")
                else:
                    out.append(line)
                in_fence = True
                i += 1
                continue
            else:
                # closing fence: normalize to bare fence
                indent = m.group(1) or ''
                out.append(f"{indent}{m.group(2)}")
                in_fence = False
                i += 1
                continue

        if in_fence:
            out.append(line)
            i += 1
            continue

        # collapse duplicate blank lines: keep at most one
        if line.strip() == '':
            # lookback: if last out line was blank, skip
            if out and out[-1].strip() == '':
                i += 1
                continue
            out.append('')
            i += 1
            continue

        # Join lines with split URLs: if this line contains 'https://' and ends with a hyphen (no trailing spaces)
        if 'https://' in line and line.rstrip().endswith('-'):
            # join subsequent lines until URL looks complete or until next space
            combined = line.rstrip()
            j = i + 1
            while j < len(lines) and lines[j].strip() and not re.search(r"\s", lines[j].strip()):
                combined = combined + lines[j].strip()
                j += 1
            # replace the lines
            # ensure the combined URL is wrapped
            combined = re.sub(r"(?<![<\[\(\"])https?://[^\s,);]+", lambda m: f"<{m.group(0)}>", combined)
            out.append(combined)
            i = j
            continue

        # Wrap bare URLs in angle brackets while not part of markdown link or inside parenthesis
        def repl_url(match):
            url = match.group(0)
            # avoid if already wrapped
            if url.startswith('<') and url.endswith('>'):
                return url
            return f"<{url}>"

        # pattern: http(s):// followed by non-space sequence, avoiding ).,] end
        url_pattern = re.compile(r"(?<![\(<\[])(https?://[^\s\)\]\>,]+)")
        newline = url_pattern.sub(repl_url, line)

        # mailto or plain emails
        email_pattern = re.compile(r'(?<![<\w/])([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})')
        newline = email_pattern.sub(r"<\1>", newline)

        # convert <br> to two spaces (markdown linebreak) if present
        newline = re.sub(r"<br\s*/?>", "  ", newline, flags=re.IGNORECASE)

        # convert simple <img src="..." alt="..."> to markdown
        img_match = re.search(r'<img\s+[^>]*src\s*=\s*"([^"]+)"[^>]*alt="([^"]*)"[^>]*>', newline)
        if img_match:
            src, alt = img_match.groups()
            newline = re.sub(r'<img\s+[^>]*src\s*=\s*"[^"]+"[^>]*alt="[^"]*"[^>]*>', f"![{alt}]({src})", newline)
        else:
            img_match2 = re.search(r'<img\s+[^>]*src\s*=\s*"([^"]+)"[^>]*>', newline)
            if img_match2:
                src = img_match2.group(1)
                newline = re.sub(r'<img\s+[^>]*src\s*=\s*"[^"]+"[^>]*>', f"![]({src})", newline)

        out.append(newline)
        i += 1

    final = '\n'.join(out) + '\n'
    # post collapse multiple blanklines
    final = re.sub(r'(\n\s*){2,}', '\n\n', final)
    path.write_text(final)
    print('Processed', path)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: one_off_perfsonar_fixes.py <file> [file ...]')
        sys.exit(1)
    for arg in sys.argv[1:]:
        process_file(Path(arg))
