# Backup: before the video close fix

Snapshot taken on 2026-10-23. Each file keeps its repo path.

- `app/lib/ui/preview/preview_views.dart`: before the media preview closed mpv's video output (and waited for it) before disposing the player. Without that, closing a playing video froze the app in media_kit's CPU fallback.

## Restore
Copy the file back to the same path in the repo.

No secrets are included.
