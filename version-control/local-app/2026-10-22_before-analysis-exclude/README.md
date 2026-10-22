# Backup: before excluding version-control/ from Dart analysis

Snapshot taken on 2026-10-22, before `dart.analysisExcludedFolders` was added to the dev container's VS Code settings.

- `.devcontainer/devcontainer.json`: the config with `dart.allowAnalytics` and `dart.shareDevToolsWithFlutter` only.

Why the change: the Dart extension analysed the backed-up `.dart` files in `version-control/`. Outside the app folder their imports can't be resolved, which showed as 794 false errors in the Problems panel.

## Restore
Copy `.devcontainer/devcontainer.json` back to the repo root, keeping its path, then rebuild the dev container.

No secrets are included.
