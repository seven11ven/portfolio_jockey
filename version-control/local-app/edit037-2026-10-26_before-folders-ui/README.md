# Before the folders UI (2026-10-26)

Backup of the files changed when folders were added to the project screen (step 4):

- `app/lib/ui/project/project_screen.dart`: navigation, breadcrumb, toolbar, grid and list views, sorting, search, drag and drop.
- `app/lib/ui/project/file_dialogs.dart`: "Add files" shows and uses the current folder.
- `app/lib/app/app_controller.dart`: session-wide sort and view preferences.
- `app/lib/vault/project_index.dart`, `app/test/vault/project_index_test.dart`: `allFolderStats()`.

Also backed up, as committed: `app/test/ui/preview_test.dart` (previous/next now follow the displayed order) and `app/test/screenshots/screenshots_test.dart` (folder scenes added).

New files (delete them to restore): `app/lib/ui/project/explorer.dart`, `app/lib/ui/project/folder_dialogs.dart`, and the new widget test `app/test/ui/folders_test.dart`.

To restore, copy the files back to their paths under the repo root.
