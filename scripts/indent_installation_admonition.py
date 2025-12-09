#!/usr/bin/env python3
import io,sys
path='docs/perfsonar/installation.md'
text=open(path,encoding='utf-8').read()
old='\nAll perfSONAR instances must have port 443 accessible to other perfSONAR instances. Port 443 is used by pScheduler to schedule tests. If unreachable, \ntests may not run and results may be missing.\n'
new='\n    All perfSONAR instances must have port 443 accessible to other perfSONAR instances. Port 443 is used by pScheduler to schedule tests. If unreachable, \n    tests may not run and results may be missing.\n'
if old in text:
    text=text.replace(old,new)
    open(path,'w',encoding='utf-8').write(text)
    print('Patched',path)
else:
    print('Pattern not found in',path)
