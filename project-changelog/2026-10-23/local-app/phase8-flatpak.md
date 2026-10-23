# Phase 8 (Linux Flatpak packaging), continued

The earlier phase 8 entries are in `project-changelog/2026-10-22/local-app/phase8-flatpak.md`.

## Settings license text, and the old backups' .gitignore files
**Time:** 2026-10-23 11:42–11:44 UTC

- **PM decision:** Settings shows the license as "AGPL-3.0-or-later · Show licenses", matching the metainfo and the README.
  - Changed one line in `app/lib/ui/settings/settings_screen.dart`. No layout change, so no mockup; the mockups don't show the license line.
  - Backup: `version-control/local-app/2026-10-23_before-license-text/`.
  - `flutter analyze` is clean, and the settings tests pass.
- **PM decision:** renamed the nested `.gitignore` copies in two older backups to `root.gitignore`, as done for the step 3 backup. The project keeps a single root `.gitignore`, and Git would otherwise apply those copies as rules inside their folders.
  - The folders are `version-control/local-app/2026-10-22_before-flutter-toolchain/` and `version-control/local-app/2026-10-22_before-scaffold/`.
  - Their README restore steps now say to copy `root.gitignore` back as `/.gitignore`.
  - No tracked nested `.gitignore` files remain.
- **Impact:** one visible text change in Settings. The backups' contents are unchanged.

## Step 5: install guide, and the kit rebuilt
**Time:** 2026-10-23 11:44–11:49 UTC (it started after commit `5d2e6c4`)

- **New: `docs/install.md`.** Written for people installing the app, in plain language:
  - what Flatpak is
  - installing Flatpak and adding Flathub for the user
  - checking the `.flatpak` file's SHA-256
  - `flatpak install --user` (the runtime and codecs come from Flathub automatically)
  - how to see that there's no network permission
  - where the vault and settings live (`~/.var/app/io.github.seven11ven.portfolio_jockey/`)
  - the warning that a forgotten passphrase can't be recovered
  - updating, and uninstalling with or without `--delete-data`
  - troubleshooting: portals, the memory-only folder, codecs, terminal output
  - a pointer to the packaging files
- **`app/tool/package-bundle.sh`:** the kit now includes `docs/install.md` as `INSTALL.md`, and `TESTING.md` is always included.
  - Backup: `version-control/local-app/2026-10-23_before-install-doc/`.
- **Kit rebuilt** with the Settings license text: 172 tests pass (13 skipped), and the privacy check and `flutter analyze` are clean.
  - Bundle SHA-256: `79161474…be503`. Kit SHA-256: `bb6d8696…9872f`.
- **Known limit:** `INSTALL.md` links to other repo files by relative path. Those links don't work inside the kit, only in the repo.
- **Impact:** documentation and packaging only. **Not committed.**

## First build on the PM's PC: libplacebo in lib64/, fixed
**Time:** 2026-10-23 12:08 UTC
- **First run of `build.sh`:** it stopped as designed because `flatpak-builder` wasn't installed. Its message asked for a log-out, which only a fresh Flatpak install needs. Now it asks for that only when `flatpak` itself is missing.
- **Second run:** libsodium, libass and libplacebo built, then mpv's meson failed with `Dependency "libplacebo" not found`.
  - The PM's diagnostics showed libplacebo installed into `/app/lib64/` (`lib64/pkgconfig/libplacebo.pc`, `lib64/libplacebo.so.360`).
  - pkg-config searches only `/app/lib/pkgconfig` and `/app/share/pkgconfig`, and the app's loader looks in `/app/lib`.
- **Fix:** pinned the library folder to `lib/` in the manifest: `--libdir=lib` for libplacebo and libmpv (meson), and `-DCMAKE_INSTALL_LIBDIR=lib` for Poppler (CMake), which could otherwise do the same. A comment in the manifest explains why.
- **Kit rebuilt:** 172 tests pass (13 skipped), and the privacy check and `flutter analyze` are clean. Kit SHA-256: `5aad2810…2061b`.
- **Correction:** the bundle's SHA-256 (`79161474…be503`) matched the previous build of the same app code exactly. So "Flutter's build isn't reproducible" was too strong: one pair of builds differed, this pair matched. Reworded in `docs/dependencies.md` and `package-bundle.sh`, to say it's not guaranteed.
- **Backup:** `version-control/local-app/2026-10-23_before-libdir-fix/`. The earlier `package-bundle.sh` is already in `2026-10-23_before-install-doc/`; only comments changed since.
- **Impact:** packaging only. **Not committed.**

