# Projects, tags and files UI (plan phase 5)

**Date:** 2026-10-22
**Time:** 2026-10-22 14:55–15:24 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Decisions made during this phase
- **File picker:** only `file_selector_linux` (the Flutter team's, BSD-3), not the 6-platform umbrella package. It uses GTK's native dialog, which also works through the desktop's file-dialog portal inside a Flatpak.
- **`http` replaced by an empty stand-in.**
  - The file picker's interface package lists the `http` networking package but never uses it. The privacy check caught this when the package was added.
  - The PM chose to override it with `app/tool/stubs/http/`, which holds no code. With it, `http_parser` and `typed_data` also left the tree.
- **A passphrase of at least 12 characters is required** to create a vault.
- **Projects are sorted by last change,** saved only as part of confirmed changes. Opening a project never writes to disk.
- **Phase 6–7 items are shown greyed out** with "Coming in a later version": Preview, Edit in another app, Export (ZIP/TAR, readable copy, "Export first…"), Import and Settings.

## Change
- **`app/pubspec.yaml`:** `file_selector_linux` and `file_selector_platform_interface`, and the `http` override. `pubspec.lock` was updated.
- **`app/tool/check-privacy.sh`:**
  - Check 5 now also scans plugins' native `linux/` code. Its patterns now include CMake's `FetchContent` / `ExternalProject` downloads.
  - Check 1 accepts only empty stand-ins in `tool/stubs/` as path dependencies.
  - **Latent bug fixed:** check 1 matched versions as regular expressions, so a version like `0.9.4+1` could never match. It's now an exact match.
- **`app/tool/allowed-packages.txt`, `reviewed-hits.txt`:** 5 reviewed packages (`file_selector_linux`, `file_selector_platform_interface`, `cross_file`, `plugin_platform_interface`, `web`) and the stand-in. 14 reviewed hits, each with a reason.
- **`app/lib/vault/`:**
  - `ProjectIndex.changedAt` and `totalSize`, and `FileEntry.originalPath` (encrypted with the rest of the index).
  - `UnlockedVault.deleteProject`, `writeBlob` / `readBlob` / `deleteBlob`, and `writeCover` / `readCover` / `deleteCover`.
- **`app/lib/app/`:** `AppController` (setup → locked → unlocked, and lock wipes the key), the unlock delay (1, 2, 4… up to 30 s, in memory), `SettingsStore` (only the storage location, in `~/.config/portfolio_jockey/settings.json`, written only when "Create vault" is confirmed), passphrase rules, and the theme from the mockup palette.
- **`app/lib/services/`:** `ProjectService` (every disk operation the screens make) and `FilePicker`.
- **`app/lib/ui/`:**
  - First run, unlock, home and the project "…" menu.
  - New project, rename, cover and description, and delete project (you type the name).
  - The project view, with tag filters and multi-select.
  - Add files (confirm, then progress, then failures), the file menu, rename file, and the three delete dialogs.
  - "Original missing" greying, manage tags with its review, and edit tags (one or several files).
- **`.gitignore`:** `/app/tool/stubs/*/pubspec.lock`, which pub generates.

## Differences from the mockups (deliberate)
- **File cards** show a type badge instead of image thumbnails or video lengths, because thumbnails would mean decrypting every file just to show the grid. They can come with preview (phase 6).
- **Phone layouts** wait for the Android port. Desktop windows reflow at any width.
- **Cards** say "Changed today" rather than "Opened today" (see sorting above).
- **Special characters in labels** (✓, →, ＋, emoji) are drawn as Material icons instead, because not every Linux font has them. The first test renders showed missing-glyph boxes.

## Verification
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- **`flutter test`: 82 tests pass,** plus 4 screenshot tests that run only on request.
  - **Unit:** `ProjectService` against a real vault: projects, covers, adding files (with progress and a mid-batch failure), each of the three deletes and the original-missing case, tag spelling, batch tag changes that never delete files, passphrase rules, the unlock delay and formatting.
  - **Widgets,** with the real app, a real vault and a fake file picker:
    - Create vault stays disabled until all three conditions are met.
    - Lock, a wrong passphrase with its delay, then unlock.
    - **Cancel writes nothing**: the folder contents are compared before and after for rename, new project, delete project, add files and manage tags.
    - Delete project needs the exact name.
    - Adding files works.
    - Delete-from-device and delete-from-both are greyed when the original is gone.
    - The tag review lists exactly the pending changes.
- **Screenshots:** all 18 screens were rendered in light and dark with the bundled Roboto and Material icon fonts, then compared with the mockups. They're in the session's temporary folder and aren't committed.
  - **Renderer artifact:** menus and dialogs show a hard outline where the desktop draws a soft shadow.
- `flutter build linux --debug` compiles, with the plugin linked.
- **`check-privacy.sh` passes.** On throwaway copies it failed as intended for:
  - curl added to the plugin's C++
  - code or a dependency added to the `http` stand-in
  - a path dependency outside `tool/stubs/`
  - `FetchContent` in the app's Linux build
- `check-lockdown.sh` passes. No servers, ports or temporary folders were left behind.

## Not verifiable here
- **The real GTK file dialog.** The container has no display, so the picker is exercised through a fake in tests, and the plugin's code was reviewed instead.
- **Delete from device inside a Flatpak:** a file chosen through the portal comes back as a document-portal path. Whether deleting through that path removes the original must be tested when packaging (phase 8).

## Impacts
- **The app is usable end to end** for projects, files and tags.
- **Phase 6** adds preview and "Edit in another app" to the greyed menu items. Decrypting a stream must discard everything if the stream ends in an error (see the "Known limits" in `docs/dependencies.md`).
- **Backup:** `version-control/local-app/edit005-2026-10-22_before-phase5-ui/` holds the previous `pubspec.yaml`, `pubspec.lock` and privacy-check files.
