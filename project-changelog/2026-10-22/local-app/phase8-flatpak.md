# Phase 8: Linux Flatpak packaging

**Date:** 2026-10-22
**Performed by:** Claude Code
**Decided by:** project manager

## Decisions (PM, 2026-10-22)
- **Build and test** on the PM's own Ubuntu-family PC. This Codespace can't run Flatpak: `unshare -Ur` is refused, so there are no user namespaces for flatpak-builder or bubblewrap.
- **Distribution:** a single `.flatpak` file first. Flathub may come later.
- **Processors:** x64 only for the first release. arm64 comes later.

## Step 0: support notes
**Time:** 2026-10-22 20:11–20:11 UTC

- **`public-notes/linux-support.md`:**
  - **Requirements:** an x64 processor. The first release is x64 only, and arm64 is planned for later because it needs its own build on an arm64 machine.
  - **"Not supported":** lists arm64 in the first release.
- **`public-notes/phase8-packaging.md`:** "arm64" and "Flathub vs `.flatpak`" move from "Still open" to "Decided", along with where the Flatpak is built and tested.
- **Impact:** docs only.

## App icon choice
**Time:** 2026-10-22 20:16 UTC

- **Options shown to the PM** on a private page: A (monogram), B (locked folder), C (locked card stack), then two the PM asked for:
  - D: a blue monkey facing forward, holding a clipboard
  - E: the same monkey in side profile
- **Chosen:** at first the PM preferred the front-facing monkey (D) over the profile version (E). The PM then chose **option C, the locked card stack** (stacked project cards with a keyhole), as the app icon.
- **Next:** the SVG and its PNG sizes are added to `packaging/flatpak/` in step 3.

## Step 1: research
**Time:** 2026-10-22 20:13–20:16 UTC

A research agent read the primary sources (freedesktop-sdk and gnome-build-meta at pinned tags, Flathub manifests, mpv, FFmpeg, Poppler and libsodium sources and docs). I checked the key runtime claims myself at tag `freedesktop-sdk-26.08.3`:
- `elements/platform.bst` lists gtk3, glib, cairo and libepoxy.
- glibc is 2.44, so a bundle built on Debian 12 (glibc 2.36) runs.
- `components/ffmpeg.bst` is "no patented codecs" (`--disable-decoder="h264,hevc,vc1,vvc"`).
- `include/ffmpeg.yml` builds with `--enable-gnutls`, so its network protocols exist.

### Findings
- **Runtime:** `org.freedesktop.Platform//26.08` has everything Flutter needs, including GTK 3. Flathub supports it for about 2 years (to around 08/2028). GNOME 51 also works, but only until around GNOME 52. Both are free.
- **Not in any runtime:** libmpv, libplacebo, libass, poppler and libsodium. They must be built as modules.
- **libmpv:** Flathub's Lotti (a Flutter app using media_kit) uses freedesktop 26.08 with mpv 0.41.0 (`-Dlua=disabled`) linked to the runtime's FFmpeg. mpv 0.39–0.41 all give `libmpv.so.2`.
- **H.264/HEVC:** Flathub's `org.freedesktop.Platform.codecs-extra` extension adds them, and Flatpak installs it automatically with the runtime. FFmpeg's own legal page says patents are a question for lawyers.
- **FFmpeg `--disable-network`** exists and removes tcp/udp, and with them http/https/tls/rtmp and the rest.
- **Poppler 26.10.0:** `ENABLE_NSS3=OFF` removes signature support entirely and still gives `libpoppler-glib.so.8`. Licence: GPL-2 or GPL-3.
- **libsodium:** the latest is **1.0.22** (2026-04-09), soname `libsodium.so.26`, SHA-256 `adbdd8f1…be3349` (computed by the agent). The minisign signature still has to be checked.

### Decisions (PM, 20:18 UTC)
- **Runtime:** `org.freedesktop.Platform//26.08`.
- **Video:** the runtime's FFmpeg plus Flathub's `codecs-extra` extension for H.264/HEVC. We don't ship patented decoders ourselves.
  - That FFmpeg includes network code. It's unreachable because the sandbox has no network and the app only lets mpv open local files. To check: is `codecs-extra` really installed automatically for our self-hosted `.flatpak`? Test on the PM's PC with `flatpak list --runtime`.
