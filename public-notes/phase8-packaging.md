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
3. **Show the real location, not the portal path,** in the "Original location" box and the delete dialogs. Use the `user.document-portal.host-path` file attribute, or the Documents portal's `GetHostPaths` (interface version 5+). The attribute can be read through a libc call such as `getxattr`, which needs a line in `app/tool/allowed-native-libs.txt`.
4. **"Original missing" detection** (greying "Move to Trash") should still be correct with portal paths, including after the original is deleted outside the app.
5. **The storage location chosen at first run.** A folder picked through the portal must stay writable across restarts. If not, consider a `--filesystem=` permission for that folder only, never the whole home folder.
6. **Errors are shown, not hidden.** For example, the Trash portal missing (`Trash portal is not available`) or files on drives without a Trash. In the dev container, GLib refuses `/tmp`: "Trashing on system internal mounts is not supported".

## Still open
- **arm64:** it needs an arm64 build machine (Flutter can't build for one processor from the other). Decide whether to offer it.
- **Flathub:** whether to publish there or only offer a `.flatpak` file (e.g. on GitHub Releases). Flathub needs a reachable `github.com/seven11ven/portfolio_jockey` repo.
- **Distribution testing:** check the distributions listed in `linux-support.md`.
