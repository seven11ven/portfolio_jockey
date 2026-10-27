# Phase 7: export, import and settings

**Date:** 2026-10-22
**Performed by:** Claude Code
**Decided by:** project manager

## Decisions (PM, 2026-10-22)
- **Two export options, everywhere:** every export, of one project or in bulk, offers exactly two options:
  1. a **custom passphrase:** a checkbox. When it's checked, the passphrase and its confirmation must be filled in and match before Export is enabled. There are no strength rules.
  2. **unlocked:** a regular ZIP or TAR archive.
- **The vault passphrase is never used for exports.**
- **Locked exports** are a Portfolio Jockey-only `.pjx` file (Argon2id and libsodium, like the vault), opened with "Import". The PM chose this over an AES-encrypted ZIP, which would have needed OpenSSL and uses the ZIP standard's weak passphrase protection.

## Step 0: mockup update
**Time:** 2026-10-22 19:03 UTC

- **`project-mockups/export.html`:**
  - **Scene 1** (export, unlocked) gets the "Lock with a custom passphrase" checkbox, unchecked, plus ZIP/TAR and the "not protected" warning.
  - **New scene 1b** (locked): the passphrase and confirm fields, the "can't be recovered" note, a `.pjx` destination, and no format choice.
  - **Scene 2** (bulk): the box is checked and the confirmation is still empty, so Export is shown disabled.
  - **Import** is split in two:
    - scene 4: "Passphrase for this export"
    - scene 5: the confirmation, which says files are re-encrypted with new keys
  - The intro text describes the two options.
- **`project-mockups/settings.html` scene 3:** the note about old exports needing the old passphrase is replaced with "Exports aren't affected", since exports never use the vault passphrase.
- **Backup:** `version-control/local-app/edit009-2026-10-22_before-phase7/`.
- **Shown to the PM** as a private page. Waiting for approval.
- **Approved** by the PM ("the mockup is good").

## Step 1: export format and archive writers (no UI yet)
**Time:** 2026-10-22 19:04–19:15 UTC

### New files
- **`app/lib/vault/export_format.dart`:** the locked `.pjx` format.
  - **Header:** a 40-byte header ("PJEX", version, Argon2id opslimit and memlimit, 16-byte salt), followed by the same secretstream encryption as vault files.
  - **Key:** from Argon2id MODERATE over the export's own passphrase, held in guarded memory.
  - **Opening:** `openLockedExport` checks the passphrase against the first chunk. A wrong passphrase gives `WrongExportPassphrase`.
  - **Checks:** oversized KDF settings and a wrong magic, version or reserved byte are refused before any work.
- **`app/lib/services/archive/`:** our own streaming archive code, so each file passes through chunk by chunk and is never held whole in memory or copied to disk. The `archive` package only takes whole files.
  - **`tar_writer.dart`:** ustar, with PAX for long or non-ASCII names and files of 8 GiB or more.
  - **`zip_writer.dart`:**
    - data descriptors, so sizes aren't needed in advance
    - ZIP64 for large files and archives
    - UTF-8 names
    - deflate through `dart:io`, with already-compressed formats stored
    - our own CRC-32
  - **`tar_reader.dart`:** reads only the tar inside `.pjx`.
    - regular files only, checksums verified, PAX path and size records only
    - paths must be plain ASCII segments with no `..` or leading `/`
    - `finish()` reads to the end, so decryption reaches its final chunk and a cut-off export is detected
- **`app/lib/services/export_service.dart`:**
  - **Unlocked exports:** `<Project>/project.json`, `cover.<ext>` and `files/<real name>`, with clashing names given " (2)". The temporary file is zeroed and deleted on failure or Cancel.
  - **Locked exports:** `manifest.json`, `covers/<p>` and `files/<p>/<f>` inside the encryption. Real names are only in the encrypted manifest, and original device paths aren't exported.
  - **`openLocked`:** reads the manifest and plans the "Name (2)" renames.
  - **`import`:** new projects with new file keys and the original "added" dates. It's all or nothing: on any error or Cancel, the projects it created are deleted.

