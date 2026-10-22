**Time:** 2026-10-22 13:25 UTC
**Approved by:** project manager

# Portfolio Jockey v2: fully local, encrypted project tracker (Flutter, Linux + Android)

## Context
The cloud version was removed (commit `7533a31`). The project manager's brief, in `project-notes/prompts/application.md`, describes a fully local project tracker for Linux and Android, with no cloud, no login and no accounts.
- **Projects** are folders under a storage location you choose. Each has a name, cover art, a description and tags (the brief calls them "categories").
- **Files** added to a project are encrypted.
- **Every action that changes files** asks you to confirm or cancel first.
- The new **Open Source and Privacy** guideline requires checking every tool and dependency for telemetry.

Decisions made in planning:

| Topic | Decision |
|---|---|
| Framework | **Flutter**, with **zero telemetry enforced in code and config**, not just a setting |
| Encryption key | **Passphrase unlock**: a local unlock, not an account. A forgotten passphrase means the data is lost |
| Encryption scope | **File contents and all names**: project, file and tag names and descriptions live in an encrypted index. On disk, folders and files have random names |
| Exports | **Asked each time**: readable (decrypted, flagged as unprotected) or encrypted |
| "Delete File from Device" | Deletes the **original** file you picked. "From Project" deletes the encrypted copy. "Both" deletes both |
| Viewing files | **In-app preview**, decrypted in memory |
| Editing files | **"Edit in another app"**: a private, temporary readable copy is opened in your editor, then re-encrypted and wiped |
| Categories | **Tags**: several per file, and you can create, rename, delete and assign them |
| Mockups | **Static HTML** with fake data in `/project-mockups/`. The old cloud mockups move to `project-mockups/cloud-service/` |

### Defaults I've filled in (change any of these at review)
- **Tags:**
  - Deleting a tag only removes the label. Files are never deleted that way. Files with no tags appear under "Untagged".
  - Taking a tag off a file is done in that file's "Edit tags". The three delete options always mean the whole file, so they have one meaning everywhere.
- **Confirmations:** the brief's rule is applied to **every** action that writes to disk. That includes creating, renaming and deleting projects and tags, assigning tags, editing descriptions, changing cover art, adding files, exports, moving the storage location and changing the passphrase. One confirm/cancel screen per action, and destructive actions use a red "Delete" button.
- **Readable export layout:** each file is included once, under `files/`, using its real name, plus `project.json` holding the name, description, tags for each file and the cover art. Nothing is duplicated.
- **Additions the brief implies but doesn't list:**
  1. **Import project**, needed to open an encrypted export.
  2. **Change passphrase** in Settings. It re-wraps the key, so files aren't re-encrypted.
  3. **A first-run screen** that warns a lost passphrase can't be recovered.

## How it's built

### Security and storage design
- **Keys:**
  - The passphrase is stretched with **Argon2id**, a slow-by-design hash, to create a key that protects a random 256-bit **master key**. That wrapped key is stored in `<root>/.pj/vault` along with the hash's salt and settings.
  - Each file gets its own random key. Those keys are stored inside the encrypted index, never in plain text.
- **File encryption:** libsodium **XChaCha20-Poly1305 secretstream**. Files are encrypted in chunks, so large videos stream without being loaded whole into memory. Tampered files are detected.
- **Layout on disk:**
  - `<root>/<random-id>/index.enc` is the project's name, description, tags and file list, encrypted.
  - `<root>/<random-id>/blobs/<random-id>.enc` holds each file's contents.
  - `<root>/<random-id>/cover.enc` is the cover art.
  - Every write goes to a temporary file first and is then renamed into place, so a crash can't half-write the index.
- **The key in memory:** the unlocked key is held only in memory, and is wiped when the app locks or quits.
- **App settings** (color scheme, storage location) sit in the app's private config folder. They aren't sensitive, so they aren't encrypted.
- **Android:**
  - "Delete File from Device" asks Android for a lasting permission on the original file when it's picked, then uses that to delete it.
  - The option is greyed out, with an explanation, when that permission isn't available, for example for files shared in from other apps.
  - The storage location is picked with Android's folder picker. This needs a small Kotlin bridge.
- **Crypto library:** `sodium_libs` (bindings to libsodium, which has been independently audited) is the likely choice. Like every dependency it gets vetted first (see phase 2).

### Zero telemetry: four layers
1. **Network block (dev container):** before Flutter is installed, the Google Analytics and Flutter/Dart crash-report hostnames are pointed at nowhere in `/etc/hosts`. A setup check fails if they still resolve.
2. **Pre-seeded opt-out:**
   - Flutter and Dart's telemetry config file is written as disabled **before their first run**. Running `--disable-analytics` would send a one-time "opt-out" event, so it's avoided.
   - The suppression environment variable is set too, after confirming in the current Flutter source that it's still honoured.
   - The exact file name, format and hostnames are checked against the current Flutter/Dart source when this phase runs.
3. **Editor:** `telemetry.telemetryLevel: off` in the dev container's VS Code settings. The Dart and Flutter extensions follow that setting.
4. **The app itself:**
   - The Android **release** manifest has no INTERNET permission, so the app physically can't use the network.
   - The Linux release is built as a Flatpak **without network access**.
   - `tool/check-privacy.sh` fails the build if any analytics or crash-reporting package (Firebase, Sentry and so on) or any network package is in the dependency tree. It also fails if a release manifest asks for INTERNET.

