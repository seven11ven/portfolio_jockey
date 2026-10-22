# Phase 6: preview and "Edit in another app"

**Date:** 2026-10-22
**Performed by:** Claude Code
**Decided by:** project manager

## Step 0: stop VS Code from flagging the backups
**Time:** 2026-10-22 16:14 UTC

- **Why:** VS Code showed 794 "Problems". They all came from the backed-up `.dart` files in `version-control/local-app/2026-10-22_before-trash/`. Outside `app/`, their imports can't be resolved. The app itself had no problems, and `flutter analyze` was clean.
- **Change:** `"dart.analysisExcludedFolders": ["version-control"]` in `.devcontainer/devcontainer.json`, next to the other Dart settings, with a comment. The same setting was added to this container's VS Code machine settings, which are untracked.
- **Verification:**
  - After a window reload, the Problems panel was empty.
  - `app/` is still analysed: a temporary lint probe was flagged, then deleted.
- **Backup:** `version-control/local-app/2026-10-22_before-analysis-exclude/`.
- **Impact:** editor only. The app, its tests and `flutter analyze` are unchanged.

## Step 1: research and decision point 1
**Time:** 2026-10-22, before 17:00 UTC

The options for audio/video, PDF and Markdown were researched and reported. The PM chose:
- **Audio and video:** media_kit + the system libmpv, with its network features switched off.
- **PDF:** our own FFI bindings to poppler-glib, rendered in memory.
- **Markdown:** flutter_markdown_plus, always with our own image builder, so it never loads images from the network or disk.

The research came from reading the packages' code. It is checked again in the code before each package is added (step 3).

### Research claims checked in the code
**Time:** 2026-10-22 18:00–18:20 UTC

- **media_kit 1.2.6** (`lib/src/player/native/player/real.dart`):
  - **On-disk cache:** it sets `cache-on-disk=yes` on every platform. We must set it to `no` ourselves after the player starts.
  - **Network protocols:** the default whitelist includes `http`, `https`, `tcp`, `udp`, `tls`, `rtp` and `crypto`. We pass `protocolWhitelist: ['file']`.
  - **Settings applied before start-up:** only `vid`, so `load-scripts` can't be switched off from our code.
  - **`Media.memory()`** writes a temporary file to `Directory.systemTemp`. It must never be used.
  - **`setProperty`** on the native player is public, so our settings can be applied after start-up.
