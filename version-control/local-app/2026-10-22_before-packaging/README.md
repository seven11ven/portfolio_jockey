# Backup: before the Flatpak packaging files (phase 8, step 3)

Snapshot taken on 2026-10-22, before step 3 changed these files. Each file keeps its repo path.

- `root.gitignore`: the root `.gitignore` (renamed so it isn't a nested `.gitignore`), before the entries for the bundle, build kit and Flatpak build output.
- `app/tool/check-privacy.sh`: before its native-code and network-API scans also covered `app/tool/`.
- `app/tool/allowed-native-libs.txt`: before the line for `tool/verify_minisign.dart`.

Every other step 3 file is new (`packaging/flatpak/`, `app/tool/package-bundle.sh`, `app/tool/verify_minisign.dart`, `app/test/tool/`).

## Restore
Copy the files back to the same paths in the repo (`root.gitignore` back to `/.gitignore`), and delete the new files listed above.

No secrets are included.
