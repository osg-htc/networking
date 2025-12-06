# Deprecations

This document tracks deprecations in the `osg-htc/networking` repository and provides migration guidance.

## Deprecated: `check-deps.sh`

- Status: Deprecated
- First announced: 2025-11-10
- Planned removal: 2026-03-01 (or later, based on user feedback)
- Affected path: `docs/perfsonar/tools_scripts/check-deps.sh`

### Why it's deprecated

The unified prerequisite installation and the guided orchestrator now cover dependency checks and setup in a more robust, repeatable way. Maintaining a separate dependency checker duplicates logic and increases drift.

### Recommended replacements

- Install prerequisites up front (RHEL/Alma/Rocky 9):
    - See Step 1 of `docs/personas/quick-deploy/install-perfsonar-testpoint.md` for the one-shot package install.
- Use the guided installer to verify and apply configuration:
    - Orchestrator: `docs/perfsonar/tools_scripts/perfSONAR-orchestrator.sh`
    - Bootstrap fetcher: `docs/perfsonar/tools_scripts/install_tools_scripts.sh`

### Migration

- If you previously called `check-deps.sh` as a first step, replace it with:
    1. Running the one-shot package installation from the guide.
    2. Running the orchestrator in guided or non-interactive mode.

- If automation still references `check-deps.sh`, pin to a known commit while you migrate. The file will remain read-only until removal and may not receive updates.

### Notes

- If you have a use case not covered by the orchestrator or the one-shot package install, please open an issue describing the gap so we can incorporate it.
