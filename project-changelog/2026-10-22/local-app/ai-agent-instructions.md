# Agent files synced with the "Open Source and Privacy" rule

**Date:** 2026-10-22
**Time:** 2026-10-22 13:25 UTC
**Performed by:** Claude Code
**Requested by:** project manager (approved plan, phase 0)

## Change
The project manager added an "Open Source and Privacy" section to `project-guidelines/implementation.md`. Before choosing any resource, dependency or third-party service, check its telemetry, and pick options that respect users' privacy while staying structurally sound and secure.
- `AGENTS.md`: added as implementation rule 8.
- `CLAUDE.md`: added a reminder after the Budgeting one.
- `.github/copilot-instructions.md` and `.cursorrules`: added to the one-line rule summary.
- `GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.
- Every agent now checks telemetry when picking tools. This rule shaped the framework choice for the local app: Flutter, with its build tools' telemetry blocked at four levels (see `plan.md` in this folder).
