# CLAUDE.md

Before doing anything in this repository, read and follow all project guidelines. They are imported below so every Claude session loads them automatically.

@project-guidelines/implementation.md
@project-guidelines/security.md

## Key reminders
- Never edit without explicit user permission; plan changes first (plan mode).
- Ask the user/project manager when uncertain.
- Log every change in `project-changelog/YYYY-MM-DD/<change>.md` with details, impacts and the time it was done (`**Time:** YYYY-MM-DD HH:MM UTC`) (untracked/.gitignored components are exempt).
- Back up prior versions of changed application components to `version-control/` (docs exempt). Never back up anything holding or exposing API keys, webhooks or secrets, such as `.env`. Hard-coded or plain-text secrets must never exist at all.
- New env variables go in `/.env_example` with EMPTY values and annotations on purpose and setup. Never put real values in annotations.
- Floor Planning: show UI mockups before building or changing any UI. Agreed format is static HTML with fake data in `/project-mockups/`.
- Budgeting: never choose a service or dependency that requires upfront card details or payment, unless the project manager explicitly says otherwise. Prefer secure, cost-efficient options. Always confirm on the provider's own pricing/plan pages, not summaries.
- Clean up loose ends: close ports, dev servers, and other connections as soon as they're no longer needed.
- Double check before every commit: review staged changes for keys, secrets, private mentions, and critical infrastructure. Commits to this public repo can't be taken back.
- This repo is PUBLIC: never print or commit secrets, keys, or PII. Keep the single root `/.gitignore` updated; no nested `.gitignore` files.
- `AGENTS.md` mirrors these rules for non-Claude agents. If guidelines change, keep it in sync.
