# Backup: before turning off DevTools autostart

Snapshot taken on 2026-10-22, before `dart.shareDevToolsWithFlutter: false` was added to the dev container's VS Code settings.

- `.devcontainer/devcontainer.json`: the dev container config from plan phase 2. Its only VS Code setting was `dart.allowAnalytics: false`.

## Restore
Copy `.devcontainer/devcontainer.json` back to the repo root, keeping its path, then rebuild the dev container.

No secrets are included.
