# Backup: before phase 7 (export, import and settings)

Snapshot taken on 2026-10-22, before phase 7 changed these files. Each file keeps its repo path.

- `project-mockups/export.html`, `project-mockups/settings.html`: the mockups as approved in phase 1, before the PM's export rule changed. The rule now has two options: a custom passphrase, or unlocked.

- `app/lib/vault/blob_stream.dart`, `atomic_write.dart`, `errors.dart`, `app/lib/services/project_service.dart`: before step 1 (the export format and archive writers).

- Before step 2 (export and import UI): `app/lib/vault/native/libc.dart`, `app/lib/services/file_picker.dart`, `app/lib/app/app_controller.dart`, `app/lib/ui/home/home_screen.dart`, `app/lib/ui/home/project_dialogs.dart`, `app/tool/allowed-native-libs.txt`, `app/pubspec.yaml`, `app/pubspec.lock`, `app/test/ui/ui_helpers.dart`.
- Before step 5 (readable copy): `app/lib/ui/common.dart` (from the phase 6 commit), `app/lib/ui/preview/preview_screen.dart`, `app/lib/services/export_service.dart`.
- Before step 3 (settings): `app/lib/app/theme.dart`, `app/lib/app/settings_store.dart`, `app/lib/main.dart`, `app/lib/vault/vault.dart`, `app/lib/ui/project/project_screen.dart`.

New files from phase 7 (delete them to go back): `app/lib/vault/export_format.dart`, `app/lib/services/archive/`, `app/lib/services/export_service.dart`, `app/lib/services/storage_move.dart`, `app/lib/app/version.dart`, `app/lib/ui/export/`, `app/lib/ui/settings/`, and their tests.

## Restore
Copy the files back to the same paths in the repo, delete the new files listed above, then run `flutter pub get` and `bash tool/check-privacy.sh` from `app/`.

No secrets are included.