- **Modules we build:** mpv 0.41.0 (`libmpv` only, no Lua, JavaScript, Blu-ray, DVD, CD audio or libarchive) with libplacebo and libass; Poppler 26.10.0 (GLib binding only, NSS, GPGME and libcurl off); libsodium 1.0.22 (minisign signature checked).

## Step 2a: mockups for the sandbox (Floor Planning)
**Time:** 2026-10-22 20:19 UTC

- **`project-mockups/first-run.html`, new scene 1b:** inside the Flatpak, the suggested storage folder is the app's own data folder (`~/.var/app/io.github.seven11ven.portfolio_jockey/data/Portfolio Jockey`), which the sandbox may always use. "Change…" uses the desktop's folder picker.
- **`project-mockups/export.html`, new scene 7:** inside the Flatpak no save location is suggested. The field shows "No location chosen yet" with "Choose…", and Export (or "Save readable copy") stays disabled until a location is chosen. This applies to every export dialog.
- **Backup:** `version-control/local-app/2026-10-22_before-phase8/`.
- **Shown to the PM** as private pages. Waiting for approval.

## Step 2b: show/hide passphrase and the confirm field (PM request)
**Time:** 2026-10-22 20:23 UTC

- **Eye button:** every passphrase field gets a show/hide button. That covers first run, unlock, a wrong unlock, change passphrase, export and import. Each field starts hidden and has its own toggle.
  - **Copying stays blocked:** desktop clipboard histories would otherwise keep the passphrase in plain text. This was recommended to the PM; the PM can still choose otherwise.
  - **First-run scene 1:** shows the passphrase revealed (🙈 to hide).
- **Confirm field (PM chose option 2):** "Confirm passphrase" appears only once the strength bar reaches Fair or better. This applies to first run and the new passphrase in Settings. Export passphrases have no strength rules, so their confirm field stays visible as soon as the lock box is ticked, as approved.
  - **New first-run scene 1a:** a too-short passphrase, with no confirm field and "Create vault" disabled.
- **Mockup files:** `first-run.html`, `settings.html`, `export.html` and `styles.css` (the `.pw` and `.eye` styles).
- **Backup:** `version-control/local-app/2026-10-22_before-phase8/`.
- **Shown to the PM** together with the step 2a Flatpak scenes. Waiting for approval.
- **Update (20:24 UTC), PM decision:** copying is **the user's choice**. Settings → Security gets an "Allow copying passphrases" switch, **on by default**. It comes with a note that some desktops keep copied text in a clipboard history. `settings.html` scene 1 shows the switch, the first-run note mentions it, and `styles.css` has a `.switch` style.

## Step 2c: built (show/hide, copy setting, Flatpak defaults)
**Time:** 2026-10-22 20:25–20:37 UTC

- **`PassphraseField`** (`ui/common.dart`) replaces all 9 passphrase fields (first run, unlock, change passphrase, export, import).
  - It starts hidden, and an eye button shows or hides it.
  - Autocorrect and suggestions are off.
  - When the setting is off, copy and cut are removed from the menu, and Ctrl+C / Ctrl+X do nothing.
- **"Allow copying passphrases"** in Settings → Security is on by default (`AppSettings.allowPassphraseCopy`).
- **Confirm field:** on first run and for the new passphrase in Settings, it appears once the strength is Fair or better.
- **`services/sandbox.dart`:** `runningInFlatpak()`, now also used by `GioAppLauncher`. `AppController.sandboxed` can be set by tests.
- **Inside a Flatpak:**
  - **Storage default:** `$XDG_DATA_HOME/Portfolio Jockey`, with a note on first run.
  - **Export and readable copy:** "No location chosen yet" with "Choose…", and the button disabled until a location is chosen.
- **Tests:**
  - New: the eye toggle, Ctrl+C with copying allowed and with it blocked (clipboard checked), the switch, and both Flatpak defaults.
  - Updated: the setup and settings tests, for the confirm rule and for scrolling to Lock.
  - Full run: 160 pass, 13 skipped. The privacy check passes and the build works.
