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

---

# CLAUDE.md: project context added

**Time:** 2026-10-22 13:55 UTC
**Requested by:** project manager (`/init`)

Updated `CLAUDE.md`. The guideline imports and key reminders are kept, and these were added:
- The standard opening line.
- **Project state:** a local Flutter app for Linux desktop, phases 0–2 done, phase 3 next, a pointer to `plan.md`, and the Android port on hold.
- **Toolchain:** the lockdown check, the setup script, and how to upgrade Flutter safely.
- **Constraints that shape the code:** no network use, the dependency checks, and confirm/cancel for every write.
- **Repo conventions:** the `local-app/` and `cloud-service/` subfolders, `public-notes/` vs `project-notes/`, and how the mockups work.

The "AGENTS.md mirrors these rules" reminder now names every agent file to keep in sync. The guideline summaries in the other agent files didn't change, so they needed no update.

## Impacts
- Documentation only; no `version-control/` backup required.
- Future Claude sessions start with the project's current state and its toolchain rules.
