# DevTools autostart off, and the brief moved to public-notes

**Date:** 2026-10-22
**Time:** 2026-10-22 14:23 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Why
After phase 3 created `app/`, the VS Code Dart extension began starting local background services as soon as the editor opened. The project manager asked that they not start automatically.

## Change
- **`.devcontainer/devcontainer.json`:** added `"dart.shareDevToolsWithFlutter": false` to the VS Code settings, next to `dart.allowAnalytics`.
  - The extension's code (Dart-Code 3.144.0) starts the DevTools server eagerly only when this setting is `true` (the default) and the workspace has a Flutter project.
  - DevTools still opens on demand while debugging.
- **This container** (outside the repo): the same setting was added to the container's machine settings, and the running DevTools server was stopped. Port `127.0.0.1:9100` is closed.
- **`docs/dependencies.md`:** a new "Background services the Dart extension starts" table.
- **The brief moved:** the project manager moved it from the private `project-notes/prompts/` to the public `public-notes/prompts/application.md`, and added `public-notes/commands/git-add.md`. Two stale references were updated:
  - `project-changelog/2026-10-22/local-app/plan.md` (Context)
  - `CLAUDE.md` (Repo conventions)

## Not possible
- **The Dart Tooling Daemon (DTD) can't be turned off.** The extension has no user setting for it. It disables it internally only for Bazel and Fuchsia workspaces, and the analysis server connects to it. It listens only on `127.0.0.1` and isn't telemetry. This is documented in `docs/dependencies.md`.

## Security review
- **`public-notes/commands/git-add.md` and `public-notes/prompts/application.md`** were read in full, including hidden characters. They contain no secrets, keys, personal details, email addresses, hostnames, IP addresses or private paths. They're fine to publish.
- **All pending changes** (31 files at the time, plus this change's files) were scanned for keys, tokens, email addresses, IP addresses, local temporary paths and long random strings. Nothing was found. The hits were the guidelines' own wording about secrets, and the public package checksums in `app/pubspec.lock`. The only identifier is the GitHub username in the app ID, which the project manager chose and which is already public in the repo URL. Nothing was staged.

## Verification
- `devcontainer.json` (with its comments removed) and the machine settings both parse as JSON.
- After the change, no `dart devtools` process is running and port 9100 is closed. Only DTD (loopback) and VS Code's own ports remain.
- `check-lockdown.sh` and `app/tool/check-privacy.sh` both pass.

## Impacts
- **New dev containers** won't start DevTools until it's asked for.
- **In this container,** a "Developer: Reload Window" applies the setting to the running extension. Until then, the extension could restart DevTools if a debug session asks for it.
- **Backup:** `version-control/local-app/2026-10-22_before-devtools-autostart/` holds the previous `devcontainer.json`.
