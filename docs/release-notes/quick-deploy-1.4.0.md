# Release Notes - Quick Deploy Guide v1.4.0

**Release Date:** November 10, 2025

## Overview

Version 1.4.0 focuses on reliability, guided automation, and simplifying the earliest steps of a perfSONAR testpoint deployment. It introduces a new orchestrator, improves policy-based routing safety, and deprecates an older dependency-checker script in favor of a unified package install workflow.

## Highlights

### Guided Orchestrator (New)
`perfSONAR-orchestrator.sh` provides a step-by-step (or non-interactive) path through prerequisites, bootstrap, network configuration (PBR), security hardening, container deployment (Option A/B), certificate issuance, and pSConfig enrollment.

Key features:
1. Interactive confirm/skip flow or `--non-interactive` batch mode.
2. Supports selection between deployment options (testpoint only vs Let's Encrypt).
3. Automatic DNS and certificate validation checkpoints.
4. Exit codes suitable for automation.

### Non-Disruptive PBR Mode (Improved)
`perfSONAR-pbr-nm.sh` now defaults to an in-place apply mode that preserves existing NetworkManager connections and minimizes SSH disruption. A full rebuild can still be invoked with `--rebuild-all` when a clean slate is needed.

### Unified Prerequisite Installation (Simplified)
The guide now uses a single one-shot `dnf` command (on EL9 derivatives) early in Step 1 to install all required packages (including DNS tools). This replaces iterative dependency checks and removes friction on minimal hosts.

### Deprecation: `check-deps.sh`
The legacy dependency checking script is deprecated. Its responsibilities are replaced by the unified package install and orchestrator validation steps. See `DEPRECATION.md` for migration guidance and the planned removal timeline.

## Detailed Changes

- Added orchestrator script with interactive and batch operation modes.
- Updated Quick Deploy Steps 1–3 to surface orchestrator early and remove `sudo` prefixes.
- Improved documentation spacing and markdownlint compliance.
- Introduced non-disruptive default mode for PBR script, reducing need for console access.
- Added dedicated deprecation tracking file `DEPRECATION.md`.
- Updated CHANGELOG with new version entry and deprecation notice.

## Upgrade Path

From v1.3.0:
1. Refresh helper scripts:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh | bash -s -- /opt/perfsonar-tp
   ```
2. Review `DEPRECATION.md` and remove any automation references to `check-deps.sh`.
3. Use orchestrator for new hosts or when revalidating configuration:
   ```bash
   /opt/perfsonar-tp/tools_scripts/perfSONAR-orchestrator.sh --option A --fqdn <FQDN> --email <EMAIL>
   ```
4. (Optional) Reapply PBR in non-disruptive mode:
   ```bash
   /opt/perfsonar-tp/tools_scripts/perfSONAR-pbr-nm.sh --apply-inplace
   ```

## Validation

- MkDocs site builds without structural errors after additions.
- Orchestrator help/usage renders correctly in documentation references.
- PBR script tested for idempotent route/rule replacement.

## Deprecations

- `check-deps.sh` (planned removal: 2026-03-01) — replace with unified install + orchestrator.

## Breaking Changes

None. All enhancements are backward compatible; deprecated script is still present for transition.

## Commits

- docs/orchestrator: add guided install script and integrate into quick-deploy
- docs/pbr: add in-place mode and update guide references
- docs: remove `sudo` prefixes and fix markdown spacing
- chore: add DEPRECATION.md and update CHANGELOG for v1.4.0

## Next Steps

- Remove deprecated dependency checker after transition window.
- Add automated test harness for orchestrator flows.
- Expand CI to include link checking heuristics under controlled ignore patterns.

---

For the full installation guide, see [Installing a perfSONAR Testpoint for WLCG/OSG](../personas/quick-deploy/install-perfsonar-testpoint.md).
