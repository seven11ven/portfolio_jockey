# Backup: before playing audio and video in the desktop's own player

Snapshot taken on 2026-10-23, before media_kit and libmpv were removed. Each file keeps its repo path.

Includes the app code (edit session, controller, settings, launcher, portal, preview screen and views, `shared_player.dart`), `pubspec.yaml`/`pubspec.lock`, the three privacy allowlists, `linux/CMakeLists.txt`, the runner, the Flatpak manifest, `.devcontainer/setup.sh`, the preview and settings mockups, and the tests that change or are removed.

## Restore
Copy the files back to the same paths, run `bash .devcontainer/setup.sh` (it reinstalls libmpv-dev and libepoxy-dev), then `flutter pub get` and `bash app/tool/check-privacy.sh`.

No secrets are included.
