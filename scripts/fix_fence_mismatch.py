#!/usr/bin/env python3
"""
Simple script to normalize fencing in a Markdown file:
- Any closing fence that contains a language (like ```bash) is converted to ```
- Any opening fence that is ```, and the following non-empty line begins with common shell commands, is changed to ```bash
This runs in dry-run mode by default and can apply changes with --apply
"""
import argparse
import re
from pathlib import Path

SHELL_CMD_RE = re.compile(r"^(\s*)(sudo\s+|bash\s+|curl\s+|sysctl\s+|sha256sum\s+|ethtool\s+|tc\s+|tuned-adm\s+|grubby\s+|grub2-mkconfig\s+|update-grub\s+|cat\s+|awk\s+)")


def normalize_file(path: Path, apply: bool = False) -> dict:
    lines = path.read_text(encoding="utf-8").splitlines()
    changed = []
    in_fence = False
    fence_lang = None
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^(\s*)```(\w+)?\s*$", line)
        if m:
            if not in_fence:
                # opening fence
                lang = m.group(2) or ""
                # look ahead for next non-empty line
                j = i+1
                while j < len(lines) and lines[j].strip() == "":
                    j += 1
                next_line = lines[j] if j < len(lines) else ""
                if not lang:
                    if SHELL_CMD_RE.match(next_line):
                        new_line = m.group(1) + "```bash"
                        if new_line != line:
                            changed.append((i+1, line, new_line))
                            lines[i] = new_line
                            lang = "bash"
                # Normalize explicit 'text' language fences to plain fences to avoid html leaking
                elif lang == 'text':
                    new_line2 = m.group(1) + "```"
                    if new_line2 != line:
                        changed.append((i+1, line, new_line2))
                        lines[i] = new_line2
                fence_lang = lang
                in_fence = True
            else:
                # closing fence
                # Always normalize closing fence to plain ```
                leading = m.group(1)
                new_line = leading + "```"
                if new_line != line:
                    changed.append((i+1, line, new_line))
                    lines[i] = new_line
                in_fence = False
                fence_lang = None
        i += 1
    if apply and changed:
        backup = path.parent / ".indent_fix_backups"
        backup.mkdir(exist_ok=True)
        bakfile = backup / (path.name + ".bak.auto")
        if not bakfile.exists():
            bakfile.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"path": str(path), "changes": changed}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="Markdown files to normalize")
    parser.add_argument("--apply", action="store_true", help="Apply changes")
    args = parser.parse_args()
    total = []
    for f in args.files:
        res = normalize_file(Path(f), apply=args.apply)
        total.append(res)
    for r in total:
        print(r["path"])
        if not r["changes"]:
            print('  no changes')
        else:
            print('  changes:')
            for ln, old, new in r["changes"]:
                print(f"   - line {ln}: '{old}' -> '{new}'")

if __name__ == '__main__':
    main()
