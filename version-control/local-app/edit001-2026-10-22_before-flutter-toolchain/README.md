# Backup: before adding the Flutter toolchain

Snapshot taken on 2026-10-22, before plan phase 2 (toolchain and privacy lockdown).

- `.devcontainer/devcontainer.json`: the minimal dev container left by the local reset. It used the Node 24 image (`typescript-node:4-24-bookworm`), ran no setup and had no telemetry lockdown.
- `root.gitignore`: the root `.gitignore` (renamed on 2026-10-23 so it isn't a nested `.gitignore`), before the Flutter and Dart build entries were added.

## Restore
Copy both files back to the repo root, keeping their paths (`root.gitignore` goes back as `.gitignore`), then rebuild the dev container.

No secrets are included.
