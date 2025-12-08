"""Indent bullet lists under admonition '**Solutions:**' in the markdown file by 4 spaces.

This script will update the file in-place (make a backup first) and is conservative: it only indents bullet list lines ('-', '*', '+', or ordered lists) immediately following a '**Solutions:**' line if those bullets are not already indented.
"""
import re
from pathlib import Path

p = Path('docs/personas/quick-deploy/install-perfsonar-testpoint.md')
text = p.read_text()
lines = text.splitlines()

changed = False

# Pattern that matches the Solutions line indented by 4 spaces
sol_pat = re.compile(r"^\s{4}\*\*Solutions:\*\*\s*$")
# Pattern for a bullet list line at column 1 or that starts with 0-3 spaces
bullet_pat = re.compile(r"^([ \t]{0,3})([-*+]\s+|\d+\.\s+)")

i = 0
while i < len(lines):
    if sol_pat.match(lines[i]):
        # Look ahead for the next non-empty line(s)
        j = i+1
        # Skip blank lines
        while j < len(lines) and lines[j].strip() == '':
            j += 1
        # Now, for contiguous bullet lines starting at less than 4 spaces, indent them
        while j < len(lines):
            match = bullet_pat.match(lines[j])
            if match:
                indent = match.group(1)
                # If indentation is already >=4, stop
                if len(indent.replace('\t', '    ')) >= 4:
                    break
                # Otherwise, add 4 spaces
                lines[j] = '    ' + lines[j]
                changed = True
                j += 1
            else:
                # If next lines are code block, admonition, header or so, stop adjusting
                if lines[j].startswith('    ') or lines[j].startswith('\t'):
                    j += 1
                    continue
                break
        i = j
    else:
        i += 1

if changed:
    bak = p.with_suffix('.md.bak')
    if not bak.exists():
        p.rename(bak)
        p.write_text('\n'.join(lines) + '\n')
        print('Patched and backed up original to', bak)
    else:
        p.write_text('\n'.join(lines) + '\n')
        print('Patched in-place (backup already exists)')
else:
    print('No changes necessary')
