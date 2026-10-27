# Before folders in exports and imports (2026-10-26)

Backup of the files changed when folders were added to exports and imports (step 5):

- `app/lib/services/export_service.dart`: nested folders in ZIP/TAR, locked manifest format 2, folder export, ZIP path-length guard.
- `app/lib/services/project_service.dart`: `importFolders`, `importFile(folderId:)`.
- `app/lib/vault/project_index.dart`, `app/test/vault/project_index_test.dart`: `foldersParentsFirst()`.
- `app/lib/ui/export/export_dialog.dart`: exporting one folder (no lock option).
- `app/lib/ui/project/project_screen.dart`: "Export a readable copy…" in the folder menu.
- `app/test/services/export_service_test.dart`: folder cases.

To restore, copy the files back to their paths under the repo root.