### Changed files
- **`blob_stream.dart`:** `encryptTo` / `decryptFrom` work on an open file. `encryptToFile` and `decryptFile` are unchanged for callers.
- **`atomic_write.dart`:** an optional `beforeDelete` hook, which zeroes a failed unlocked export.
- **`project_index.dart`:** `FileEntry.create` takes an optional `addedAt`.
- **`ProjectService`:** `openFile`, a decrypting stream that wipes the key when it ends, and `importFile`, which checks the size.
- **`pubspec.yaml`:** `archive 4.5.2` is a **dev** dependency. It was already in the tree and reviewed, and the tests use it as an independent ZIP/TAR reader.

### Verification
- **Archive tests (9):**
  - `archive`'s ZIP and TAR decoders read every file back exactly, including Unicode and over-100-byte names.
  - Python's `zipfile.testzip()` passes, and GNU `tar -tf` lists the same names.
  - Our reader refuses `..`, absolute and non-ASCII paths, links, damaged checksums and archives that end too early.
  - Size mismatches fail.
  - The CRC-32 check value is correct.
- **Slow ZIP64/PAX test** (opt-in, `RUN_SLOW_TESTS=1`, run once at 19:12, 46 s): a file of 4 GiB + 12,345 bytes is read back by Python's `zipfile` and by GNU tar, and the file after it is intact.
- **Export service tests (12):**
  - the unlocked ZIP and TAR layouts
  - nothing secret readable in a `.pjx`
  - a full round trip with new keys and the same contents, tags, dates and cover
  - wrong passphrase, including the vault passphrase
  - a byte changed at three places, a cut-off file and a cancelled import: each fails and creates nothing
  - oversized KDF settings refused
  - a ZIP given as `.pjx` refused
  - a cancelled or damaged export leaves no file
- **Full run:** 141 tests pass, 11 skipped (screenshots, the real Trash, and the slow test). `flutter analyze` is clean, and the privacy check passes.

## Step 2: export and import UI
**Time:** 2026-10-22 19:16–19:22 UTC

### New files
- **`app/lib/ui/export/export_dialog.dart`:** one dialog for one project and for bulk (mockup scenes 1, 1b, 2 and 3).
  - **Lock checkbox:** "Lock with a custom passphrase". When it's checked:
    - Passphrase and Confirm fields appear. Export stays disabled until both are filled in and match ("The passphrases don't match").
    - The "can't be recovered" warning shows.
    - The format row is hidden and the destination becomes `.pjx`.
  - **Unchecked:** ZIP/TAR plus the "not protected" warning.
  - **Save to:** defaults to `~/Documents/<Project>.<ext>`. "Change…" opens GTK's save dialog. The extension follows the choice.
  - **Warnings:**
    - "A file named … already exists there. Exporting replaces it" (GTK's save dialog doesn't ask)
    - the space needed and the space free, with Export disabled when there isn't enough
  - **Progress:** the same dialog shows progress with "Cancel export", and can't be dismissed while running. A snackbar then confirms "Exported to …" or "Export cancelled. Nothing was saved."
  - **Bulk:** "All projects (n)" with a checkbox per project. "Choose at least one project" disables Export.
- **`app/lib/ui/export/import_dialog.dart`:** home's ⤓ button.
  1. Pick a `.pjx`.
  2. "Open this export", with "Passphrase for this export". A wrong passphrase, including the vault's, is refused.
  3. "Import projects?" lists each project with its file count and any "already exists, imported as “Name (2)”".
  4. Progress with "Cancel import".

### Changed files
- **`libc.dart`:** `freeBytes` through `statvfs`, added to the native allowlist. It reads glibc's 64-bit `struct statvfs` (`f_frsize` and `f_bavail`).
- **`file_picker.dart`:**
  - `pickSaveLocation` uses `getSaveLocation`, GTK's native save dialog, which goes through the portal inside a Flatpak.
  - `pickExport` opens one `.pjx` file.
- **`AppController`:** `exports`.
- **Home screen:**
  - The project "…" menu's "Export as ZIP…" and "Export as TAR…" open the dialog with that format preselected.
  - The ⤓ button is enabled for import.
- **Delete-project dialog:** "Export first…" is enabled.

