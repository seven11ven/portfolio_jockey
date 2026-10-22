# Guideline: examine the code of every third-party package

**Date:** 2026-10-22
**Time:** 2026-10-22 14:17 UTC
**Guideline written by:** project manager
**Synced by:** Claude Code

## Change
- **`project-guidelines/implementation.md`** → "Open Source and Privacy": the project manager added a rule:
  > When implementing third party packages or any resource, always examine the code. Never take it at face value. Look for any traces of telemetry or tracking related functions/programs.

  The text is left exactly as the project manager wrote it.
- **Synced into the agent files**, as `CLAUDE.md` requires when guidelines change:
  - `CLAUDE.md` (Key reminders)
  - `AGENTS.md` (item 8)
  - `.github/copilot-instructions.md`
  - `.cursorrules`

  `GEMINI.md` imports the guidelines directly, so it needs no change.

## Impacts
- Checking a package's web page or docs is no longer enough. Its downloaded source must be read for telemetry and tracking before it's used.
- First applied in plan phase 3 (`scaffold.md`): every package in the app's dependency tree was code-reviewed. The review is now automated by `app/tool/check-privacy.sh`, which fails whenever a package's code changes and hasn't been re-reviewed.
