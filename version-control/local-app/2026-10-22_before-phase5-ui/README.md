# Backup: before the phase 5 UI

Snapshot taken on 2026-10-22, before plan phase 5 (projects, tags and files UI) added the file picker packages.

- `app/pubspec.yaml`, `app/pubspec.lock`: the dependencies after phase 4 (no file picker).
- `app/tool/check-privacy.sh`, `allowed-packages.txt`, `reviewed-hits.txt`: the privacy check before its plugin native-code scan and the new packages.

Phase 5 also adds `app/lib/app/`, `app/lib/services/`, `app/lib/ui/` and new tests, changes `app/lib/main.dart` and `app/lib/vault/`, and the Flutter tool regenerates `app/linux/flutter/generated_plugin*`.

## Restore
1. Copy these files back to the repo root, keeping their paths.
2. Run `flutter pub get` in `app/`.
3. To drop the UI as well, delete the new folders listed above.

No secrets are included.
