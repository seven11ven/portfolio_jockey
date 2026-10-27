# Backup: before "Delete from device" became "Move to Trash"

Snapshot taken on 2026-10-22, before the original file was moved to the Trash instead of being permanently deleted (project manager's decision, so the app works the same inside a Flatpak).

- `app/lib/services/project_service.dart`: `deleteOriginal` permanently deleted the original.
- `app/lib/ui/project/file_dialogs.dart`, `project_screen.dart`: the "Delete from device" / "Delete everywhere" wording.
- `app/lib/app/app_controller.dart`: before the Trash dependency was passed in.
- `app/tool/allowed-native-libs.txt`: before GLib's GIO was allowed.
- `app/test/...`: the tests for the old behaviour.
- `project-mockups/project.html`: the approved mockup with the old wording.

Phase 5 isn't committed yet, so git can't restore these files.

## Restore
1. Copy these files back to the repo root, keeping their paths.
2. Delete `app/lib/services/native/gio_trash.dart` and `app/test/services/gio_trash_test.dart`.

No secrets are included.