## Test A5: the app wasn't in the menu until a log-out
**Time:** 2026-10-23 12:29 UTC
- **What happened:** the build finished, and the app starts. On the PM's Linux Mint (Cinnamon), the terminal showed `Failed to load module "xapp-gtk3-module"`. That's a harmless GTK warning: Mint's add-on isn't inside the sandbox. The Impeller/OpenGLES line is information only.
- **Test A5 failed at first:** the app wasn't in the menu.
  - The desktop file was exported to `~/.local/share/flatpak/exports/share/applications/`, and `desktop-file-validate` printed nothing (valid).
  - After logging out and back in, the app appeared. Flatpak adds the per-user exports folder to `XDG_DATA_DIRS` at login, and this was the PM's first per-user Flatpak app.
- **Change:** a note about this in `build.sh`'s closing message, `TESTING.md` A5 and `docs/install.md`. No packaging change was needed.
- **Backup:** `version-control/local-app/2026-10-23_before-menu-note/`.
- **Impact:** messages and docs only. The next kit build includes them; the PM's current build doesn't need rebuilding. **Not committed.**

## License files and source for the Flatpak's libraries
**Time:** 2026-10-23 12:46 UTC
- **Why:** the PM asked whether the in-app license list is required and complete. That list comes from Flutter (`NOTICES.Z`) and covers the engine and the Dart packages. The five libraries the Flatpak builds weren't covered: their license texts weren't shipped, and no source was offered for the GPL parts.
- **Research** (from upstream files at the pinned versions):
  - libsodium and libass are ISC.
  - libplacebo is LGPL-2.1+, and compiles in fast_float (Apache-2.0 OR MIT OR BSL-1.0) and a glad-generated loader.
  - mpv is GPL-2.0-or-later.
  - Poppler is (GPL-2.0-only OR GPL-3.0-only) AND GPL-2.0-or-later.
  - All can be combined with AGPL-3.0-or-later (GPLv3 §13 and AGPLv3 §13).
  - flatpak-builder only installs license files automatically from 1.4.5; Ubuntu 24.04 and Mint 22 have 1.4.2.
- **Manifest:** each module's `post-install` copies its license files into `/app/share/licenses/<app-id>/<module>/`, and the app adds its own `LICENSE`. **To confirm on the next build:** that `${FLATPAK_BUILDER_BUILDDIR}` points to each module's unpacked source folder.
- **`build.sh`:**
  - builds with `--bundle-sources --repo=repo`
  - makes the app `.flatpak` and a matching `-sources.flatpak` (the exact sources of every module)
  - installs the app from the `.flatpak` file itself, so the test covers what users get
  - stops if any module's license folder is missing
- **`package-bundle.sh`:**
  - refuses to run with uncommitted changes
  - ships `LICENSE` and `SOURCE_COMMIT` in the kit
  - writes `dist/portfolio-jockey-source-<version>.tar.gz` with `git archive` of that commit, for the AGPL
- **`.gitignore`:** `/packaging/flatpak/repo/`.
- **Docs:**
  - `docs/dependencies.md`: corrected licenses (Poppler, mpv wording, the libplacebo submodules) and a new "Licenses and source for the Flatpak" section
  - `docs/install.md`: where to find the license texts and the source
  - `TESTING.md`: new check A6
  - a release checklist in `public-notes/phase8-packaging.md`
- **Checks here:** `bash -n` on both scripts, and `package-bundle.sh` correctly refuses to run with uncommitted changes. The full kit build has to wait for a commit.
- **Backup:** `version-control/local-app/2026-10-23_before-license-files/`.
- **Impact:** packaging and docs. No app change. The PM's current test build stays valid for `TESTING.md`. **Not committed.**

## Test D4/D5: audio and video crashed; mpv needs LC_NUMERIC=C
**Time:** 2026-10-23 12:51 UTC
- **What happened:** on the PM's PC, opening any audio or video file (m4a, mp3, mp4) crashed the app. Started with `flatpak run --env=LC_NUMERIC=C …`, they played, which confirms the cause.
- **Cause:**
  - libmpv refuses to start unless `LC_NUMERIC` is `"C"`, so `mpv_create` returns NULL and media_kit crashes using it.
  - GTK's startup sets the locale from the environment.
  - `media_kit_libs_linux`, which we don't use because its build downloads mimalloc, normally resets it. Nothing replaced that line.
  - Tests run without GTK, so the locale stayed `"C"` and the bug never showed.