### Verification
- **Widget tests (4):**
  - the lock checkbox and Export button rules, with no strength rules, and Cancel writes nothing
  - a TAR export saved where chosen, with the "already exists" notice and free space shown
  - a locked export, then import: the vault passphrase is refused, the export passphrase opens it, "Kitchen Remodel (2)" is imported
  - bulk selection
- **`statvfs`:** a test compares `freeBytes` with `df`.
- **Full run:** 147 tests pass, 11 skipped. The privacy check passes.

## Step 3: settings
**Time:** 2026-10-22 19:23–19:37 UTC

### New files
- **`app/lib/ui/settings/settings_screen.dart`:** opened from the ⚙ cog on Home and on each project (mockup scenes 1–3).
  - **Color scheme:** System / Light / Dark, plus five accent colours. They apply at once and are saved. It's a preference, not project data, so there's no confirmation.
  - **Storage location:** the path, the project count and size, the free space, and "Move…".
  - **Export:** "Export projects…" opens the bulk export dialog.
  - **Security:** "Change…" (passphrase) and "Lock" (through `requestLock`, so an open edit is finished first).
  - **About:**
    - the version
    - "Network access: None. This app never connects to the internet."
    - "AGPL-3.0 · Show licenses", Flutter's built-in offline licence page
- **`MoveStorageDialog`:** shows From and To, the free space and "Don't remove the drive". It's refused while a file is being edited.
- **`ChangePassphraseDialog`:** current, new (with the first-run strength bar and the same minimum) and confirm. It says files aren't re-encrypted and exports aren't affected.
- **`app/lib/services/storage_move.dart`:**
  - **`plan`:** the picked folder is used if it's empty, otherwise a new "Portfolio Jockey" folder inside it. It's refused if the target is the same folder, inside the current one or the current one is inside it, if the target isn't empty, or if there are links in the storage folder.
  - **`copyAndVerify`:** copies each file and flushes it, then compares it byte for byte. On any failure the partial copy is removed.
- **`app/lib/app/version.dart`:** `appVersion` / `appBuild`. A test keeps them equal to `pubspec.yaml`. `package_info_plus` isn't used, because it runs `stat` as a separate process.

### Changed files
- **`AppController`:**
  - **Appearance:** `themeMode`, `accent` and `setAppearance`.
  - **`moveStorage`:** copy and check, then save the new path, then switch the open vault (`UnlockedVault.relocatedTo`, the same key), then remove the old folder.
  - **`changePassphrase`:** wraps `Vault.changePassphrase`. The open vault stays open.
  - **`isCurrent`.**
  - **`createVault`** keeps the other settings.
- **`settings_store.dart`:** `themeMode` and `accent`, with `copyWith`.
- **`theme.dart`:** `PjAccent`. `buildTheme` takes the accent, and the soft accent colour follows it.
  - The amber accent uses #B45309 instead of the mockup's #D97706, so white button text stays readable.
- **`main.dart`:** the app rebuilds its theme when the settings change.
- **Home and project screens:** the cog opens Settings.
- **Bug fix (lock while reading):** a read cut off by a lock is now recognised by its own vault being locked (`isCurrent`), not by the app's stage. Locking and unlocking again quickly no longer reports an uncaught error.
- **Test helper:** `tempFolder` tolerates a folder a test already removed.

### Verification
- **Settings widget tests (5):**
  - Dark mode and the teal accent apply and are saved, and the storage path is kept.
  - A wrong current passphrase changes no file. After a change, the old passphrase no longer unlocks and the new one does.
  - Moving storage: Cancel writes nothing. Move copies, switches and removes the old folder, and the project opens from the new place, also after lock and unlock.
  - Moving into its own folder is refused.
  - A copy that fails part-way is removed, while the old folder and someone else's file in the picked folder stay.
- **Version test (1):** passes.
- **Full run:** 153 tests pass, 11 skipped. The privacy check passes, and `flutter build linux --debug` builds.

## Step 4: screenshots, docs and final checks
**Time:** 2026-10-22 19:37–19:46 UTC

- **Screenshots:** 8 screens in light and dark. They're rendered by a new screenshot run, `export, import and settings`, and shared with the PM as a private page.
  - The export dialogs (unlocked and locked), import (passphrase and confirmation), Settings, bulk export, moving storage and changing the passphrase.
  - They found one layout fix: Settings values and buttons now sit at the right edge, as in the mockup.
