# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- Budgeting: never choose a service or dependency that requires upfront card details or payment, unless the project manager explicitly says otherwise. Prefer secure, cost-efficient options. Always confirm on the provider's own pricing/plan pages, read in their entirety. Never decide from a first glance or a summary.
- Open Source and Privacy: check every tool, dependency and service for telemetry, and pick options that respect users' privacy while staying secure.
- Clean up loose ends: close ports, dev servers, and other connections as soon as they're no longer needed.
- All code, whether written, borrowed or reused, must meet OWASP and OSINT security standards. Check dependencies for vulnerabilities, and give keys and webhooks least privilege.
- Double check before every commit: review staged changes for keys, secrets, private mentions, and critical infrastructure. Commits to this public repo can't be taken back.
- This repo is PUBLIC: never print or commit secrets, keys, or PII. Keep the single root `/.gitignore` updated; no nested `.gitignore` files.
- When guidelines change, sync `AGENTS.md`, `.github/copilot-instructions.md` and `.cursorrules`. `GEMINI.md` imports the guidelines directly.

## Project state
Portfolio Jockey v2 is a fully local, offline, encrypted project tracker built with Flutter for **Linux desktop**.
- No app code exists yet. Plan phases 0–2 (guidelines, mockups, toolchain) are done, and phase 3 (the scaffold) is next.
- The approved plan, including the encryption and storage design and the phase list, is `project-changelog/2026-10-22/local-app/plan.md`.
- The Android port is on hold because the Android SDK license was declined (`public-notes/android-port.md`). Don't add Android platform code or install the Android SDK.

## Toolchain
- `bash .devcontainer/check-lockdown.sh`: checks every telemetry layer. It must pass before running `flutter` or `dart`.
- `bash .devcontainer/setup.sh`: installs or repairs the pinned Flutter 3.47.7 and its telemetry patch. Safe to re-run.
- To upgrade Flutter, edit `FLUTTER_VERSION` and `FLUTTER_SHA256` in `setup.sh` and confirm the patch still applies. Never run `flutter upgrade` or `flutter channel`: they overwrite the patched source.
- Build, lint and test commands get added here once phase 3 creates the app.

## Constraints that shape the code
- The app must never use the network. No analytics, crash-reporting or networking packages, and no local HTTP servers, which rules out the usual workaround for streaming media.
- Every new package needs a license, cost and telemetry check recorded in `docs/dependencies.md`.
- Every action that writes to disk shows a confirm/cancel step, as the project brief requires.

## Repo conventions
- Changelogs and backups for the local app go in `local-app/` subfolders: `project-changelog/YYYY-MM-DD/local-app/` and `version-control/local-app/<date>_before-<change>/`, each with a README explaining how to restore. Cloud-era history is under `cloud-service/`.
- `public-notes/` is tracked and public. `project-notes/` is git-ignored and holds the project manager's private notes, prompts and session handoff.
- Mockups: on each page, `mockup.js` clones every `.scene > .screen` into a desktop window and a phone frame. The phone layout comes from container queries in `styles.css`.
