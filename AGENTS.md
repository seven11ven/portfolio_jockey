# AI Agent Instructions (all agents)

This file is read on startup by AI coding agents (OpenAI Codex/ChatGPT, Gemini, Cursor, Copilot, Claude, and others).
**Before doing anything in this repository, read every file in [`project-guidelines/`](project-guidelines/) and follow it.**
Those files are the single source of truth. The summary below is a quick reference; if it ever conflicts with `project-guidelines/`, the guidelines win.

- [`project-guidelines/implementation.md`](project-guidelines/implementation.md)
- [`project-guidelines/security.md`](project-guidelines/security.md)

## Implementation rules (summary)
1. **Never edit off the bat.** Reading is fine. Any permanent or temporary change must be planned first (planning mode) and requires explicit permission from the user. Never edit the repo automatically.
2. **Always ask questions.** When uncertain about the project or a change, ask the project manager/user before acting.
3. **Log your actions.** Every change/build gets a markdown entry in `project-changelog/YYYY-MM-DD/` (reuse today's folder if it exists), describing the change and its impacts. Untracked components (anything covered by `.gitignore`) are exempt.
4. **Version control.** Before changing any application component, store its prior version in `version-control/`. Applies to packages/dependencies, modules/scripts, application builds, and servers. Documentation (guidelines, changelogs, notes) is exempt.
5. **Environment variables.** When adding a new variable, update `/.env_example` to mirror what `.env` should look like. Leave every value EMPTY, and annotate each variable with what it does and how to set it up. Never reveal a real secret or API value in the annotation.

## Security rules (summary)
1. **This repo is PUBLIC.** Never expose secrets, keys, API credentials, or PII in code, commits, the console/terminal, agent chat, or anywhere public. Avoid commands that print them.
2. **Verify code security.** Check packages/dependencies for vulnerabilities, grant webhooks and API keys least-privilege permissions only, and keep code to OWASP standards.
3. **Keep `.gitignore` current.** Immediately add backend secrets, database files, keys, and `.env` files to `.gitignore`.
4. **One `.gitignore` only.** Use only the root `/.gitignore`; never create nested `.gitignore` files. Keep it consistently updated with critical infrastructure from builds, packages, and other applicable pieces.
