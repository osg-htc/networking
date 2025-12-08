import io
import sys
import os
from markdown import Markdown
from markdown import markdown

extensions=['toc','tables','fenced_code','admonition','mdx_details','codehilite','meta','pymdownx.superfences','attr_list','pymdownx.emoji']
# pymdownx details plugin name is 'pymdownx.details' but import name may differ

path = 'docs/personas/quick-deploy/install-perfsonar-testpoint.md'
if not os.path.exists(path):
    print('File not found:', path)
    sys.exit(1)

with open(path, 'r') as f:
    md = f.read()

# try with a variety of extension names if necessary
ext = [
    'toc', 'tables', 'fenced_code', 'admonition', 'pymdownx.details', 'codehilite', 'meta', 'pymdownx.superfences', 'attr_list', 'pymdownx.emoji'
]

html = markdown(md, extensions=ext)

print('length', len(html))
# print snippet around </li>
for i in range(0, len(html)): 
    idx = html.find('</li>', i)
    if idx==-1:
        break
    start = max(0, idx-80)
    end = min(len(html), idx+80)
    print('--- snippet ---')
    print(html[start:end])
    i = idx+1


# check for </li> without <li> earlier in the file
if '</li>' not in html:
    print('No </li>')
else:
    print('Found </li> count:', html.count('</li>'))

# search for strange constructs
if '<li>' not in html and '</li>' in html:
    print('Found </li> but no <li>')

# Save HTML
with open('tmp_install_page.html','w') as f:
    f.write(html)
print('Saved HTML to tmp_install_page.html')
