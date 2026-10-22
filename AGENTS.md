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
6. **Floor Planning (UI mockups first).** Before building or changing any UI, present clear mockups to the project manager instead of improvising. Ask them how they want mockups presented. The agreed format is static HTML mockups with fake sample data in `/project-mockups/`.

## Security rules (summary)
1. **Double check before every commit.** Review staged changes for keys, secrets, private mentions (including references to ignored/private files), and critical infrastructure. Anything committed to this public repo cannot be taken back.
2. **This repo is PUBLIC.** Never expose secrets, keys, API credentials, or PII in code, commits, the console/terminal, agent chat, or anywhere public. Avoid commands that print them.
3. **Verify code security.** Check packages/dependencies for vulnerabilities, grant webhooks and API keys least-privilege permissions only, and keep code to OWASP standards.
4. **Keep `.gitignore` current.** Immediately add backend secrets, database files, keys, and `.env` files to `.gitignore`.
5. **One `.gitignore` only.** Use only the root `/.gitignore`; never create nested `.gitignore` files. Keep it consistently updated with critical infrastructure from builds, packages, and other applicable pieces.
6. **Clean up loose ends.** Never leave ports, dev servers, tunnels, or other connections open. Close them as soon as they are no longer in use to minimize the attack surface.

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
