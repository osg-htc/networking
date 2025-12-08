import re
from pathlib import Path

p = Path('docs/personas/quick-deploy/install-perfsonar-testpoint.md')
text = p.read_text()
lines = text.splitlines()

fence_re = re.compile(r'^(\s*)```(.*)$')

in_fence = False
fence_indent = ''
changed = False

out_lines = []
for i, line in enumerate(lines):
    m = fence_re.match(line)
    if m:
        indent = m.group(1)
        # If not in fence -> start fence
        if not in_fence:
            in_fence = True
            fence_indent = indent
            out_lines.append(line)
            continue
        else:
            # in_fence and we found a new fence -> this implies previous fence wasn't closed
            # close it by inserting a fence line before this one
            out_lines.append(fence_indent + '```')
            out_lines.append(line)
            in_fence = True
            fence_indent = indent
            changed = True
            continue
    else:
        out_lines.append(line)

# If at EOF still in_fence, insert a closing fence
if in_fence:
    out_lines.append(fence_indent + '```')
    changed = True

if changed:
    bak = p.with_suffix('.md.fencefix.bak')
    if not bak.exists():
        p.rename(bak)
        p.write_text('\n'.join(out_lines) + '\n')
        print('Fixed fences and backed up original to', bak)
    else:
        p.write_text('\n'.join(out_lines) + '\n')
        print('Fixed fences (backup exists)')
else:
    print('No fence issues found')