### File preview
- **Images, PDF, text and Markdown:** decrypted in memory and rendered directly.
- **Audio and video** are the hard part:
  - Players expect a file path or a URL.
  - The usual workaround, a local web server inside the app, would need network permission on Android, which layer 4 forbids.
  - So **phase 6 starts with a short test of the options** before anything is built. I'll report back before committing to one.
  - The fallback is decrypting to a RAM-only folder on Linux (`$XDG_RUNTIME_DIR`), or to the app's private cache on Android, wiped as soon as the preview closes.

### Edit in another app
- **How it works:**
  1. Choose "Edit in…" on a file and confirm. The confirmation warns that a readable copy exists while you edit.
  2. The app decrypts the file to a private temporary copy. On Linux this is a RAM-only folder (`$XDG_RUNTIME_DIR`, permissions 0700). On Android it's the app's private cache, shared with the editor through a short-lived, write-enabled link (`FileProvider` with `ACTION_EDIT`).
  3. The file opens in your chosen app.
  4. While it's open, the app shows an "Editing…" banner with **Save changes** and **Discard** buttons. Save changes asks for confirmation, re-encrypts the edited copy and replaces the old one in one step that can't be half-done. Both buttons wipe the temporary copy.
- **Clean-up:** leftover temporary copies, for example after a crash, are wiped the next time you unlock. One file is edited at a time.
- **Usability:** after unlocking, browsing and editing projects works with no extra steps. The passphrase is asked for only when the app opens. There's no automatic lock timer; one can be added as a setting if you want it.

## Phases
Each phase is logged in `project-changelog/YYYY-MM-DD/`. Changed application parts are backed up to `version-control/` first. Phase 1 needs your approval before any UI is built.

0. **Housekeeping (docs only):**
   - Sync `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` and `.cursorrules` with the new **Open Source and Privacy** rule.
   - Log it.
   - Your `cloud-service/` reorganization of the changelogs and backups stays as you left it. I'll commit it only if you ask.
1. **Mockups (Floor Planning gate):**
   - Move the old mockups to `project-mockups/cloud-service/`.
   - New static HTML, each screen in both a desktop (Linux) and a phone (Android) layout, light and dark:
     - first run: set a passphrase, with the warning
     - unlock
     - home: project grid and a "New project" button
     - new and edit project: name, cover art, description
     - the project "…" menu: rename, export, delete
     - project view: file grid, tag filter, "Add files"
     - add-files confirmation
     - the file right-click or long-press menu and its 3 delete confirmations
     - the tag manager and per-file tag editor
     - preview
     - "Edit in…": the confirmation, then the editing banner with Save changes and Discard
     - the export dialog: zip or tar, readable or encrypted
     - settings: color scheme, version, storage location (with the move confirmation), bulk export, change passphrase
     - import
   - **I stop here for your approval.**
2. **Toolchain and privacy lockdown:**
   - Dev container: a pinned Flutter SDK version, the Android SDK command-line tools, the Linux desktop build packages, and telemetry layers 1–3.
   - `docs/dependencies.md`: for each tool and package, its license, cost and telemetry, checked on its own site and docs in full, as Budgeting and Privacy require.
   - `.gitignore` additions: `build/`, `.dart_tool/`, `android/local.properties`, `*.jks`, `*.keystore` and `key.properties`. The Android signing key must never be committed.
3. **Scaffold:**
   - `flutter create` with only the Linux and Android platforms.
   - Strict lints.
   - The release manifest with no INTERNET permission.
   - `tool/check-privacy.sh`.
4. **Vault core:** the encryption, the index, writes that can't be half-done, and the unlock flow. This is pure Dart, unit-tested on Linux. It's the most security-critical code, so it gets the most tests.
5. **Projects, tags and files UI** built to the approved mockups, with confirmations everywhere. Includes the Android bridge for deleting originals and picking the storage location.
6. **Preview and "Edit in another app":** the audio and video test, then the build, as described above. The Android editing link goes in the same Kotlin bridge.
7. **Export, import and settings:** zip and tar export, readable or encrypted, for one project or all of them. Import. Color scheme. Version display. Moving the storage location, which copies everything, checks the copies, then removes the originals. Change passphrase.
8. **Packaging:**
   - A Linux Flatpak with no network.
   - An Android APK signed with a key you create locally and never commit.
   - Install instructions in `docs/`.
   - No paid stores. Play Store's $25 fee is excluded unless you say otherwise.

## Verification
- **Unit tests for the vault:**
  - Encrypt then decrypt gives back the same bytes.
  - A wrong passphrase is refused.
  - A tampered file or index is detected.
  - A crash during a write leaves the old index intact.
  - Changing the passphrase keeps every file readable.
  - Nothing readable shows up on disk: a test greps the vault folder for known file names and contents.
- **Privacy:**
  - `tool/check-privacy.sh` passes.
  - `aapt dump permissions` on the release APK shows no INTERNET permission.
  - The dev container setup check confirms the telemetry hostnames are blocked and the config file says disabled.
  - `~/.dart-tool/dart-flutter-telemetry.log` stays empty after builds.
- **Widget tests:** every action that writes to disk shows a confirm/cancel screen, and Cancel leaves the disk untouched.
- **Manual checks on Linux and an Android emulator:**
  - Create a project, tag files, preview them, and use all three delete options.
  - Export readable and encrypted, then import the encrypted export.
  - Move the storage location.
  - Lock and unlock.
  - Edit a file in another app (LibreOffice on Linux, a phone editor on Android), then save, and confirm the encrypted version changed. Discard an edit and confirm the temporary copy is gone.
- **Security:** the dependency audit (`dart pub outdated` and advisories) is recorded, and no ports or emulators are left running at the end of each session.
