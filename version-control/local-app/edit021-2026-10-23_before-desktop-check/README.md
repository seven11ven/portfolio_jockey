# Backup: before the desktop check tools

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `.devcontainer/setup.sh`: before it installed xvfb, xdotool, xclip, python3-yaml, appstream and desktop-file-utils, for `app/tool/desktop-check.sh`.
- `root.gitignore`: the root `.gitignore` (renamed so it isn't a nested `.gitignore`), before the desktop check's output folder was listed.

## Restore
Copy the files back to the same paths in the repo (`root.gitignore` back to `/.gitignore`).

No secrets are included.
