# Backup: before shipping license files and sources with the Flatpak

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `packaging/flatpak/io.github.seven11ven.portfolio_jockey.yml`: before each module installed its license files.
- `packaging/flatpak/build.sh`: before it built a sources bundle and installed the app from the `.flatpak` file.
- `app/tool/package-bundle.sh`: before it shipped `LICENSE` and made the app's source tarball.
- `root.gitignore`: the root `.gitignore` (renamed so it isn't a nested `.gitignore`), before the `repo/` entry.

## Restore
Copy the files back to the same paths in the repo (`root.gitignore` back to `/.gitignore`).

No secrets are included.
