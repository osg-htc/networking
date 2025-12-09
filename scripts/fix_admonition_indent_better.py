#!/usr/bin/env python3
"""
Improve conservative adjustment of fenced codeblocks indented too far inside admonitions.

This scans Markdown under docs/, finds fenced code blocks inside admonition blocks ('!!!'), and
if the opening or closing fence lines are indented by more than 4 spaces, it reduces the indentation
to 4 spaces for the fence lines and for all lines in the fenced block's content, preserving relative
indent where reasonable.

Writes backups to docs/.indent_fix_backups/
"""
import re,os,sys
from pathlib import Path
import argparse
from datetime import datetime


def find_fences(lines):
    """Return list of tuples (start_idx, end_idx, fence_indent, fence_lang)
    where start_idx and end_idx are 0-based inclusive start/stop indices in lines.
    """
    fence_re=re.compile(r'^(?P<indent>\s*)(?P<fence>```+)(?P<lang>\w+.*)?$')
    in_fence=False
    start=None
    indent=None
    lang=None
    out=[]
    for i,l in enumerate(lines):
        m=fence_re.match(l.rstrip('\n'))
        if m:
            if not in_fence:
                in_fence=True
                start=i
                indent=len(m.group('indent'))
                lang=m.group('lang') or ''
            else:
                # end
                end=i
                out.append((start,end,indent,lang.strip()))
                in_fence=False
                start=None
                indent=None
                lang=None
    return out


def find_admonitions(lines):
    # Return list of (start_idx, end_idx), where start is the '!!!' line index and end is the last
    # line before the next non-indented block (approx). Simpler approach: find '!!!' and assume its
    # content lines are indented by at least 4 spaces; find first subsequent line which has less than 4
    # leading spaces and is not blank, marking admonition end.
    admon_re=re.compile(r'^\s*!!!')
    admonitions=[]
    i=0
    N=len(lines)
    while i<N:
        if admon_re.match(lines[i]):
            start=i
            j=i+1
            while j<N:
                l=lines[j]
                # end when we see a line that starts text at column 0 (no leading spaces) and is not blank
                if l.strip() and (not l.startswith(' ')):
                    break
                j+=1
            end=j-1
            admonitions.append((start,end))
            i=j
        else:
            i+=1
    return admonitions


def inside_admon(idx, admonitions):
    for s,e in admonitions:
        if s<idx<=e:
            return True, (s,e)
    return False, None


def fix_file(path, dry_run=True, backup=True):
    with open(path,'r',encoding='utf-8',errors='ignore') as fh:
        lines=fh.readlines()
    fences=find_fences(lines)
    admons=find_admonitions(lines)
    if not fences:
        return 0
    modified=False
    changes=0
    for s,e,indent,lang in fences:
        # check if inside an admonition
        inz,alen=inside_admon(s,admons)
        # compute context: is it inside a list item? find the nearest previous non-blank line
        prev_line_idx=None
        for j in range(s-1, max(0,s-15), -1):
            if lines[j].strip():
                prev_line_idx=j
                break
        list_indent=None
        if prev_line_idx is not None:
            pl=lines[prev_line_idx]
            m=re.match(r'^(\s*)([-*]|\d+\.)\s+',pl)
            if m:
                list_indent=len(m.group(1))
        # decide target indent
        if inz:
            target_indent=4
        elif list_indent is not None:
            target_indent=list_indent+4
        else:
            target_indent=0
        # special-case: if target_indent is 4 but the fence is inside a 4-space indented pre block
        # (i.e., previous non-blank line also starts with 4 spaces and is not list/admon), then
        # promote fence to top-level (target_indent = 0) to allow proper fenced parsing.
        if target_indent==4:
            prev_line_idx=None
            for j in range(s-1, max(0,s-10), -1):
                if lines[j].strip():
                    prev_line_idx=j
                    break
            if prev_line_idx is not None and lines[prev_line_idx].startswith('    '):
                # if preceding non-blank line also starts with 4 spaces, likely pre-block
                # avoid if it's a list marker
                if not re.match(r'^\s*([-*]|\d+\.)\s+', lines[prev_line_idx]):
                    target_indent=0
        if indent==target_indent:
            continue
        if indent<=4:
            continue
        # dedent (or re-indent) the fence and the content to target_indent, compute shift
        shift=indent-target_indent
        for i in range(s,e+1):
            l=lines[i]
            # only adjust if leading spaces >= indent
            # remove exactly shift leading spaces if present
            if l.startswith(' ' * indent):
                lines[i]=l[shift:]
                modified=True
                changes+=1
            else:
                # if a line has less indentation, skip (safety)
                pass
    if modified:
        if backup:
            bdir=os.path.join(os.path.dirname(path),'..','.indent_fix_backups')
            os.makedirs(bdir,exist_ok=True)
            ts=datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
            bp=os.path.join(bdir,os.path.basename(path)+'.bak.'+ts)
            with open(bp,'w',encoding='utf-8') as fh:
                fh.writelines(lines)
        if not dry_run:
            with open(path,'w',encoding='utf-8') as fh:
                fh.writelines(lines)
    return changes


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--docs-root',default='docs')
    parser.add_argument('--files',help='Comma-separated list of files to operate on (relative to docs-root)')
    parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    docs=args.docs_root
    total=0
    if args.files:
        files_list=[os.path.join(docs,f) for f in args.files.split(',')]
        walk_files=files_list
    else:
        walk_files=[]
        for root,_,files in os.walk(docs):
            for f in files:
                walk_files.append(os.path.join(root,f))
    for path in walk_files:
        if not path.endswith('.md'): continue
        # skip backup directories
        if '.indent_fix_backups' in path: continue
        try:
            c=fix_file(path, dry_run=not args.apply)
        except Exception as ex:
            print('Error on',path,ex)
            continue
        if c>0:
            print(('Would change' if not args.apply else 'Changed'),c,'lines in',path)
        total += c
    print('Total changes:',total)


if __name__=='__main__':
    main()
