# Docs Cleanup Scripts

This folder contains a set of small helper scripts used to normalize and automatically fix common Markdown errors across the repository. The scripts are intentionally conservative and are safe to run locally. They do not change the semantic content of fenced code blocks (e.g. commands and code examples).

## Usage examples

- Add heuristic languages to unlabeled fences in a docs tree:

```bash
python3 scripts/assign_fence_language.py docs
```

- Normalize fence indentation across a docs tree:

```bash
python3 scripts/normalize_fence_indent.py docs
```

- Apply markdownlint `fixInfo` suggestions from a JSON output file:

```bash
python3 scripts/apply_markdownlint_fixes.py tmp/markdownlint_install-testpoint_postfix.json
```

- Attempt to fix MD040 (fenced code language) findings using linter JSON suggestions:

```bash
python3 scripts/fix_md040_from_json.py tmp/markdownlint_repo.json
```

## Testing

Simple smoke tests exist under `scripts/tests` to demonstrate how to run the scripts safely on fixtures. The smoke tests do not touch the repository's `docs` directory; they operate on a temporary fixtures copy.

Run the smoke tests:

```bash
bash scripts/tests/run_tests.sh
```

## Notes and tips

- Use VENV when running these tools locally; they are Python scripts and assume a typical Linux environment.
- The scripts aim to be conservative: if in doubt they default to adding `text` as a neutral fenced-code language label to avoid changing semantics.
- If a script acts on files you do not want to change, run it against a single file or a fixtures directory first and use `git diff` to review changes.

If you need help adding additional heuristics or tests, submit an issue or open a PR describing the desired behavior.
