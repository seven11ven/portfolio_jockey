# Backup: before the shared media player

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/lib/ui/preview/preview_views.dart`: before `MediaPreview` used `SharedPlayer` (it disposed its own player after `stopVideoOutput`, which still froze the app).
- `app/lib/ui/preview/preview_screen.dart`, `app/lib/app/app_controller.dart`: saved as planned; unchanged in the end.
- `app/test/ui/media_release_test.dart`: the removed `stopVideoOutput` tests.

## Restore
Copy the files back to the same paths in the repo, and delete `app/lib/ui/preview/shared_player.dart` and `app/test/ui/shared_player_test.dart`.

No secrets are included.
