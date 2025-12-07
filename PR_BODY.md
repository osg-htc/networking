Title: style(docs/perfsonar): auto-fixes + editorial fixes to satisfy markdownlint for perfsonar docs

This PR includes a set of safe, non-semantic edits to docs/perfsonar to address markdownlint issues and improve formatting.

What I changed (summary):
- Ran automated and targeted scripts to:
  - Wrap bare URLs (angle brackets) and join hyphenated URLs
  - Convert multi-line HTML `<img>` tags to Markdown images
  - Add default code fence languages (bash, json, yaml, text)
  - Collapse duplicate blank lines and enforce blank lines around headings/fences/lists
  - Normalize list marker spacing and consistent list indentation
  - Reflow long paragraphs and list items to satisfy MD013
  - Fix malformed/embedded code blocks and JSON fences
  - Escape placeholder angle-bracketed items that caused MD033 (e.g., `<iface>` -> `` `<iface>` ``)
- Added / updated helper scripts in `scripts/` to automate and re-run formatting and fixes.

Files changed (high-level):
- docs/perfsonar/* (various files) and scripts/* helper scripts.

Why: This PR aims to get the `docs/perfsonar/` subset lint-clean (markdownlint) and to make the content easier to maintain with automated scripts. Changes were designed to be non-semantic where possible and avoid content changes.

Manual review checklist (recommended):
- Verify IOMMU/Packet Pacing paragraphs were reflowed without semantic changes.
- Validate any content where multi-line HTML was converted to Markdown images (`<img>` -> `![alt](src)`).
- Check JSON snippets and code fences were preserved correctly (no loss of indentation or context).
- Confirm no necessary inline HTML semantics were accidentally removed (e.g., summary/details blocks that rely on HTML tags for behavior).
- Spot-check a few pages locally with `mkdocs build` to confirm site builds and navigation expectations.

Next steps (optional - confirm):
- Run automated fixes across the full `docs/` folder to reduce linter noise elsewhere.
- Create a follow-up PR to refactor and enforce site-wide MD rules gradually.


