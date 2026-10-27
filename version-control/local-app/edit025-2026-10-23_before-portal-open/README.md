# Backup: before the direct portal calls and the "Open vault folder" button

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/lib/services/native/gio_apps.dart`: before "Edit in another app" inside the Flatpak went through `portal.dart`, and before `openFolder`.
- `app/lib/vault/native/libc.dart`: before `openReadOnly`, `openReadWrite` and `closeFd`.
- `app/tool/allowed-native-libs.txt`: before the `portal.dart` line.
- `app/lib/ui/home/home_screen.dart`, `project-mockups/home.html`: before the folder button.
- `app/test/screenshots/screenshots_test.dart`: before the redraw between the passphrase and confirm fields.

## Restore
Copy the files back to the same paths in the repo, and delete `app/lib/services/native/portal.dart` and `app/test/services/portal_test.dart`.

No secrets are included.