- **Not done yet (step 2 continues):** showing the original's real location (`getxattr`, test item 3). Steps 3–5 (packaging files, test checklist, install docs) are still to do. **Not committed.**

## Guideline sync
**Time:** 2026-10-22 20:44 UTC
- The PM added two rules to `project-guidelines/`: keep token usage low without bending the other rules (`implementation.md`, Budgeting), and give webhooks and API keys only the permissions they need (`security.md`).
- Synced both into `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` and `.cursorrules`, as `CLAUDE.md` requires. `AGENTS.md` and `CLAUDE.md` already had the least-privilege rule.
- **Impact:** documentation only.

## Step 2d: show the original's real location (test item 3)
**Time:** 2026-10-22 22:47–22:56 UTC

- **Why:** inside the Flatpak, picked files arrive as `/run/user/<uid>/doc/<id>/<name>`. The app showed that path as the "Original location", which means nothing to the user.
- **`vault/native/libc.dart`:** binds libc's `getxattr` (added to `app/tool/allowed-native-libs.txt`). `Libc.hostPath(path)` reads the document portal's `user.document-portal.host-path` attribute, or gives null.
- **`vault/project_index.dart`:** `FileEntry.originalShownPath`, an optional field in the encrypted index, written only when it's set. Old indexes load unchanged. `shownOriginal` gives it, or else `originalPath`.
- **`services/project_service.dart`:** when a file is added, the attribute is read once, and only for paths under `/run/user/<uid>/doc/` or `/run/flatpak/doc/` (`isPortalPath`). Outside a Flatpak, nothing extra is read or stored. `ProjectService` and `AppController` take a `hostPathOf` lookup so tests can fake it.
- **Screens (text only, no layout change):** the preview details, the "Move to Trash" and delete dialogs, and the "no longer at…" note show `shownOriginal`. Trash and the "original missing" check still use the portal path, which is the only one the sandbox can reach.
- **Exports:** unchanged. Device paths, including this one, are never exported (tested).
- **Tests:** `getxattr` on a temp file with the attribute set (real read, including non-ASCII), null for an ordinary or missing file; portal path matching; the service stores the real path while Trash gets the portal path; index round trip and old entries; a UI test of the Trash dialog. Full run: 167 pass, 13 skipped. `flutter analyze` is clean, the privacy check passes, and the debug build works. Negative check: binding libc's `socket` next to `getxattr` fails the privacy check.
- **Backups:** `version-control/local-app/2026-10-22_before-host-path/` (8 files, with a README).
- **Slip, fixed:** a `dart format` run reformatted about 30 unrelated files. They were restored from git before any other change, and my edits were applied again without the formatter. Nothing else changed.
- **Impact:** step 2 is done. The real check happens inside the Flatpak on the PM's PC (`TESTING.md`, step 4). **Not committed.**

## Step 3: packaging files
**Time:** 2026-10-22 22:57–23:16 UTC (it started after commit `f339521`)

- **PM decisions:**
  - Check libsodium's signature with a small Dart tool instead of installing minisign.
  - Ship the icon as an SVG only for now.
- **Sources pinned** (details in `docs/dependencies.md`, "Flatpak modules"):
  - libsodium 1.0.22: minisign signature checked with the new tool
  - libass **0.17.5**, not 0.17.x in general, because it fixes two CVEs: GPG checked
  - libplacebo v7.360.1, as a git source with tag and commit, because the archives lack the submodules OpenGL needs
  - mpv 0.41.0, matching Flathub's pin
  - Poppler 26.10.0: GPG checked
  - The downloads were only hashed, never extracted or run, and were deleted afterwards.
- **New: `app/tool/verify_minisign.dart`** with `test/tool/verify_minisign_test.dart` (5 tests), plus a line for it in `allowed-native-libs.txt`.
  - **`check-privacy.sh`** now scans `app/tool/` as well as `lib/` for native code, and as well as `lib/` and `test/` for network APIs.
  - **Negative check:** an unlisted libsodium symbol in the tool fails the privacy check.
