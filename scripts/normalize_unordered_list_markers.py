#!/usr/bin/env python3
"""Normalize unordered list markers to asterisks (*) instead of dashes (-).

This script replaces '-' with '*' for unordered list items, skipping code fences and front matter.
"""

import re
import sys
import os
from pathlib import Path

UNORDERED_RE = re.compile(r"^([ \t]*)-\s+(.*)$")


def process_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fm_open = False
    changed = False
    for i, line in enumerate(lines):
        # Handle frontmatter YAML block
        if i == 0 and line.strip() == '---':
            fm_open = True
            out.append(line)
            continue
        if fm_open:
            out.append(line)
            if line.strip() == '---':
                fm_open = False
            continue
        # detect fence toggles
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        # replace unordered '-' list markers with '*'
        m = UNORDERED_RE.match(line)
        if m:
            indent, rest = m.groups()
            new_line = f"{indent}* {rest}"
            if new_line != line:
                changed = True
            out.append(new_line)
        else:
            out.append(line)
    final = '\n'.join(out) + '\n'
    if final != s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: normalize_unordered_list_markers.py <dir>')
        sys.exit(1)
    changed = False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    p = Path(os.path.join(dirpath, f))
                    try:
                        if process_file(p):
                            changed = True
                    except Exception as e:
                        print(f"Error processing {p}: {e}")
    if not changed:
        print('No changes')
        sys.exit(0)
    sys.exit(0)

#!/usr/bin/env python3
"""Normalize unordered list markers to asterisks (*) instead of dashes (-).

This script replaces '-' with '*' for unordered list items, skipping code fences and front matter.
"""

import re
import sys
import os
from pathlib import Path

UNORDERED_RE = re.compile(r"^([ \t]*)-\s+(.*)$")


def process_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fm_open = False
    changed = False
    for i, line in enumerate(lines):
        # Handle frontmatter YAML block
        if i == 0 and line.strip() == '---':
            fm_open = True
            out.append(line)
            continue
        if fm_open:
            out.append(line)
            if line.strip() == '---':
                fm_open = False
            continue
        # detect fence toggles
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        # replace unordered '-' list markers with '*'
        m = UNORDERED_RE.match(line)
        if m:
            indent, rest = m.groups()
            new_line = f"{indent}* {rest}"
            if new_line != line:
                changed = True
            out.append(new_line)
        else:
            out.append(line)
    final = '\n'.join(out) + '\n'
    if final != s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: normalize_unordered_list_markers.py <dir>')
        sys.exit(1)
    changed = False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    p = Path(os.path.join(dirpath, f))
                    try:
                        if process_file(p):
                            changed = True
                    except Exception as e:
                        print(f"Error processing {p}: {e}")
    if not changed:
        print('No changes')
        sys.exit(0)
    sys.exit(0)

#!/usr/bin/env python3
"""Normalize unordered list markers to asterisks (*) instead of dashes (-).

This script replaces '-' with '*' for unordered list items, skipping code fences and front matter.
"""

import re
import sys
import os
from pathlib import Path

UNORDERED_RE = re.compile(r"^([ \t]*)-\s+(.*)$")


def process_file(p: Path):
    s = p.read_text()
    lines = s.splitlines()
    out = []
    in_fence = False
    fm_open = False
    changed = False
    for i, line in enumerate(lines):
        # Handle frontmatter YAML block
        if i == 0 and line.strip() == '---':
            fm_open = True
            out.append(line)
            continue
        if fm_open:
            out.append(line)
            if line.strip() == '---':
                fm_open = False
            continue
        # detect fence toggles
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        # replace unordered '-' list markers with '*'
        m = UNORDERED_RE.match(line)
        if m:
            indent, rest = m.groups()
            new_line = f"{indent}* {rest}"
            if new_line != line:
                changed = True
            out.append(new_line)
        else:
            out.append(line)
    final = '\n'.join(out) + '\n'
    if final != s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: normalize_unordered_list_markers.py <dir>')
        sys.exit(1)
    changed = False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    p = Path(os.path.join(dirpath, f))
                    try:
                        if process_file(p):
                            changed = True
                    except Exception as e:
                        print(f"Error processing {p}: {e}")
    if not changed:
        print('No changes')
        sys.exit(0)
    sys.exit(0)
#!/usr/bin/env python3
"""Normalize unordered list markers to asterisks (*) instead of dashes (-).

This script replaces '-' with '*' for unordered list items, skipping code fences and front matter.
"""

import re
import sys
from pathlib import Path

UNORDERED_RE = re.compile(r"^(	|\s*)-\s+(\