- **`docs/dependencies.md`:**
  - **New "Exports" section:** the two options, the unlocked layout, the `.pjx` byte layout, the inner tar, import rules and known limits.
  - **libc row:** `statvfs`.
  - **`archive`:** now also a dev dependency, used by the tests.
  - **The app's direct dependencies** are updated.
  - **The privacy check's list of negative tests** has the phase 7 case.
- **`public-notes/phase8-packaging.md`:** new items 11 and 12.
  - **11, exports through the portals:** hide the `~/Documents` default inside a Flatpak and require "Change…"; whether the document portal allows a temporary file and rename; read-only import.
  - **12, moving storage to a portal folder.**
- **`CLAUDE.md`:** phases 0–7 are done and phase 8 is next. Added the layout of `ui/export/`, `ui/settings/` and the export services, and the export rules.
- **Backup README:** lists every backed-up file and the new files to delete when restoring.
- **Privacy check:** a throwaway binding of libc's `socket` next to `statvfs` fails it. The file was restored and the check passes.
- **Final checks:**
  - telemetry lockdown: passed
  - `flutter pub get`, then `check-privacy.sh`: passed
  - `flutter analyze`: clean
  - `flutter test`: 153 passed, 13 skipped (screenshots, the real Trash, the slow ZIP64 test)
  - `flutter build linux --debug`: built
  - secret and personal-data scan of every change: clean
  - no ports opened
- **Not committed:** waiting for the PM.

## Step 5: version display, and the "Export a readable copy" mockup
**Time:** 2026-10-22 19:48–19:49 UTC

- **Version (PM decision):** Settings → About shows "0.1.0", without the build number, as does the licence page. `project-mockups/settings.html` now shows "0.1.0" instead of "2.0.0 (build 1)".
- **`project-mockups/export.html`:** new scenes for "Export a readable copy…" of one file, from the file menu or the preview's "…" menu.
  - **6:** "Save a readable copy of contractor-quote.pdf?", with the file and its size, the "not protected" warning, Save to plus Change…, and "Save readable copy".
  - **6b:** the same, when a file of that name already exists ("Saving replaces it").
  - There's no lock option: it's meant as a normal, readable file.
- **Shown to the PM** as a private page (same link as before). Waiting for approval.
- **Approved** by the PM, with no lock option ("that would be redundant").

## Step 6: "Export a readable copy…" built
**Time:** 2026-10-22 19:51–20:02 UTC

### New files
- **`app/lib/ui/export/readable_copy_dialog.dart`:** mockup scenes 6 and 6b.
  - "Save a readable copy of <file>?", with the file and its size, the "not protected" warning, "Save to" with Change… (GTK's save dialog), the "already exists" warning, and a free-space check.
  - "Save readable copy" shows a snackbar: "Saved a readable copy to …".

### Changed files
- **`ExportService.exportReadableCopy`:** decrypts the file chunk by chunk straight into the target, atomically, and checks the size. On any failure the partial file is overwritten with zeros and removed.
- **Where the item appears:** the project screen's file menu and the preview's "…" menu. Both used to be greyed out.
- **Removed:** the "Coming in a later version" placeholder (`comingSoon` / `comingLater` in `ui/common.dart`) and the file menu's `later` helper. Nothing used them any more. `CLAUDE.md` is updated.
- **Bug fix:** the preview's "…" menu labels overflowed while the menu animated open (found by the new test). They now shrink with an ellipsis, like the file menu since phase 5.

### Verification
- **Widget test:** from the file menu and from the preview menu.
  - Cancel writes nothing, and there's no lock option.
  - The "already exists" notice shows, and the saved files match the originals.
- **Service tests (2):**
  - the copy is exactly the decrypted file
  - a damaged file leaves nothing behind
- **Screenshot 37** (light and dark) was added to the PM's review page, and the Settings screenshots were re-rendered with the version showing "0.1.0".
- **Full run:** 156 tests pass, 13 skipped. `flutter analyze` is clean, the privacy check passes, and `flutter build linux --debug` builds.
