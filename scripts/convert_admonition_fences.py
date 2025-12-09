#!/usr/bin/env python3
from pathlib import Path
path=Path('docs/perfsonar/installation.md')
lines=path.read_text(encoding='utf-8').splitlines()

def process(lines):
    out=[]
    i=0
    while i<len(lines):
        l=lines[i]
        if l.strip().startswith('!!!'):
            out.append(l)
            i+=1
            # process inside admon until blank line or next '!!!' or heading
            while i<len(lines) and not lines[i].startswith('!!!') and not lines[i].startswith('##'):
                if lines[i].strip()=="```text":
                    i+=1
                    # indent subsequent lines until closing fence
                    while i<len(lines) and lines[i].strip()!="``":
                        if lines[i].strip():
                            out.append('    '+lines[i])
                        else:
                            out.append(lines[i])
                        i+=1
                    # skip closing fence line
                    if i<len(lines) and lines[i].strip()=="``":
                        i+=1
                        continue
                else:
                    out.append(lines[i])
                    i+=1
        else:
            out.append(l)
            i+=1
    return out

new=process(lines)
path.write_text('\n'.join(new)+'\n',encoding='utf-8')
print('Converted admonition fences in',path)
