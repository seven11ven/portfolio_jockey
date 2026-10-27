# Backup: before showing the original's real location (phase 8)

Snapshot taken on 2026-10-22, before the app learned to read the document portal's `user.document-portal.host-path` attribute and show it as the original's location. Each file keeps its repo path.

- `app/lib/vault/native/libc.dart`, `app/tool/allowed-native-libs.txt`: before `getxattr` was added.
- `app/lib/vault/project_index.dart`: before the `originalShownPath` field.
- `app/lib/services/project_service.dart`: before `addFiles` stored it.
- `app/lib/app/app_controller.dart`: before it passed a host-path lookup to `ProjectService` (tests use a fake).
- `app/lib/ui/preview/preview_screen.dart`, `app/lib/ui/project/file_dialogs.dart`, `app/lib/ui/project/project_screen.dart`: before they showed it.

## Restore
Copy the files back to the same paths in the repo. Indexes written with the new field still load in the old code, which ignores unknown fields.

No secrets are included.
