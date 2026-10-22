# AI agent instruction files added

**Date:** 2026-10-22
**Time:** 2026-10-22 00:41 UTC
**Requested by:** repository owner
**Performed by:** Claude Code

## Change
Added startup instruction files so every AI agent reads `project-guidelines/` on initiation:

| File | Read by |
|------|---------|
| `CLAUDE.md` | Claude Code (imports the guideline files directly) |
| `AGENTS.md` | OpenAI Codex/ChatGPT, Cursor, Jules, and other agents using the AGENTS.md convention |
| `GEMINI.md` | Gemini CLI / Gemini Code Assist (imports AGENTS.md and guidelines) |
| `.github/copilot-instructions.md` | GitHub Copilot |
| `.cursorrules` | Cursor (legacy rules file) |

## Impacts
- No application code changed; documentation only, so no `version-control/` backup required.
- `project-guidelines/` stays the single source of truth. When it changes, update the summary in `AGENTS.md` and the short rules in `.github/copilot-instructions.md` and `.cursorrules`.


# Agent instruction files synced with updated guidelines

**Time:** 2026-10-22 00:58 UTC

Updated `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, and `.cursorrules` to reflect new guideline rules:
- Logging is not required for untracked components (anything covered by `.gitignore`).
- New environment variables must be added to `/.env_example` with empty values and annotations.
- Only one `.gitignore` is allowed, at the repo root.

`GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.
- All agents now receive the same current rules on startup.

---

# Agent instruction files synced with "Double check before a commit" rule

**Time:** 2026-10-22 01:02 UTC

Added the new security rule from `project-guidelines/security.md` to `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, and `.cursorrules`: review staged changes for keys, secrets, private mentions, and critical infrastructure before every commit.

`GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.
- Security rules in `AGENTS.md` were renumbered so the commit check comes first.

---

# Agent instruction files synced with "Floor Planning" rule

**Time:** 2026-10-22 01:21 UTC

Added the new rule from `project-guidelines/implementation.md` to `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, and `.cursorrules`: present UI mockups before building or changing any UI. Also recorded the agreed mockup format, which is static HTML with fake sample data in `/project-mockups/`.

`GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.
- No agent may build UI before mockups are approved.

---

# Changelog timestamps added; agent files synced with the time rule

**Time:** 2026-10-22 01:46 UTC

The logging rule in `project-guidelines/implementation.md` now requires the time each change was made.
- Added a `**Time:**` line to every existing changelog section from today. Times come from the AI session log of when each entry was written, in UTC, the Codespace's clock.
- Updated `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` and `.cursorrules` so every agent includes the time in future entries.

`GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.
- All future changelog entries include a time.

---

# Agent files synced with the version-control secrets rule

**Time:** 2026-10-22 05:50 UTC
**Requested by:** project manager

The version-control rule in `project-guidelines/implementation.md` now says backups must never include critical components that could expose API keys, webhooks or secrets, and that hard-coded or plain-text secrets must never exist at all. This rule was added earlier and committed with plan step 4, but the agent files hadn't been synced with it.
- Added it to `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` and `.cursorrules`.
- The project manager also removed the "This Guideline also extends to implementations" line from `project-guidelines/security.md`. The agent files never included it, so nothing needed removing.
- Checked existing backups: no `version-control/` folder contains a secret. The two backed-up `.env_example` copies only hold empty placeholders.

`GEMINI.md` needed no change because it imports the guideline files directly.

## Impacts
- Documentation only; no `version-control/` backup required.

---

# Agent files synced with the "Budgeting" rule

**Time:** 2026-10-22 06:03 UTC

The project manager added a "Budgeting" section to `project-guidelines/implementation.md`. Dependencies and third-party services must be price conscious, and, unless explicitly stated otherwise, must never require upfront card details or payment. Secure, cost-efficient options come first.
- Added it as implementation rule 7 in `AGENTS.md`, a reminder in `CLAUDE.md`, and the one-line summaries in `.github/copilot-instructions.md` and `.cursorrules`.
- `GEMINI.md` needed no change because it imports the guideline files directly.
- The switch from Cloudflare R2 (card required) to Backblaze B2 (no card) already follows this rule. See `backblaze-switch.md`.

## Impacts
- Documentation only; no `version-control/` backup required.

---

# Agent files synced with the Budgeting "check the website" line

**Time:** 2026-10-22 06:14 UTC

The Budgeting rule gained a sub-point: always check the resource's own website or documentation to confirm whether it's paid-only or free. It was added to `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` and `.cursorrules`. `GEMINI.md` imports the guidelines directly.

## Impacts
- Documentation only; no `version-control/` backup required.
