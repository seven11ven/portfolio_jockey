# Phase 8 notes: packaging the Linux Flatpak

A running list of what phase 8 (packaging) must do and test. Add to it as earlier phases find things. It's started 2026-10-22.

Flatpak can't run in this Codespace, because the sandbox it needs isn't allowed here. So these tests need a real Linux desktop, ideally the project manager's own machine.

## Decided
- **"Delete from device" moves the original to the Trash,** never deleting it permanently. This was decided by the PM on 2026-10-22 and is already built (`app/lib/services/native/gio_trash.dart`).
  - The app calls GLib's `g_file_trash()`.
  - Inside a Flatpak, GLib hands the file to the desktop's **Trash portal** (`org.freedesktop.portal.Trash`) over the session D-Bus, the desktop's local message bus, not the network.
  - Outside a Flatpak, it uses the standard Trash folder.
  - The encrypted copy in the project is still deleted permanently, as before.
- **No network permission** in the Flatpak manifest (`--share=network` must not appear).
- **libsodium is bundled,** built from the official release after its minisign signature is checked (key `RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3`, confirmed on two official sources). The app loads `libsodium.so.26` (1.0.19+) or `libsodium.so.23`.
- **App ID:** `io.github.seven11ven.portfolio_jockey`.
- **Processors (2026-10-22):** the first release is **x64 only**. arm64 comes later, because it needs an arm64 build machine (Flutter can't build for one processor from the other).
- **How it's offered (2026-10-22):** first as a single **`.flatpak` file**, for example on GitHub Releases once the repo is pushed. Flathub may come later. It would need the public `github.com/seven11ven/portfolio_jockey` repo, a Flathub review, and building Flutter from source without network during the build.
- **Runtime (2026-10-22):** `org.freedesktop.Platform//26.08` (GTK 3, GLib, cairo, epoxy and glibc 2.44 are included, and it's supported until about 08/2028).
- **Video codecs (2026-10-22):** mpv uses the runtime's FFmpeg. H.264/HEVC come from Flathub's `org.freedesktop.Platform.codecs-extra` extension, which is installed automatically, so the app never ships patent-restricted decoders itself. The runtime's FFmpeg has network code, but it's unreachable: the sandbox has no network, and the app whitelists only `file`.
- **Built as modules:** mpv 0.41.0 (libmpv only, with Lua, JavaScript, Blu-ray, DVD, CD audio and libarchive off), libplacebo, libass, Poppler 26.10.0 (GLib binding only, with NSS, GPGME and libcurl off), and libsodium 1.0.22 (minisign signature checked).
- **Media previews open paused (2026-10-23):** the user presses Play. It was a side effect of loading files with mpv's `loadfile`; the PM kept it as a decision.
- **License (2026-10-22):** `AGPL-3.0-or-later`, in the metainfo and the README.
- **App icon (2026-10-22):** the locked card stack (option C), shipped as an **SVG only** for now (`hicolor/scalable`). Flathub would also want PNGs (128 and 256 px).
- **Where it's built and tested (2026-10-22):** on the PM's own Ubuntu-family PC. This Codespace blocks the user namespaces Flatpak needs. Everything is prepared here (manifest, app bundle, `build.sh`, test checklist), and the PM runs the build and tests.
- **Readable copies only in memory** (phase 6): audio/video copies and "Edit in another app" copies go only in `$XDG_RUNTIME_DIR/portfolio_jockey/`, which must be on tmpfs. Otherwise the app refuses. The Flatpak must not change that rule.

## To test inside the Flatpak
1. **The file picker hands the app portal paths.** Files picked with "Add files" arrive as `/run/user/<uid>/doc/<id>/<name>`. Check that:
   - Adding and encrypting them works.
   - The path saved as the "original" still works after the app restarts. The portal docs say picked files "stay accessible across sessions".
2. **Moving to the Trash through a portal path.**
   - The Trash portal only trashes a file the app "can open in r/w mode". Check whether the picker grants **read/write** (the portal docs don't say).
   - If it grants only read access, choose between:
     - opening the picker in a mode that grants write access
     - asking again at delete time
     - greying the option with an explanation
   - Confirm the file really lands in the desktop's Trash and can be restored.
3. **Built 2026-10-22, to be tested on the PM's PC.** **Show the real location, not the portal path,** in the "Original location" box and the delete dialogs. Use the `user.document-portal.host-path` file attribute, or the Documents portal's `GetHostPaths` (interface version 5+). The attribute can be read through a libc call such as `getxattr`, which needs a line in `app/tool/allowed-native-libs.txt`.
   - Built: when a file is added from a portal path, the app reads the attribute once and stores it in the encrypted index (`originalShownPath`). The screens show it; Trash and the "original missing" check still use the portal path. Check that the real path shows in the file details and in the "Move to Trash" dialog.
4. **"Original missing" detection** (greying "Move to Trash") should still be correct with portal paths, including after the original is deleted outside the app.
5. **The storage location chosen at first run.** A folder picked through the portal must stay writable across restarts. If not, consider a `--filesystem=` permission for that folder only, never the whole home folder.
6. **Errors are shown, not hidden.** For example, the Trash portal missing (`Trash portal is not available`) or files on drives without a Trash. In the dev container, GLib refuses `/tmp`: "Trashing on system internal mounts is not supported".

7. **`$XDG_RUNTIME_DIR` inside the sandbox** (phase 6). Flatpak gives each app its own `/run/user/<uid>`. Check that:
   - it's tmpfs and mode 0700 there, so previews of audio/video and "Edit in another app" work
   - the refusal dialog shows if it isn't
8. **"Edit in another app" through the OpenURI portal.** Inside the sandbox, GLib uses the OpenURI portal and the desktop's app chooser. Check:
   - that the chosen editor can **write** the copy back: the portal may hand it a read-only document-portal path unless the app asks for write access (`writable` option)
   - that editors which save through rename ("safe save") still update the copy the app reads
   - that "Save changes" sees the edit
9. **Bundle or reuse libmpv and Poppler.** The app loads `libmpv.so.2` and `libpoppler-glib.so.8`, and the video plugin links `mpv` and `epoxy`. Decide between building them as Flatpak modules (checksum-verified sources, with the mpv build options chosen to leave out network protocols where possible) and an extension. The freedesktop/GNOME runtimes ship cairo and GLib, but not mpv or poppler-glib.
10. **Media inside the sandbox:** audio output through PipeWire/PulseAudio (`--socket=pulseaudio`), and video through the GPU (`--device=dri`). Both are local and add no network access.

11. **Exports and imports through the portals** (phase 7).
    - The export dialog suggests `~/Documents/<name>.<ext>`. A sandboxed app can't write there without a filesystem permission, so either hide that default inside a Flatpak and require "Change…" (GTK's save dialog goes through the FileChooser portal, which grants write access to the chosen file), or add `--filesystem=xdg-documents`. The first keeps the sandbox tighter.
    - Writing through a portal path: the export writes a temporary file next to the target, then renames it. Check that the document portal allows creating the temporary file and renaming it. If not, write the target directly and delete it on failure.
    - Import reads a `.pjx` picked through the portal (read-only is enough).
12. **Moving the storage location** to a folder picked through the portal: it must stay writable across restarts, like the first-run folder (item 5). Check free space (`statvfs`) on a portal path, too.

## Packaging files (built 2026-10-22)
- `packaging/flatpak/`:
  - the manifest (`io.github.seven11ven.portfolio_jockey.yml`)
  - the `.desktop` file, the `.metainfo.xml` and the `.svg` icon
  - `build.sh`, for the PM's PC
- `app/tool/package-bundle.sh`: it runs every check, builds the release bundle, and makes `packaging/flatpak/dist/portfolio-jockey-build-kit-<version>.tar.gz`, which is git-ignored.
- The module versions and how each source was confirmed are in `docs/dependencies.md` ("Flatpak modules").
- **To confirm on the first build:**
  - the manifest's syntax (no YAML validator here)
  - mpv 0.41.0's meson option names
  - that the Poppler build check passes
  - the metainfo and desktop file validators, which `build.sh` runs if they're installed

## Open ideas
- **A `.deb` package** (asked 2026-10-23), after the Flatpak release. It wouldn't be sandboxed, and it would use the system's libmpv and Poppler (Ubuntu's are built with network protocols and Lua), so it needs its own decision and review. For now: Flatpak only.

## Release checklist
Every release on GitHub publishes these together. Never publish the `.flatpak` without the other two.
1. Commit everything, run `bash app/tool/package-bundle.sh` (it refuses to run with uncommitted changes), and build with the kit's `build.sh`.
2. Tag the commit in `SOURCE_COMMIT` (for example `v0.1.0`) and push the tag.
3. Upload:
   - `portfolio-jockey-<version>-x86_64.flatpak`
   - `portfolio-jockey-<version>-sources.flatpak`, the library sources (GPL and LGPL)
   - `portfolio-jockey-source-<version>.tar.gz`, the app's own source (AGPL)
4. List the SHA-256 of each file in the release notes, with a link to `docs/install.md`.

## Still open
- **Distribution testing:** check the distributions listed in `linux-support.md`.
