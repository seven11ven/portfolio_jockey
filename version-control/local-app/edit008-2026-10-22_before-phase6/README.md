# Backup: before phase 6 (preview and "Edit in another app")

Snapshot taken on 2026-10-22, before phase 6 step 3 added the preview screen, the edit session, media_kit, flutter_markdown_plus, our Poppler bindings and the new system libraries.

Every file keeps its repo path (for example `app/lib/main.dart`).

## Restore
1. Copy the files back to the same paths in the repo.
2. Delete the files phase 6 added (listed in `project-changelog/2026-10-22/local-app/phase6-preview-edit.md`), such as `app/lib/ui/preview/`.
3. From `app/`: `flutter pub get`, then `bash tool/check-privacy.sh`.

No secrets are included.
