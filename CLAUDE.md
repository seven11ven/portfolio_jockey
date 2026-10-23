# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Before doing anything in this repository, read and follow all project guidelines. They are imported below so every Claude session loads them automatically.

@project-guidelines/implementation.md
@project-guidelines/security.md

## Key reminders
- Never edit without explicit user permission; plan changes first (plan mode).
- Ask the user/project manager when uncertain.
- Log every change in `project-changelog/YYYY-MM-DD/<change>.md` with details, impacts and the time it was done (`**Time:** YYYY-MM-DD HH:MM UTC`) (untracked/.gitignored components are exempt).
- Back up prior versions of changed application components to `version-control/` (docs exempt). Never back up anything holding or exposing API keys, webhooks or secrets, such as `.env`. Hard-coded or plain-text secrets must never exist at all.
- New env variables go in `/.env_example` with EMPTY values and annotations on purpose and setup. Never put real values in annotations.
- Floor Planning: show UI mockups before building or changing any UI. Agreed format is static HTML with fake data in `/project-mockups/`.
- Budgeting: never choose a service or dependency that requires upfront card details or payment, unless the project manager explicitly says otherwise. Prefer secure, cost-efficient options. Always confirm on the provider's own pricing/plan pages, read in their entirety. Never decide from a first glance or a summary. Keep token usage low, but never at the cost of these rules.
- Open Source and Privacy: check every tool, dependency and service for telemetry, and pick options that respect users' privacy while staying secure. Examine the code of every third-party package or resource for telemetry or tracking. Never take it at face value.
- Clean up loose ends: close ports, dev servers, and other connections as soon as they're no longer needed.
- All code, whether written, borrowed or reused, must meet OWASP and OSINT security standards. Check dependencies for vulnerabilities, and give keys and webhooks least privilege.
- Double check before every commit: review staged changes for keys, secrets, private mentions, and critical infrastructure. Commits to this public repo can't be taken back.
- This repo is PUBLIC: never print or commit secrets, keys, or PII. Keep the single root `/.gitignore` updated; no nested `.gitignore` files.
- When guidelines change, sync `AGENTS.md`, `.github/copilot-instructions.md` and `.cursorrules`. `GEMINI.md` imports the guidelines directly.

## Project state
Portfolio Jockey v2 is a fully local, offline, encrypted project tracker built with Flutter for **Linux desktop**.
- The Flutter app lives in `app/`, with app ID `io.github.seven11ven.portfolio_jockey`. Plan phases 0–7 (guidelines, mockups, toolchain, scaffold, vault core, projects/tags/files UI, preview and "Edit in another app", export/import/settings) are done, and phase 8 (Flatpak packaging) is next.
- The vault core is in `app/lib/vault/`: libsodium through our own `dart:ffi` bindings (`vault/native/`), Argon2id MODERATE, an XChaCha20-Poly1305 index and secretstream files. Its file formats and known limits are in `docs/dependencies.md` ("Vault format"). It never asks for confirmation itself: the UI shows the confirm/cancel step before calling anything that writes.
- App layout under `app/lib/`:
  - `app/`: controller, settings and theme
  - `services/`: `ProjectService`, which holds every disk operation the screens make, and the file picker
  - `ui/`: the screens and dialogs built to `project-mockups/`
  - `ui/preview/`: the preview screen, its content views, and the edit dialogs and banner. `app/edit_session.dart` holds the one active edit.
  - `ui/export/` (export and import dialogs) and `ui/settings/` (settings, storage move, change passphrase). `services/export_service.dart` and `services/archive/` (our own streaming ZIP/TAR writers and the strict tar reader) do the work; `vault/export_format.dart` is the locked `.pjx` format.
  - Every menu item is built; the phase 3–6 "Coming in a later version" placeholder was removed in phase 7. "Export a readable copy…" of one file is `ui/export/readable_copy_dialog.dart` (no lock option, PM decision).
