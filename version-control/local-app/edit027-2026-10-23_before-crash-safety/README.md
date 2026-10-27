# Backup: before the crash and power-cut safety work

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/lib/vault/`: `vault.dart`, `project_index.dart`, `layout.dart`, `atomic_write.dart`, `export_format.dart`, `native/libc.dart`, before blob and cover IDs, the journal, `onTemp` and the fsync check.
- `app/lib/services/`: `project_service.dart`, `export_service.dart`, `storage_move.dart`, before the journal entries, the recovery and the clean-up.
- `app/lib/app/`: `edit_session.dart`, `app_controller.dart`, `settings_store.dart` (unchanged in the end), before session.json was written last and before the recovery at unlock.
- `app/lib/ui/home/home_screen.dart`: before it showed recovery messages after unlocking.

## Restore
Copy the files back to the same paths in the repo, and delete `app/lib/vault/journal.dart`, `app/test/services/crash_safety_test.dart` and `app/test/services/storage_move_test.dart`. Vaults written by the new code keep working with the old code only if no file was edited and no cover was replaced since (the old code ignores `blobId`/`coverId`).

No secrets are included.