- **New: `packaging/flatpak/`:**
  - **the manifest:** runtime 26.08; libsodium, libass, libplacebo, libmpv, Poppler and the app; the finish-args `wayland`, `fallback-x11`, `ipc`, `dri` and `pulseaudio`, with no network and no filesystem
  - the `.desktop` file, the `.metainfo.xml` (`AGPL-3.0-only`, OARS) and the SVG icon
  - **`build.sh`**, for the PM's PC. It checks the tools and the kit's SHA256SUMS, adds Flathub for the user, installs the runtime, builds and installs the app, makes the `.flatpak` file, and prints the permissions, stopping if network access appears. It also checks codecs-extra and runs the validators if they're present.
- **New: `app/tool/package-bundle.sh`.** It runs the lockdown check, the privacy check, `flutter analyze` and `flutter test`, then the release build. Then it makes a reproducible bundle tarball and the build kit in `packaging/flatpak/dist/`.
- **`.gitignore`:** `packaging/flatpak/dist/`, `build-dir/`, `.flatpak-builder/` and `*.flatpak`.
- **Run here:**
  - `package-bundle.sh` ran end to end: every check and test passed, the release build worked, and the kit was made.
  - The bundle's direct dependencies are all in the runtime, apart from our own libmpv.
  - The highest glibc version needed is 2.34; the runtime has 2.44.
  - The metainfo is well-formed XML.
- **Not checked here:**
  - the manifest's YAML syntax, because no parser is installed
  - mpv's meson option names
  - `appstreamcli` and `desktop-file-validate`, which aren't installed here
  - The first build on the PM's PC checks all of these.
- **Fixed during the step:**
  - The kit's manifest comment had its placeholders filled in too; the comment was reworded.
  - The mpv licence entry first said LGPL; it's GPL-2.0+ (mpv's default build), which is compatible with AGPL-3.0.
- **Backups:** `version-control/local-app/2026-10-22_before-packaging/`.
- **Impact:** no app behaviour changes. Next is step 4 (`TESTING.md`), then the kit is rebuilt so it includes the checklist. **Not committed.**

## Metainfo homepage link
**Time:** 2026-10-22 23:32 UTC
- The PM confirmed the repo is public, so the metainfo now has `<url type="homepage">https://github.com/seven11ven/portfolio_jockey</url>`. It's metadata for software centers only; the app never opens it.
- The license label (`AGPL-3.0-only` or `AGPL-3.0-or-later`) is still waiting on the PM.

## License label: AGPL-3.0-or-later
**Time:** 2026-10-22 23:38 UTC
- PM decision: the app is `AGPL-3.0-or-later` (version 3, or at the user's option any later version).
- The metainfo's `project_license` is now `AGPL-3.0-or-later`. `README.md` has a new "License" section just above its closing line, saying the same and linking `LICENSE`. The rest of the README is unchanged.
- **Impact:** metadata and documentation only. The `LICENSE` text itself (AGPL v3) is unchanged.

## Step 4: TESTING.md, and the kit rebuilt
**Time:** 2026-10-22 23:42–23:46 UTC (it started after commit `ab9cd86`)
- **New: `packaging/flatpak/TESTING.md`.** A plain-language checklist for the PM's PC:
  - A: terminal checks for no network permission, only loopback inside the sandbox, `$XDG_RUNTIME_DIR` on tmpfs with mode 700, and codecs-extra installed
  - B–H: first run, projects and files, every preview type, "Edit in another app", Trash, export, import and readable copies, and settings. These cover test items 1–12 in `phase8-packaging.md`.
  - I: cleanup
  - a results table, with a reminder to remove personal folder names before sharing any output
- **Readable-copy check (D6):** it uses `flatpak enter` on the running instance. A new `flatpak run` gets a fresh sandbox, and could miss leftover copies.
- **Kit rebuilt** with `TESTING.md` inside: 172 tests pass (13 skipped), and the privacy check and `flutter analyze` are clean.
  - Bundle SHA-256: `c1867dfb…26bc`. Kit SHA-256: `8f0dcc64…8406`.
- **Correction:** the bundle's checksum changed between two builds of the same code, so Flutter's release build isn't byte-for-byte reproducible. The packing step is still deterministic. `package-bundle.sh` and `docs/dependencies.md` no longer call the tarball "reproducible".
- **Backup:** `version-control/local-app/2026-10-22_before-testing-doc/`.
- **Impact:** documentation and packaging only. **Not committed.**
