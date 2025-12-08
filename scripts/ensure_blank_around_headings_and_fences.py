#!/usr/bin/env python3
"""Ensure blank lines around headings and fenced code blocks outside frontmatter.
"""
import re, sys
from pathlib import Path

def process_file(p):
    s=p.read_text()
    lines=s.splitlines()
    out=[]
    in_f=False
    i=0
    while i<len(lines):
        line=lines[i]
        if re.match(r"^\s*(`{3,}|~{3,})", line):
            if out and out[-1].strip()!='':
                out.append('')
            out.append(line)
            i+=1
            # copy until closing
            while i<len(lines) and not re.match(r"^\s*(`{3,}|~{3,})", lines[i]):
                out.append(lines[i])
                i+=1
            if i<len(lines):
                out.append(lines[i])
                i+=1
            if i<len(lines) and lines[i].strip()!='':
                out.append('')
            continue
        # heading
        if re.match(r"^\s*#{1,6}\s+", line):
            if out and out[-1].strip()!='':
                out.append('')
            out.append(line)
            # add blank line after heading where appropriate
            if i+1<len(lines) and lines[i+1].strip()!='' and not re.match(r"^\s*(#{1,6}|(`{3,}|~{3,})|[-*+]|\d+\.)", lines[i+1]):
                out.append('')
            i+=1
            continue
        out.append(line)
        i+=1

    final='\n'.join(out)+"\n"
    if final!=s:
        p.write_text(final)
        print('Patched', p)
        return True
    return False

if __name__=='__main__':
    if len(sys.argv)<2:
        print('Usage: ensure_blank_around_headings_and_fences.py <dir>')
        sys.exit(1)
    import os
    changed=False
    for r in sys.argv[1:]:
        for dirpath, _, filenames in os.walk(r):
            for f in filenames:
                if f.endswith('.md'):
                    if process_file(Path(os.path.join(dirpath,f))):
                        changed=True
    if changed:
        sys.exit(0)
    sys.exit(0)
