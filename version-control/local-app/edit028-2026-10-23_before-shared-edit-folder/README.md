# Backup: before edit copies moved to the shared Flatpak memory folder

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/lib/services/private_folder.dart`, `app/lib/app/edit_session.dart`, `app/lib/app/app_controller.dart`, `app/lib/ui/preview/edit_dialogs.dart`, `app/lib/services/native/gio_apps.dart`, `project-mockups/preview.html`: before `PrivateFolders.forEditing`, the risk notice and the launcher check.

## Restore
Copy the files back to the same paths in the repo, and delete `app/test/services/private_folder_edit_test.dart`.

No secrets are included.
