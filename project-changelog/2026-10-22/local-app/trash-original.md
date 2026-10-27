# "Delete from device" moves the original to the Trash

**Date:** 2026-10-22
**Time:** 2026-10-22 15:27–15:40 UTC
**Performed by:** Claude Code
**Decided by:** project manager

## Why
Inside a Flatpak, picked files arrive as document-portal paths. The portal docs don't say whether an app can permanently delete the real file through such a path. They do document a **Trash portal**. The project manager decided that removing the **original** should move it to the system Trash from the start, on every install, with the wording changed from "deleted" to "Trash". The Flatpak details are tested in phase 8.

## Change
- **`app/lib/services/native/gio_trash.dart` (new):** `dart:ffi` bindings to 4 GLib functions (`g_file_new_for_path`, `g_file_trash`, `g_object_unref`, `g_error_free`).
  - They run on a background isolate, behind a `Trasher` interface.
  - The library is already loaded by Flutter's GTK engine, so **no new package** is needed.
- **Reviewed in GLib's source** (`gio/glocalfile.c`, `gio/gtrashportal.c`):
  - Inside a Flatpak, `g_file_trash()` opens the file read/write and calls the Trash portal over the **session D-Bus**, the desktop's local message bus.
  - Otherwise it uses the freedesktop Trash (`~/.local/share/Trash`, or `<drive>/.Trash-<uid>`).
  - There's no network access and no process spawning.
- **`app/tool/allowed-native-libs.txt`:** only that file may open the three GLib libraries, and only those 4 functions. GIO's socket functions stay unreachable.
- **`ProjectService`:** `deleteOriginal` became `trashOriginal`, and `deleteFromBoth` became `trashOriginalAndDeleteCopy`. The original goes to the Trash first: if that fails, nothing else changes. The project copy is still deleted permanently.
- **Wording**, in the UI and in the mockup `project-mockups/project.html` (scenes 3, 4a, 4c, 5):
  - **Menu:** "Move to Trash" *(the original)*, "Delete from project" *(the encrypted copy)*, "Trash original, delete copy".
  - **Dialogs:**
    - "Move the original to the Trash?", with **Move to Trash**.
    - "Trash the original and delete the copy?", with **Trash and delete**.
    - Both say the original can be restored until the Trash is emptied.
  - **Original missing:** "…so it can't be moved to the Trash. Only the project copy can be deleted."
  - **New notices after each confirmed delete:** "…: original moved to Trash", "…: removed from the project", and "…: original trashed and project copy deleted".
- **Layout fix found by the new test:** file-menu rows overflowed while the menu animated open. Their text now shrinks with an ellipsis.
- **`public-notes/phase8-packaging.md` (new):** the phase 8 plan.
  - Test the Trash portal with portal paths.
  - Check whether the picker grants read/write.
  - Show the real location via `user.document-portal.host-path` / `GetHostPaths`.
  - Persistence across restarts, the storage folder, error messages, bundling libsodium, and no network permission.
  - Open: arm64 and Flathub.
- **`docs/dependencies.md`:** a GLib row in "Native libraries".
- **`CLAUDE.md`:** the Trash rule, and the phase 8 notes file.

## Verification
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- **`flutter test`: 85 tests pass** (6 skipped: screenshots and the real-Trash test run only on request). They cover:
  - the original going to a fake Trash while the encrypted copy stays
  - "both"
  - a Trash failure changing nothing
  - the original already being gone
  - the dialog wording and success notice, with Cancel writing nothing
  - greying when the original is missing
- **The real GLib Trash** was tested with a throwaway `XDG_DATA_HOME`, never the real Trash. The file landed in `Trash/files/` with a standard `.trashinfo` (`Path=`, `DeletionDate=`).
  - On `/tmp`, which is a separate system drive in this container, GLib refused with "Trashing on system internal mounts is not supported". The app showed that as an error and left the file in place.
- **`check-privacy.sh` passes.** A throwaway copy binding GIO's `g_socket_new` fails it.
- The screenshots of the file menu, both Trash dialogs and the original-missing menu were re-rendered and match the updated mockup.
- `flutter build linux --debug` compiles.

## Impacts
- **Originals are never permanently deleted by the app.** Users can restore them from the Trash.
- **On drives without a Trash** (some USB sticks or network drives), moving to the Trash fails with GLib's message, and nothing is changed.
- **Backup:** `version-control/local-app/edit006-2026-10-22_before-trash/` holds the previous files.