- **Fix:** `app/linux/runner/my_application.cc` calls `setlocale(LC_NUMERIC, "C")` in `my_application_startup`, right after GTK's startup. Dart doesn't use the C locale, so the app's own formatting is unchanged.
- **Test:** `test/linux_runner_test.dart` checks the reset is in `my_application_startup`, after the parent startup call. It fails if the line is removed (checked). A real check needs GTK and a display.
- **Docs:** a media_kit rule in `CLAUDE.md`, and a note in `docs/dependencies.md`.
- **Checks:** `flutter analyze` is clean, the privacy check passes, and the release build works.
- **Backup:** `version-control/local-app/2026-10-23_before-mpv-locale/`.
- **Also seen in the log, not fixed yet:**
  - `media_kit: VideoOutput: EGL display or context is invalid` and `S/W rendering`: video is drawn by the CPU.
  - `Failed to open VDPAU backend libvdpau_radeonsi.so`: no hardware decoding through VDPAU, which is harmless.
- **Impact:** audio and video should play when started from the menu. To confirm on the next build. **Not committed.**

## Test D5: closing a playing video froze the app
**Time:** 2026-10-23 12:55 UTC
- **What happened:** on the PM's PC, closing an MP4 preview while it played froze the app ("not responding"). media_kit_video had fallen back to CPU drawing (`EGL display or context is invalid` → `S/W rendering`).
- **Likely cause** (read from the code; it can't be reproduced here without a display):
  - `Player.dispose` (`media_kit-1.2.6 …/native/player/real.dart:89`) sends mpv's `stop`, then runs the release hooks right away.
  - Those hooks reach `video_output_dispose` (`media_kit_video-2.0.1/linux/video_output.cc:40`), which calls `mpv_render_context_free` on the main thread. That forcibly shuts down a still-active video output and waits for it.
  - In the CPU path, mpv's frames are drawn by `gdk_threads_add_idle` callbacks on that same thread, so the two can wait on each other.
- **Fix:** a new `stopVideoOutput` in `ui/preview/preview_views.dart`.
  - It sets `pause=yes` and `vid=no`, then polls `vo-configured` until it reads `no` (every 20 ms, for at most 2 s). It never throws.
  - `MediaPreview` calls it before `player.dispose()`, so mpv closes its video output while the main thread is still free. The readable copy is wiped afterwards, as before.
- **Tests:** `test/ui/media_release_test.dart` (4 tests, with fakes for mpv): the order of steps, an immediate return for audio, the time limit instead of a hang, and errors swallowed.
- **Docs:** a media_kit rule in `CLAUDE.md`, a note in `docs/dependencies.md`, and `TESTING.md` D5 now asks to close the preview while it's playing.
- **Backup:** `version-control/local-app/2026-10-23_before-video-close-fix/`.
- **Note:** the PM's first approval of this plan was a misclick, and the code change was made before they said so. The PM then re-read the plan and approved it as-is.
- **Impact:** to confirm on the PM's PC after the next kit build. **Not committed.**

## Desktop check tools installed
**Time:** 2026-10-23 13:03 UTC
- **PM-approved plan:** run the real app on a virtual screen here, covering the locale, close-while-playing, a tour of every screen, TESTING.md D6–H, and packaging checks.
- **Installed** via `.devcontainer/setup.sh`: `xvfb`, `xdotool`, `xclip`, `python3-yaml`, `appstream`, `desktop-file-utils`. The licence and telemetry check is recorded in `docs/dependencies.md` ("Desktop check tools"): no telemetry; `appstreamcli` links libcurl and is always run with `--no-net`.
- **Backup:** `version-control/local-app/2026-10-23_before-desktop-check/` (`setup.sh` and `.gitignore`).
- **Impact:** the dev container only. **Not committed.**

## Delete project: the name to type is now in quotation marks
**Time:** 2026-10-23 13:27 UTC
- **What happened:** in the PM's test, "Delete project" stayed disabled after typing "To help with next week(2)". The project is called "To help with next week (2)", with a space. The match is exact on purpose, but the unquoted label made that space easy to miss.
- **Change (PM's wording):** the label is now `Type “<name>” to confirm`, using the same curly quotes as the dialog's title. The exact-match rule is unchanged.
  - `app/lib/ui/home/project_dialogs.dart`
  - the mockup `project-mockups/home.html`
- **Test:** `projects_test.dart` checks the quoted label, and that a name with a missing space still doesn't enable the button. It passes, and `flutter analyze` is clean.
- **Backup:** `version-control/local-app/2026-10-23_before-delete-label/`.
- **Impact:** one label in one dialog. **Not committed.**

## The video-close freeze, properly: one shared player
**Time:** 2026-10-23 14:42 UTC
- **Desktop check:** the real release build ran on a virtual X11 screen (Xvfb) here, with `en_US.UTF-8` and Mesa's CPU renderer. media_kit fell back to S/W rendering, as on the PM's PC.
  - **With `stopVideoOutput`, closing a playing video still froze the app permanently** (twice).
  - The app was started under gdb, because attaching is refused in this container. The stacks showed Flutter's raster thread stuck mid-frame inside the GL upload, and the main thread waiting on it.
  - Closing a paused video didn't freeze.
- **Cause:** media_kit_video 2.0.1's `video_output_dispose` frees the pixel buffer that `texture_sw_copy_pixels` hands to the raster thread every frame, without waiting for a frame in flight.
- **Fix:** `app/lib/ui/preview/shared_player.dart`, one player for the app session that's **never disposed**. `MediaPreview` opens files paused and closes them in this order: `pause()`, 250 ms, media_kit's `stop()`, wait for `idle-active`, then wipe the copy.
  - A close that's already been replaced by the next file (prev/next arrows) doesn't stop the new file.
  - Steps run one at a time.
  - Errors and time limits never block the wipe.
  - `stopVideoOutput` and its tests were removed.
- **Found and fixed during testing:** the first version paused and stopped mpv directly, so media_kit's own playing flag went stale, and Play could act as Pause on the next file. It now uses media_kit's `pause()`/`stop()` (no files written; checked in the source).
- **Not established:** a several-second main-thread wait after closing. With the CPU renderer, short waits for frames are normal here. The 250 ms pause before `stop` is kept as harmless.
- **Tests:** `test/ui/shared_player_test.dart` (4 tests). Full run: 177 pass (13 skipped); `flutter analyze` is clean, and the privacy check passes.
- **Desktop check tools:** `app/tool/desktop_check/` (`lib.sh`, `xwd2png.py`, `make_files.py`, `under_gdb.sh`), plus gdb in `setup.sh` (backup in `2026-10-23_before-gdb/`). The test log is in `project-notes/phase8-tests.md` (private). The full `desktop-check.sh` is still to do.
- **Known limit:** the last video frame stays in media_kit's buffer in RAM (never on disk) until another video plays or the app quits.
- **PM decisions:** previews open paused; Flatpak only for now, with a `.deb` as an open idea.
- **Backup:** `version-control/local-app/2026-10-23_before-shared-player/`.
- **Impact:** to confirm on the PM's PC: TESTING.md D4–D6, and Play on a second file.

## "Edit in another app" through the portal, and the "Open vault folder" button
**Time:** 2026-10-23 15:17 UTC
- **PM's second test round:** the shared player works; closing a playing video no longer freezes the app.
- **"Edit in another app" showed no chooser** in the Flatpak.
  - The PM's checks: `flatpak run --command=gio … open <file>` **did** show the desktop's "Open With…" chooser, and the portal backends are `gtk`, `xapp`, `gnome-keyring` and `xapp-gnome-keyring`. So the portal works; the app's way of calling it didn't.
  - **Likely cause:** GLib's `g_app_info_launch_default_for_uri` in a sandbox sends the request asynchronously on the calling thread's main loop, which our worker isolate doesn't run.
- **Fix:** new `app/lib/services/native/portal.dart`, a synchronous D-Bus call to `org.freedesktop.portal.OpenURI.OpenFile` with the copy's fd (read/write) and `{ask: true, writable: true}`. Errors are shown. `GioAppLauncher` uses it inside a Flatpak.
  - New allowlist line (8 GLib/GIO functions); `Libc` gains `openReadOnly`, `openReadWrite` and `closeFd` (O_CLOEXEC).
  - Negative check: an unlisted D-Bus function fails the privacy check.
- **PM request, approved mockup:** an "Open vault folder" button (`Icons.folder_open_outlined`) first in the home top bar.
  - Inside a Flatpak: `OpenDirectory` with the vault's `.pj` folder. Outside: GIO's default handler for the folder.
  - Errors show as a message. It writes nothing, so there's no confirm step.
  - Mockup: `project-mockups/home.html`, scene 1.
- **Found along the way:** the screenshot test (which only runs with `SCREENSHOT_DIR`) had failed since the confirm-at-Fair change. It typed into the confirm field before the redraw that shows it. Fixed with one `pump()`; all 10 screenshot tests pass (78 images, not committed).
- **Tests:**
  - `test/services/portal_test.dart`: GLib parses both requests, and the options are present
  - a widget test: the button opens the vault folder
- **Still to confirm on the PM's PC:**
  - the chooser appears every time
  - the chosen editor can save (`writable`)
  - the folder button opens the file manager
  - **Open risk:** readable copies live in the sandbox's own memory-only folder, and the host may not be able to reach it. The portal should still pass the file by its fd. If not, the copies need to go somewhere the host can see, which needs the PM's decision.
- **TESTING.md:** D notes previews open paused; new D5b (Play on a second file) and H6 (folder button); E1 says the chooser appears every time.
- **Backup:** `version-control/local-app/2026-10-23_before-portal-open/`.
- **Impact:** app code and packaging docs. **Not committed.**

## Edit safeguards (readable copies stay private)
**Time:** 2026-10-23 15:57 UTC
- **PM decision, after discussing the shared Flatpak folder:** readable copies stay in the sandbox's private memory folder, so no other app can read them by path. Instead, the edit flow handles mishaps.
- **`edit_session.dart`:** `save()` first waits `settle` (1 s; tests pass zero) and throws `EditNotReady`:
  - `stillWriting` if the copy changed meanwhile
  - `empty` for a 0-byte copy over a non-empty file, unless `allowEmpty`
  - It also refuses a copy that's no longer a file.
  - Failures keep the project version and leave the edit open.
- **`edit_dialogs.dart`:**
  - the banner's help line
  - Save: scene 5c (still saving, with Try again) and 5d (empty, with a red "Save the empty file"); 5b adds the different-place hint; the close-it-first line
  - Discard: the close-it-first line
  - `AppController` takes `editSettle` (zero in the UI tests).
- **Mockups:** `project-mockups/preview.html` (scenes 4, 5, 5b, 5c, 5d, 9), approved by the PM.
- **Tests:**
  - `test/app/edit_session_test.dart`, 4 new: still writing, empty needs confirmation, a folder in the copy's place, and an unreadable copy keeps the old version and the open edit
  - `test/ui/preview_test.dart`: new texts, and a new empty-copy flow
- **TESTING.md:** E6–E8.
- **Backup:** `version-control/local-app/2026-10-23_before-edit-safeguards/`.
- **Impact:** wording and save checks in the edit flow. **Not committed.**

## Crash and power-cut safety
**Time:** 2026-10-23 16:34 UTC
- **PM request:** a fail-safe for the app closing, or the device turning off, while editing, moving or changing files.
- **Audit:** an Explore agent read every write. I checked the serious items in the code myself:
  - an interrupted export or readable copy left a readable temp file in the user's folder
  - an edit cut off mid-decrypt was offered for saving
  - a cover replace overwrote the cover before the index had its new key
  - an edit save could leave a wrong size in the index
  - moves and imports weren't safe across a crash
  - nothing was cleaned up at unlock
- **Built:**
  - **Edits:** `session.json` is written last, atomically.
  - **New names:** `FileEntry.blobId` and `ProjectIndex.coverId` (optional), with new-name-then-index-then-delete for edit saves and covers.
  - **The journal:** `lib/vault/journal.dart`, `.pj/journal.enc`, encrypted. Exports (through `writeAtomically(onTemp:)`), imports (pre-chosen project IDs) and storage moves are listed in it, and so are open edits.
  - **At unlock:** `ProjectService.recoverJournal` and `cleanUp` (only files from before it started; never unreadable projects).
  - **Fsync:** `syncDirectory` checks `fsync` through `errno` (`__errno_location` added to the allowlist; "not supported" is tolerated). Moves fsync every copied folder.
  - **Messages:** recovery messages appear on the home screen after unlocking. Move progress no longer overcounts.
- **Tests:**
  - `test/services/crash_safety_test.dart` (13)
  - `test/services/storage_move_test.dart` (new)
  - a UI test of the message
  - the cover test updated for `cover-<id>.enc`
  - the move UI test gets more settle rounds (the extra fsyncs make it slower, not stuck)
  - Full run: 201 pass (13 skipped); analyze clean; privacy check passes; release build works.
- **Not verified here:** a real process kill. The tests recreate the disk state a crash leaves; the real kill is TESTING.md J1–J5 on the PM's PC. J5 also settles whether Flatpak keeps the memory folder across a restart.
- **Backup:** `version-control/local-app/2026-10-23_before-crash-safety/`.
- **Impact:** an index format addition (backward compatible), a new journal file, and messages after unlock. **Not committed.**

## Edit copies in Flatpak's shared memory folder
**Time:** 2026-10-23 17:04 UTC
- **The PM's test E1:** no chooser appeared. The PM's checks:
  - `gio open "$XDG_RUNTIME_DIR/t.txt"` inside the sandbox: **"Launch failed"**
  - the same in `$XDG_RUNTIME_DIR/app/$FLATPAK_ID/`: the "Open With…" chooser appeared
  - The portal can't hand another app a file in the sandbox's private memory folder.
- **Agreed fallback (PM decision):** inside the Flatpak, edit copies only go in the shared folder; media copies stay private.
  - New `PrivateFolders.forEditing`, with the same private and in-memory checks, and no disk fallback.
  - `EditSessions.editFolders` and `AppController(editFolders:)`.
- **The notice (approved mockup, preview.html scene 8):** inside the Flatpak, the edit dialog says other apps on the device can read the copy while it's open, that it's never on disk, and that it's wiped at Save or Discard.
- **`GioAppLauncher`** refuses clearly if a copy is outside the shared folder. Listening for the portal's late "Response" is an open item.
- **Tests:** `test/services/private_folder_edit_test.dart` (3), and an edit-versus-media folder test.
- **Backup:** `version-control/local-app/2026-10-23_before-shared-edit-folder/`.
- **Impact:** to confirm with E1–E5 on the PM's PC. **Not committed.**

## The edit path check, and the missing folder icon
**Time:** 2026-10-23 17:34 UTC
- **"Edit in another app" refused with my own new error.** Inside the sandbox, `$XDG_RUNTIME_DIR/app/<id>` is a link to `/run/flatpak/app/<id>`, and the copy's path is the resolved one. The check now accepts both forms (`isInFolder` in `gio_apps.dart`; `test/services/gio_apps_test.dart`, including a look-alike name that's still refused).
- **The "Open vault folder" icon was blank** in the PM's build. Reproduced with the release build on the virtual screen: the button and its tooltip were there, but not the glyph. Another folder icon was blank too, and `--no-tree-shake-icons` showed it, so the release build's icon-font shrinking dropped it. `package-bundle.sh` now builds with `--no-tree-shake-icons` (about 1.5 MB more) so no icon can disappear this way.
- **Audio and video "stuck loading" after a few opens** (PM's D4/D5): not reproducible outside the Flatpak (6 rounds loaded fine here). Waiting for the PM's terminal log.
- **Backup:** `version-control/local-app/2026-10-23_before-edit-path-fix/`. **Not committed.**

## PM decision: inbox dismissals need no confirmation
**Time:** 2026-10-23 17:54 UTC
- The brief asks for a confirmation screen before anything that changes files. **PM decision:** in the inbox, dismissing one notice (✕) and marking notices as read go without one; they only change the inbox's own small encrypted file. "Clear all" still asks first.

## Stuck media, the inbox, the false notice, icons
**Time:** 2026-10-23 18:11 UTC
- **Stuck media (PM's D4/D5):** the screenshot showed the app's own spinner, and the log showed one player with every file loaded. The cause is media_kit's unlimited wait for mpv's async replies, while holding the player's lock.
  - `SharedPlayer` now has a 5 s limit per step (`stepLimit`), and a stuck player is set aside for a fresh one (`PlayerStuck`, with a clear message). Each timeout is logged.
  - Tests: 4 new, covering a hung pause, a hung stop during close, and a hung loadfile.
- **The false "edit was open" notice:** a failed edit start now removes its journal entry. Tested.
- **The inbox (approved mockups, home.html scenes 6–8):**
  - storage: `lib/vault/inbox.dart` and `.pj/inbox.enc`, through the new shared `sealed_json.dart` (the journal's file format is unchanged)
  - `ProjectService.inbox/changeInbox`, and `AppController.inbox/unreadCount/markAllRead/dismiss/clearInbox`
  - recovery notices go to the inbox, with titles; the pop-ups are removed
  - the UI: `ui/home/inbox_screen.dart`, and the top bar's `Icons.inbox_outlined` with a `Badge`
  - PM decision: no confirmation for ✕ or mark-as-read; Clear all confirms
  - A UI test covers the badge, opening, ✕, keeping notices across lock and unlock, and Clear all.
- **Icons:** `--no-tree-shake-icons` in `package-bundle.sh`.
- **Checked in the release build on the virtual screen** (as the kit builds it):
  - the top bar with all five icons (folder, inbox, import, lock, settings), with no badge and with a red 1
  - a **real kill** mid-export: the 4.6 MB readable temp file was removed at unlock, and the notice appeared
  - the inbox with the notice and its ✕; dismissing it; the empty inbox
  - 8 media open/close rounds: no timeouts, and the copies were wiped
- **Full run:** 212 pass (13 skipped); analyze clean; privacy check passes.
- **Backups:** `version-control/local-app/2026-10-23_before-inbox/` (with `journal.dart` and `project_service.dart`).
- **Next requests from the PM:** a Settings button to clear the app's temporary files (needs a mockup), and a look at slow clicks, low video frame rate and memory leaks. **Not committed.**

## Temporary files, instant clicks, and memory
**Time:** 2026-10-23 19:13 UTC
- **Temporary files (approved mockups, settings.html scenes 1, 4, 5):**
  - `EditSessions.clearTemporaryFiles` (keeps the open edit and unfinished ones)
  - media copies are wiped at `AppController.start`
  - `prepareToExit`, and `AppLifecycleListener.onExitRequested` in `main.dart`: clear and close, or with an edit open, scene 5 (`requestExit`, which closes after Save or Discard)
  - the Settings row, with its confirmation and "Temporary files cleared."
- **Clicks (PM decision, option A):** a single click opens the preview, with no double-tap wait. The menu is on right-click or a long press. Tests updated to right-click for menus.
- **Memory:** `MALLOC_ARENA_MAX=2` (manifest finish-args) and mpv `demuxer-max-bytes=32MiB`, `demuxer-max-back-bytes=0`. 30 video rounds in the release build: flat at about 350–415 MB, against about 650 MB and rising before. Images: flat, so no leak in the app's own code.
- **Checked in the release build on the virtual screen:**
  - the Security card with the new row (and the Lock icon)
  - the confirmation
  - Clear emptying the memory folder
  - single clicks opening previews in all 30 rounds
- **Full run:** 216 pass (13 skipped); the 10 screenshot tests pass; analyze clean.
- **Docs:** `docs/dependencies.md`, `docs/install.md`, TESTING.md (D click note, H8).
- **Backup:** `version-control/local-app/2026-10-23_before-temp-clear/`.
- **Next:** the video frame rate investigation. **Not committed.**

## Video playback settings: hardware decoding
**Time:** 2026-10-23 20:54 UTC (Preview quality removed 21:01 UTC)
- **Settings → Video playback → Hardware decoding** (PM approved the mockup, settings.html scene 1): a switch, on by default; mpv `hwdec=auto-copy-safe`, or `no`. It falls back to CPU decoding if there are no drivers. Saved in `settings.json` (`hardwareDecoding`; an unknown value counts as on) and applies to the next video.
- **Preview quality (Balanced / Full) was built, then removed** (PM decision: ship decoding only, fix Balanced later). The check in the release build showed mpv's scale filter doesn't help: media_kit sizes its picture from the size before filters, so a 1920×1080 video was still drawn at 1920×1080 (shrunk, then drawn back up). `setSize` alone is reset by media_kit on every new video. Details in `docs/dependencies.md`. The mockup still shows the row, as the target for later.
- **Code:** `AppSettings` and `AppController` (`hardwareDecoding`, `setHardwareDecoding`), `videoPlaybackOptions` (`preview_views.dart`), and `SharedPlayer.open(options:)`, which waits for the VideoController to start, then sets each option (time-limited) before `loadfile`.
- **Tests:** 7 new (option order, waiting for the video output, stuck option and start steps, both option values, the switch saved and reloaded, `fromJson` defaults). The Change passphrase test now scrolls to its button. **Full run:** 223 pass (13 skipped); analyze clean; privacy check passes.
- **Checked in the release build on the virtual screen:**
  - the new card (no icons), and the switch saving to `settings.json`
  - videos playing with the options set
- **Found while checking, not fixed:**
  - On the virtual screen, a playing video can make the app stop responding for up to a minute. gdb showed Mesa's software renderer busy on both of the container's cores; it recovers, and the last commit (`a03d5a1`) does the same. Not an app bug.
  - **A video bigger than the free space in the memory folder spins forever** instead of showing an error (a 124 MB video against a 64 MB `/dev/shm` here). Needs a fix: an error that says the file is too big to preview.
- **Docs:** `docs/dependencies.md` ("Video playback settings"), `CLAUDE.md` (media rules), TESTING.md (D7).
- **Backup:** `version-control/local-app/2026-10-23_before-video-settings/` (with the mockup from before the card).

## PM test results recorded
**Time:** 2026-10-23 21:33 UTC
- TESTING.md: everything passes (PM) except **D4–D7** (audio and video). With kit `59f0c7d`, the log showed repeated `Failed to open VDPAU backend libvdpau_radeonsi.so`, then `SharedPlayer: pause timed out after 5 s`; the preview said the player stopped responding, then the whole app froze.
- Next: a quick look at known media_kit problems before choosing between the desktop's own player (portal) and a GStreamer player of our own.
- **media_kit known problems (web search):** media-kit issue #1404 (open): on Flutter 3.38+ media_kit_video 2.0.1 always falls back to CPU (S/W) rendering on Linux, X11 and Wayland; the fix (PR #1466) isn't merged or released and hasn't been tested on real hardware. Linux freeze and crash reports during video load: #898, #852. No upstream report matches the `pause` hang. The project has 342 open issues.

## Audio and video play in the desktop's own player; media_kit removed
**Time:** 2026-10-23 21:47 UTC
- **PM decisions:**
  - play in the desktop's own player through the portal
  - a **Play** button, so no readable copy exists until it's pressed
  - remove media_kit and libmpv completely
  - layout approved from the preview shown in the question
- **Why:** media_kit's in-app player froze the app on the PM's PC (D4–D7 failed: `pause timed out`, then a full freeze). The cause is upstream: media-kit #1404, open, not fixed (see `docs/dependencies.md`). The PM pointed out that the issue tracker was never checked when media_kit was chosen. That check is now required in CLAUDE.md, and saved as a standing rule.
- **App:**
  - `MediaHandoff` (`preview_views.dart`) replaces `MediaPreview`. It shows a note or play icon, "Plays in your desktop's audio/video player.", the warning, and **Play** (then **Play again**, which reuses the copy).
  - The copy is made in `EditSessions.editFolders` (Flatpak's shared memory folder inside the sandbox) and wiped when the preview closes.
  - Errors are shown in the stage: no memory folder, the memory folder full (ENOSPC), the player didn't open.
  - **New launcher method:** `AppLauncher.openToView`. In the Flatpak it calls `OpenUriPortal.openFileToView` (`ask` false, `writable` false); outside it, GLib's default app.
  - The start, unlock and Clear wipes now cover media copies in both folders.
  - **The endless spinner:** the preview loader caught only `Exception`, so an `Error` left the stage spinning forever. It now catches everything.
  - **Removed:** `shared_player.dart`, the Hardware decoding setting (the code is back to `a03d5a1`), `MEDIA_KIT_LIBS_AVAILABLE` in CMake, and `setlocale(LC_NUMERIC)` in the runner (only libmpv needed it).
- **Dependencies:** removed media_kit, media_kit_video and wakelock_plus_platform_interface. With them, 21 packages left `pubspec.lock`, 20 entries left `allowed-packages.txt`, and 9 reviewed hits left `reviewed-hits.txt`. `setup.sh` no longer installs libmpv-dev or libepoxy-dev.
- **Flatpak:** removed the libass, libplacebo and libmpv modules, `--socket=pulseaudio` and `MALLOC_ARENA_MAX`. `build.sh` checks licenses for libsodium, poppler and the app only, and the codecs check is gone.
- **Tests:**
  - **Removed:** `shared_player_test`, `media_lockdown_test` and `linux_runner_test`.
  - **Added:** nothing is decrypted before Play; Play hands over a copy, Play again reuses it, and closing wipes it; the audio wording; a player that fails to open; media copies in the edit folders, with old ones cleared; the portal's view arguments.
- **Mockups:** `preview.html` scene 2 now shows the hand-off; the Video playback card is gone from `settings.html`.
- **Docs:** `CLAUDE.md`, `docs/dependencies.md`, `docs/install.md`, TESTING.md (A4, A6, D4–D7 rewritten), `public-notes/phase8-packaging.md`.
- **Full run:** 208 pass (13 skipped); analyze clean; privacy check passes (38 reviewed hits).
- **Checked in the release build on the virtual screen** (with a fake default player registered): the video and audio stages and icons; no copy before Play; Play launched the default app with a readable copy; Play again; closing wiped the copy; the 124 MB file showed the "too big" error and left nothing behind; Settings without the Video playback card.
- **Backup:** `version-control/local-app/2026-10-23_before-desktop-player/`.
