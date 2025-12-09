#!/usr/bin/env python3
from pathlib import Path
path=Path('docs/perfsonar/installation.md')
lines=path.read_text(encoding='utf-8').splitlines()
for idx in [137,138]:  # 0-based indices for 138th and 139th lines
    if idx < len(lines):
        if not lines[idx].startswith('    '):
            lines[idx] = '    ' + lines[idx]
path.write_text('\n'.join(lines)+'\n', encoding='utf-8')
print('Indented lines 138-139 in',path)