- **mpv 0.35.1 source** (Debian 12's version; `etc/builtin.conf`, `options/path.c`, `player/scripting.c`, `demux/cache.c`):
  - **No user config or scripts:** libmpv's built-in profile sets `config=no`. That leaves the config folder empty, so nothing in the user's `~/.config/mpv` is loaded.
  - **The `ytdl` script:** the built-in scripts still load. The ytdl downloader script follows the `ytdl` option, and setting it to `no` at runtime unloads it.
  - **On-disk cache:** it fails without a `cache-dir` in 0.35. Newer mpv versions may set that folder by default, so we set `cache-on-disk=no` explicitly.
- **media_kit_video 2.0.1:**
  - **Wakelock:** only used when the `Video` widget's `wakelock` flag is on. We pass `false`.
  - **`wakelock_plus`:** still a required package, so it goes through the full review.
  - **Native build:** compiled only when `MEDIA_KIT_LIBS_AVAILABLE` is set, and it links the system `mpv` and `epoxy` through pkg-config.
- **media_kit_libs_linux 1.2.1:** its CMake **downloads mimalloc from GitHub** at build time (`file(DOWNLOAD …)`, MD5 only). Plan: don't depend on it, and set `MEDIA_KIT_LIBS_AVAILABLE` in our own `linux/CMakeLists.txt`.
- **flutter_markdown_plus 1.0.12:**
  - **Dependencies:** only flutter, markdown, meta and path.
  - **Images:** when `imageBuilder` is set, it is always used. Only without it does `kDefaultImageBuilder` call `Image.network` / `Image.file` / `Image.asset`.
  - **Links:** without `onTapLink`, a tapped link does nothing.

## Step 2: mockup additions and decision point 2
**Time:** 2026-10-22, before 17:58 UTC

- **`project-mockups/preview.html`:** added scenes 6–12:
  - 6: PDF preview
  - 7: Markdown preview
  - 8: "Edit in…" inside a Flatpak, which uses the desktop's app chooser
  - 9: "Discard your changes?" confirmation
  - 10: lock while editing
  - 11: an unfinished edit found at unlock
  - 12: refusal when there's no private memory-only folder
- **Scene 1's note** now says audio and video play in the app via media_kit + libmpv.
- **Approved** by the PM on 2026-10-22.
- **Impact:** mockup only. No application code changed.

## Step 3a: backups and system libraries
**Time:** 2026-10-22 18:25–18:35 UTC

- **Backup:** `version-control/local-app/2026-10-22_before-phase6/` holds 20 files that phase 6 changes, each at its repo path, with a README on how to restore. They include `setup.sh`, the pubspec files, the Linux CMake and plugin files, the privacy-check lists and script, `main.dart`, the controller, `ProjectService`, the screens that get the banner or menu items, `libc.dart` and `vault.dart`.
- **`.devcontainer/setup.sh`:** now also installs the following from Debian 12:
  - `libmpv-dev` (mpv 0.35.1) and `libepoxy-dev` (1.5.10), which media_kit's video player builds against
  - `libpoppler-glib8` (22.12.0), for PDF previews
  - They were installed in this container too. None of them has telemetry.
- **Linked network-capable libraries:** found with `ldd`. Neither library uses them unless asked to.
  - **Poppler links NSS** (`libnss3`, `libsmime3`), which it uses only for checking signed PDFs. Our bindings will not include any signature functions, so that code is never called.
  - **libmpv links** gnutls, OpenSSL, libssh, SRT, libbluray, libcdio and libarchive through FFmpeg. They're kept unreachable because:
    - we only ever open plain file paths
    - FFmpeg's protocol whitelist is set to `file`
    - inside the Flatpak (phase 8), the app gets no network permission
- **Impact:** a bigger dev container. Phase 8 must decide whether the Flatpak bundles mpv and Poppler or takes them from its runtime. This is noted in `public-notes/phase8-packaging.md` in step 4.

## Step 3b: preview packages added and reviewed
**Time:** 2026-10-22 18:35–19:05 UTC

- **`app/pubspec.yaml`:** added `flutter_markdown_plus 1.0.12`, `media_kit 1.2.6` and `media_kit_video 2.0.1`. That brings in 27 new packages in total, all listed in `app/tool/allowed-packages.txt` with their licence and what they do. The licences are MIT, BSD-3-Clause and MPL-2.0 (`dbus`), all compatible with AGPL-3.0. `path` is now used by the app itself, not only by the tests.
- **Code review**, done by reading each package's `lib/` code plus media_kit_video's C++ code. It looked for file, process, socket, HTTP and native-library code:
  - **`markdown`, `args`:** pure Dart, no I/O.
  - **media_kit `Player.open()`:** always writes a temporary playlist file containing the media's path to `Directory.systemTemp` (`/tmp`). It's deleted 5 s later, or never if the app crashes. **Rule:** load media with `NativePlayer.command(['loadfile', path])` instead. Subtitle data tracks also write temporary files, so they're never used.
  - **media_kit's libmpv lookup:** the `LIBMPV_LIBRARY_PATH` environment variable can point it at another library. **Rule:** pass `libmpv: 'libmpv.so.2'` explicitly.
  - **`wakelock_plus` → `dbus`:** `dbus` can reach a TCP address taken from `DBUS_SESSION_BUS_ADDRESS`, but it only connects when a call is made. **Rule:** `wakelock: false`, and a no-op wakelock is registered at start-up as a second guard.
  - **`package_info_plus`:** runs `stat` as a separate process, but only when wakelock_plus asks for the app name. That's never reached.
  - **`image`, `archive`:** only used by media_kit's `screenshot()`, which we never call. Their file APIs only run when called.
  - **`win32`, `ffi_leak_tracker`:** Windows-only.
  - **media_kit_video's C++ code (1,133 lines):** no network, process, `getenv` or file code. It only uses mpv's render API, plus `video-sync=audio`.
- **`app/tool/reviewed-hits.txt`:** 12 new hits recorded, each with its reason:
  - 4 `dbus` socket hits, which need a call that never happens
  - web-only code in media_kit, package_info_plus and flutter_markdown_plus
  - name matches: the WebP `amplitude` field, the Win32 `TELEMETRY` IOCTL constants, and a `dart:html` error string
  - flutter_markdown_plus's default image loader, which our `imageBuilder` always replaces
- **`app/linux/CMakeLists.txt`:** sets `MEDIA_KIT_LIBS_AVAILABLE`, so media_kit_video compiles against the system libmpv. **`media_kit_libs_linux` is not used:** its CMake downloads mimalloc from GitHub at build time, checked only by MD5.
- **Verification:**
  - `flutter build linux --debug` builds.
  - The plugin links `/lib/x86_64-linux-gnu/libmpv.so.2` and `libepoxy.so.0`, with no mimalloc.
  - `check-privacy.sh` passes.
  - `flutter analyze` is clean.
  - 85 tests pass.

## Step 3c: the build
**Time:** 2026-10-22 19:05–21:10 UTC

### New files
- **`app/lib/services/native/poppler.dart`:** PDF previews.
  - A worker isolate opens the PDF from memory with `g_bytes_new_static`, a copy we own and wipe with `sodium_memzero` on close.
  - Pages are rendered through cairo, capped at 4096 px per side.
  - Password-protected PDFs get their own message.
- **`app/lib/services/native/gio_apps.dart`:** "Open with".
  - Apps for a file type are found by its name only, and the chosen app is launched with GLib's app-info functions.
  - Inside a Flatpak, `g_app_info_launch_default_for_uri` goes through the OpenURI portal.
  - Checked in GLib 2.74.6's source (`gio/gappinfo.c`, `gio/gdesktopappinfo.c`): GIO sends a local "Launched" signal on the session D-Bus, containing the app ID, its process ID and the file's path.
- **`app/lib/services/private_folder.dart`:** the memory-only folders.
  - Each is `$XDG_RUNTIME_DIR/portfolio_jockey/<edit|view>-<random>`, created with mode 0700 by libc `mkdir`.
  - It's refused unless the session folder is set, private (no group or other permissions), not a link, and on tmpfs or ramfs according to `/proc/self/mountinfo`.
  - `wipe` overwrites every file with zeros, then deletes it, never following links.
- **`app/lib/app/edit_session.dart`:** one edit at a time.
  - Each edit keeps a `session.json` next to the copy in `file/`.
  - Save re-encrypts the copy with the file's key, atomically. Discard wipes it.
  - Leftover edits are found after unlocking. Media copies are wiped when a preview closes, at lock and at unlock.
- **`app/lib/ui/preview/`:** the preview screen, its content views and the edit dialogs and banner (mockup scenes 1–12).
  - Images, text, Markdown and PDF are decrypted fully into memory before showing, with limits of 200 MB, 5 MB, 5 MB and 200 MB.
  - Bytes are zeroed and images evicted from the cache when they close.
  - Audio and video play through media_kit from a memory-only copy:
    - loaded with mpv's `loadfile`
    - libmpv pinned to `libmpv.so.2`
    - a no-op wakelock
    - the lockdown options `cache-on-disk`, `ytdl`, `access-references`, `load-unsafe-playlists`, `stream-lavf-o` (file only), `sub-auto`, `cover-art-auto` and `save-position-on-quit`

### Changed files
- **`libc.dart`:** `mkdir`.
- **`project_index.dart`:** a file's `size` can change after an edit.
- **`ProjectService`:** `readFile`, `decryptTo`, `differsFrom`, `replaceContent` and `TooLargeToPreview`.
- **`AppController`:** `edits` and `canLock`. `lock()` refuses while editing.
- **`common.dart`:** `formatDate`, `formatAgo` and `formatDuration`.
- **Project screen:**
  - Preview and "Edit in another app…" are enabled.
  - Double-click opens a preview.
  - It has the banner.
- **Home screen:**
  - It has the banner.
  - Lock asks first while a file is being edited.
  - It shows the unfinished-edit dialog.
- **`pubspec.yaml`:** `wakelock_plus_platform_interface` is now a direct dependency, for the no-op wakelock.
- **Native allowlist:** Poppler/cairo (20 functions), GIO app-info (14 functions) and libc `mkdir`.

### Bug fixed (from phase 5)
Pressing Lock while the home or project screen was still reading from the vault made that read fail with an uncaught error. Both screens now stop quietly when the vault was locked meanwhile.

### Verification
- **`flutter analyze`:** clean.
- **`flutter test`:** 120 pass (6 screenshot and real-Trash tests skipped). The new tests cover:
  - **Poppler:** 4 tests, including rendering real pixels.
  - **Private folders:** 10 tests, including the refusals and not following links.
  - **Edit sessions and preview reads:** 12 tests, including a damaged file, crash recovery, and same-length change detection.
  - **Widget tests:** 8. They check that no `Image` widget is built for Markdown images, and that Cancel writes nothing.
  - **libmpv:** a test against the real library confirms it accepts every lockdown option, that `config` is `no`, and that a local WAV loaded with `loadfile` plays.
- **Negative checks:** a throwaway binding of `poppler_document_new_from_file` or `g_socket_client_new` fails `check-privacy.sh`.
- **`flutter build linux --debug`** builds.
- **Screenshots** of scenes 1 and 3–12, in light and dark, were shared with the PM as a private page. Video can't be drawn by the headless renderer.

## Step 4: docs and final checks
**Time:** 2026-10-22 21:25–21:50 UTC

- **The PM reviewed the screenshots** and approved them ("the screens look fine").
- **`docs/dependencies.md`:**
  - **Direct dependencies:** the list of the app's own direct dependencies is updated.
  - **New table, "Previews (plan phase 6)":** all 27 packages, plus why `media_kit_libs_linux` isn't used.
  - **Native libraries table:** new rows for GIO app info, Poppler and cairo, and libmpv and epoxy. The libc row now includes `mkdir`.
  - **Licences:** read from Debian's copyright files.
    - Poppler: "GPL-2 or GPL-3".
    - mpv: LGPL-2.1+ with some GPL-2+ parts.
    - cairo: LGPL-2.1 or MPL-1.1.
    - All are compatible with AGPL-3.0.
  - **New section, "Readable copies":** the memory-only folder rules, the mpv options, and the known limits (swap, the other app's own copies, unwipeable Dart strings, the tmpfs size, and GIO's local "Launched" signal).
  - **The privacy check's list of negative tests** now includes the phase 6 ones.
- **`public-notes/phase8-packaging.md`:** a new decided rule (readable copies only in memory) and new tests 7–10:
  - `$XDG_RUNTIME_DIR` inside the sandbox
  - OpenURI write access and safe-save
  - whether to bundle or reuse libmpv and Poppler
  - audio and GPU access
- **`CLAUDE.md`:** phases 0–6 are done and phase 7 is next. Added the layout of `ui/preview/`, the readable-copy rule, the media_kit and Markdown rules, and the new `setup.sh` packages. `AGENTS.md`, `.github/copilot-instructions.md` and `.cursorrules` don't mirror the project state, so they need no change.
- **`app/pubspec.yaml`:** comments on the new packages.
- **Final checks:**
  - telemetry lockdown: passed
  - `flutter pub get`, then `check-privacy.sh`: passed
  - `flutter analyze`: clean
  - `flutter test`: 120 passed, 10 skipped (4 new screenshot tests, which run only on request, plus the earlier 6)
  - `flutter build linux --debug`: built
  - secret and personal-data scan of every change: clean
  - **No new ports.** The only local listeners are VS Code's own processes and the Dart extension's tooling daemon (127.0.0.1).
- **Not committed:** waiting for the PM.
