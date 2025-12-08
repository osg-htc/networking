import re
from pathlib import Path

html = Path('tmp_install_page.html').read_text()

orphan_positions = []

for m in re.finditer(r'</li>', html):
    start = max(0, m.start()-200)
    snippet = html[start:m.start()]
    if '<li>' not in snippet:
        # record position and surrounding snippet
        orphan_positions.append((m.start(), html[start:m.end()+200]))

print('Found', len(orphan_positions), 'orphan </li> instances')
for pos, snip in orphan_positions[:10]:
    print('--- at', pos, '...')
    print(snip.replace('\n','\\n')[:400])
    print('---------')