- **Readable copies** (audio/video and "Edit in another app"; also inside the Flatpak, PM decision 2026-10-23: never the shared `app/<id>` folder) go only in `services/private_folder.dart`'s memory-only folder: `$XDG_RUNTIME_DIR/portfolio_jockey/`, mode 0700, on tmpfs. If that isn't available the app refuses; it never falls back to a disk folder. Images, text, Markdown and PDF are decrypted into memory only. Details and known limits are in `docs/dependencies.md` ("Readable copies").
- **media_kit rules** (see `docs/dependencies.md`):
  - Load media with `NativePlayer.command(['loadfile', path])`. Never use `Player.open()`, `Media.memory()` or subtitle data tracks: they write temporary files to `/tmp`.
  - Always apply `lockedDownMpvOptions`, and call `ensureMediaReady()` first.
  - Never add `media_kit_libs_linux`: its build downloads mimalloc.
  - Keep `setlocale(LC_NUMERIC, "C")` in `app/linux/runner/my_application.cc` (after GTK's startup). libmpv refuses to start otherwise, and `media_kit_libs_linux` would normally do it. `test/linux_runner_test.dart` checks it.
  - Inside the Flatpak, open files and folders for other apps only through `services/native/portal.dart` (the OpenURI portal, synchronous, with `ask`/`writable`). GLib's `g_app_info_launch_default_for_uri` silently does nothing from a worker isolate there.
  - Play audio and video only through `SharedPlayer` (`ui/preview/shared_player.dart`), and never dispose a player or VideoController: media_kit_video's CPU (S/W) path frees its frame buffer on dispose while Flutter may still be reading it, which froze the app. Previews open paused (PM decision).
- **Markdown:** always pass an `imageBuilder` to flutter_markdown_plus. Without one, it loads images from the network or disk.
- **Exports** (PM decision, 2026-10-22): exactly two options, everywhere. Either a **custom passphrase** (a checkbox; it must be filled in and confirmed before Export is enabled; no strength rules), making a Portfolio Jockey-only `.pjx`, or **unlocked** ZIP/TAR. The vault passphrase is never used for exports. Files stream chunk by chunk into the archive: never buffer a whole file or write a readable temp copy. Imports get new file keys and are all or nothing.
- "Delete from device" **moves the original to the Trash** (GLib's `g_file_trash`, through the Trash portal inside a Flatpak). The encrypted project copy is still deleted permanently. This was the PM's decision on 2026-10-22.
- Phase 8 (Flatpak) to-dos and open questions go in `public-notes/phase8-packaging.md`. Add to it whenever a later phase finds something.
- Supported Linux systems are listed in `public-notes/linux-support.md` (any 64-bit desktop with Flatpak; x64 now, arm64 to be decided in phase 8).
- The approved plan, including the encryption and storage design and the phase list, is `project-changelog/2026-10-22/local-app/plan.md`.
- The Android port is on hold because the Android SDK license was declined (`public-notes/android-port.md`). Don't add Android platform code or install the Android SDK.

## Toolchain
- `bash .devcontainer/check-lockdown.sh`: checks every telemetry layer. It must pass before running `flutter` or `dart`.
- `bash .devcontainer/setup.sh`: installs or repairs the pinned Flutter 3.47.7 and its telemetry patch. It also installs `libsodium23` (the vault), `libmpv-dev` and `libepoxy-dev` (audio/video), and `libpoppler-glib8` (PDF), which the app and its tests need. Safe to re-run.
- To upgrade Flutter, edit `FLUTTER_VERSION` and `FLUTTER_SHA256` in `setup.sh` and confirm the patch still applies. Never run `flutter upgrade` or `flutter channel`: they overwrite the patched source.
- Run these from `app/`:
  - Lint: `flutter analyze --fatal-infos --fatal-warnings`
  - Test: `flutter test`, or `flutter test test/vault/vault_test.dart` for a single file. The widget tests (`test/ui/`) run the real app against a real vault in temporary folders, with a fake file picker. Real file and crypto work needs `settle()` / `settleUntil()` from `test/ui/ui_helpers.dart`.
  - Screenshots for review: `SCREENSHOT_DIR=<folder> flutter test test/screenshots`. This renders every screen to PNG in light and dark. Never commit the PNGs. The vault tests use libsodium's smallest Argon2id settings (`fastKdf` in `test/vault/test_helpers.dart`); one test checks the real MODERATE default.
  - Build: `flutter build linux --debug`. The container has no display, so the app can be built but not launched.
- `bash app/tool/check-privacy.sh`:
  - It must pass after every `flutter pub get` and before every commit.
  - It fails on any package that isn't in `app/tool/allowed-packages.txt` at its exact version, on known network and analytics packages, and on network APIs in `app/lib`, `app/test` or `app/linux`.
  - It also scans every dependency's code. Each hit must be listed in `app/tool/reviewed-hits.txt` for that exact version.
  - Native code: only files in `app/tool/allowed-native-libs.txt` may open native libraries, using plain-string names and only the listed functions.
  - `--list-hits` prints the current hits for a review. Read the code before adding any of them.

## Constraints that shape the code
- The app must never use the network. No analytics, crash-reporting or networking packages, and no local HTTP servers, which rules out the usual workaround for streaming media.
- Every new or upgraded package needs a license, cost and telemetry check and a code review, recorded in `docs/dependencies.md`, `app/tool/allowed-packages.txt` and `app/tool/reviewed-hits.txt`. The same goes for a new native library or libc function (`app/tool/allowed-native-libs.txt`).
- Text in the UI must not rely on special characters that fonts may lack (✓ → ＋ emoji): use Material icons (`ChangeArrow`, `TagChip(icon:, check:)`).
- `http` is replaced by the empty stand-in `app/tool/stubs/http/`, because the file picker lists it but never uses it. Never put code there.
- Keys and the passphrase stay in `SecureBuffer` (libsodium's guarded memory), never in Dart lists or strings that outlive their use.
- The app's tests must not turn on leak_tracker's retaining-path collection. It starts the Dart VM's local debug server, and `check-privacy.sh` blocks it.
- Every action that writes to disk shows a confirm/cancel step, as the project brief requires.
- Crash safety (docs/dependencies.md, "Crash and power-cut safety"): write a new version under a new ID, save the index, then delete the old one; list multi-step work (exports, imports, moves, edits) in the vault journal before it starts, and remove the entry when it ends. Never delete anything an index refers to.

## Repo conventions
- Changelogs and backups for the local app go in `local-app/` subfolders: `project-changelog/YYYY-MM-DD/local-app/` and `version-control/local-app/<date>_before-<change>/`, each with a README explaining how to restore. Cloud-era history is under `cloud-service-abandoned/` (in `project-changelog/2026-10-22/`, `version-control/` and `project-mockups/`).
- `public-notes/` is tracked and public. It holds the project brief (`prompts/application.md`) and command notes (`commands/`). `project-notes/` is git-ignored and holds the project manager's private notes and the session handoff.
- Mockups: on each page, `mockup.js` clones every `.scene > .screen` into a desktop window and a phone frame. The phone layout comes from container queries in `styles.css`.
