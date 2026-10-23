# Testing the Portfolio Jockey Flatpak

A checklist for the first test round on your own PC, after `bash build.sh` has finished. Tick each box, and for anything that fails, write down what you did, what happened, and the exact error text or a screenshot. Then send the results back (the table at the end is enough).

Use **throwaway test files** (a few photos, a text file, a PDF, a short song and a short video). Don't test with files you care about: some steps move files to the Trash.

**Terms used below:**
- **Sandbox:** the Flatpak runs the app walled off from the rest of your PC. It can only see files you hand it through the desktop's file dialogs ("portals").
- **Portal path:** how a file you picked looks from inside the sandbox, for example `/run/user/1000/doc/ab12cd/photo.jpg`. You should never have to see one.
- **tmpfs:** a folder that lives in memory only, never on the disk. Portfolio Jockey keeps the readable copies it needs for audio, video and "Edit in another app" only there.

---

## A. Before you start the app (terminal checks)
Run these in a terminal. They don't change anything.

- [x] **A1. No network permission.**
      `flatpak info --show-permissions io.github.seven11ven.portfolio_jockey`
      Under `[Context]`, the `shared=` line must say `ipc` only. It must **not** say `network`.
- [x] **A2. No network inside the sandbox.**
      `flatpak run --command=sh io.github.seven11ven.portfolio_jockey -c 'cat /proc/net/dev'`
      Only the `lo` line (loopback, the PC talking to itself) should be listed. No `eth0`, `wlan0`, `enp…` or `wlp…`.
- [x] **A3. The memory-only folder is tmpfs and private.**
      `flatpak run --command=sh io.github.seven11ven.portfolio_jockey -c 'stat -f -c %T "$XDG_RUNTIME_DIR"; stat -c %a "$XDG_RUNTIME_DIR"'`
      The first line should say `tmpfs`, and the second `700`.
- [x] **A4. No sound permission.** `flatpak info --user --show-permissions io.github.seven11ven.portfolio_jockey` has no `pulseaudio` line: audio and video now play in your desktop's own player. (Re-check with the new kit.)
- [x] **A5. The app is in the menu,** with the stacked-cards icon and the name "Portfolio Jockey". If it's missing after your first install, log out and back in once, then check again. The menu only finds apps installed for your user after Flatpak has set that up at login. Only count it as a fail if it's still missing after that.

- [x] **A6. License files are installed.**
      `flatpak run --command=ls io.github.seven11ven.portfolio_jockey /app/share/licenses/io.github.seven11ven.portfolio_jockey`
      It should list `libsodium  poppler  portfolio_jockey`.

## B. First run and unlocking
- [x] **B1.** Start the app from the menu. The first-run screen appears.
- [x] **B2. Storage default.** The suggested storage location is inside the app's own data folder (`~/.var/app/io.github.seven11ven.portfolio_jockey/data/Portfolio Jockey`), with a note saying why.
- [x] **B3. Passphrase field.** It's hidden as you type, and the eye button shows and hides it. The "Confirm" field only appears once the strength reaches **Fair**.
- [x] **B4.** Click **Create vault**. The home screen appears.
- [x] **B5. Storage folder survives a restart** (test item 5). Close the app, start it again, and unlock with your passphrase. Your vault is still there.
- [x] **B6.** A wrong passphrase is refused with a clear message.

## C. Projects and files
- [x] **C1.** Click **New project**, give it a name and description, and confirm. It appears in the list.
- [x] **C2. Adding files through the portal** (test item 1). Open the project and click **Add files**. Pick a few test files from your home folder. The file dialog is your desktop's own. Confirm **Encrypt and add**. The files appear.
- [x] **C3. Real location, not the portal path** (test item 3). Open a file's details (**Preview**). Its "Original" line shows the real place, for example `/home/<you>/Pictures/photo.jpg`, **not** `/run/user/…/doc/…`.
- [x] **C4. Still works after a restart** (test item 1). Close and reopen the app, unlock, and open the same file's details. The real location still shows.
- [x] **C5.** **Rename**, **Edit tags…**, **Change cover art and description**, and **Delete from project** each work. Their **Cancel** changes nothing.

## D. Previews
Open each type by **clicking it once** (right-click or a long press opens the file's menu). Audio and video open with a **Play** button that hands them to your desktop's player.
- [x] **D1.** An image (zoom in and out).
- [x] **D2.** A text file and a Markdown file.
- [x] **D3.** A PDF (go to the next and previous page).
- [ ] **D4. Audio.** Open an audio file (MP3 or M4A). The preview shows a note icon, "Plays in your desktop's audio player.", the warning that other apps can read the copy while it plays, and a **Play** button. Press Play: your default audio player opens and plays it. The text changes to "Playing in…" and the button to **Play again**.
- [ ] **D5. Video.** The same with an MP4 (and a WebM if you have one): your default video player opens and plays it, with sound. Portfolio Jockey stays responsive the whole time.
- [ ] **D5b. Play again.** Close the player window, then press **Play again** in the preview. The player opens again with the same file.
- [ ] **D5c. Closing stops it.** Start a video, then close the preview in Portfolio Jockey (back arrow). The readable copy is deleted, so the player stops or shows an error. That's expected. Portfolio Jockey must not freeze.
- [ ] **D6. Readable copies are cleaned up.** Keep the app open.
      1. Open a video preview and press **Play**.
      2. Run `ls -la "$XDG_RUNTIME_DIR/app/io.github.seven11ven.portfolio_jockey/portfolio_jockey"` in a normal terminal (outside the app). A `view-…` folder with the copy should be listed.
      3. Close the preview and run the same command again. The `view-…` folder should be gone.
- [ ] **D7. Nothing before Play.** Open a video preview, but don't press Play. Run the command from D6: no `view-…` folder is there.

## E. "Edit in another app" (test item 8)
- [x] **E1.** On a text file, choose **Edit in another app…**, then **Open**. Your desktop's "Open With…" chooser appears **every time**, even if you picked an app before. Pick a text editor. If nothing appears, or the app shows an error, note the exact message.
- [x] **E2.** The editor opens the file and **can save it**. Make a small change and save. If the editor says the file is read-only, note the exact message.
- [x] **E3.** Back in Portfolio Jockey, the edit banner shows. **Save changes…** stores the edit, and the preview shows the new text.
- [x] **E4.** Repeat with **Discard…**: the project copy stays as it was.
- [x] **E5.** Try an image editor such as GIMP, if you have one. Some editors save by replacing the file; check that the edit still arrives.
- [x] **E6. Saving too early.** In the editor, start saving a large change, and press **Save changes** in Portfolio Jockey right away. If the editor is still writing, the app says "The other app is still saving this file…" and writes nothing. **Try again** then works.
- [x] **E7. Empty file.** In the editor, delete all the text and save. **Save changes** shows "The edited copy is empty" and only saves after **Save the empty file**. Cancel keeps the old version.
- [x] **E8. Save As.** In the editor, use **Save As** to a different place, then **Save changes** in the app. It says there are no changes and that the editor may have saved to a different place.

## F. Moving originals to the Trash (test items 2, 4, 6)
- [x] **F1.** On a file you added, open the menu and choose **Move to Trash**. The dialog shows the **real** location (not a portal path). Cancel changes nothing.
- [x] **F2.** Confirm. The app says the original was moved to the Trash, and the project copy stays.
- [x] **F3.** Open your desktop's Trash. The file is there and can be **restored** to where it was.
- [x] **F4.** If F2 fails, write down the exact error. A likely one is that the portal gave the app read-only access to the file.
- [x] **F5. Original missing** (test item 4). Add another test file, then delete that original yourself in your file manager. Back in the app, **Move to Trash** is greyed out, with a note saying the original is no longer there.

## G. Export, import and readable copies (test items 11 and 12)
- [x] **G1.** **Export projects…**: no location is preset ("No location chosen yet"). **Choose…** opens your desktop's save dialog. Export as **ZIP** to your Documents folder. The ZIP opens in your archive manager, and the files are readable.
- [x] **G2.** The same with **TAR**.
- [x] **G3.** Export again with **Lock with a custom passphrase** ticked. A `.pjx` file is made.
- [x] **G4.** Look in the folder you exported to. Apart from the export itself, no leftover temporary file should be there.
- [x] **G5.** **Import a locked export**: pick the `.pjx` and enter its passphrase. The projects come in as copies. A wrong passphrase is refused.
- [x] **G6.** **Export a readable copy…** of one file: choose a location, and the copy appears there.
- [x] **G7.** **Cancel export** and **Cancel import** leave nothing behind.

## H. Settings
- [x] **H1. Change passphrase.** Lock the vault, then unlock it with the new passphrase. The old one is refused.
- [x] **H2. Allow copying passphrases.** With it switched **off**, Ctrl+C in a passphrase field copies nothing. Switched **on**, it copies.
- [x] **H3. Storage location → Move…** to a new folder you pick (for example `~/Documents/PJ test`). The move finishes. After a restart, the vault opens from the new place.
- [x] **H4.** **Light**, **Dark** and **System** themes all look right.
- [x] **H5.** **Show licenses** opens the list of licenses.
- [x] **H8. Temporary files.** Settings → Security → Temporary files → **Clear…** asks first, then says "Temporary files cleared." With a file open in another app, the confirmation says that file's copy is kept. Closing the window while editing asks you to save or discard first; otherwise the app closes at once.
- [x] **H7. Inbox.** After a J test, the inbox icon (next to the folder button) shows a red number. Opening it lists the notice, with an ✕ to dismiss it, and the number goes away. **Clear all** asks first.
- [x] **H6. Open vault folder.** On the home screen, the folder button (first icon in the top bar) opens your file manager at the vault's folder. You'll see only folders with long random names and a hidden `.pj` folder; nothing in it is readable.

## J. Pull the plug
These check that a crash or power cut never loses data or leaves a readable file behind. To "pull the plug", run `flatpak kill io.github.seven11ven.portfolio_jockey` in a terminal at the moment described. Then start the app again and unlock it.
- [x] **J1. Export.** Start an unlocked ZIP export of a project with a big file, and kill the app while it's still writing. After unlocking, a message says "An export was interrupted. Its unfinished file was removed." In the export folder, no hidden `.….tmp-…` file is left (`ls -la` shows hidden files).
- [x] **J2. Import.** Start importing a `.pjx` with several projects, and kill the app partway. After unlocking, a message says the import was undone, and none of its projects are in the list.
- [x] **J3. Storage move.** Start **Move…** to a new folder, and kill the app while it's copying. After restarting, your projects are all there, at the old location, and a message says the unfinished copy was removed. The new folder is empty.
- [x] **J4. Edit save.** Open a file with **Edit in another app**, change and save it in the editor, press **Save changes** and confirm, and kill the app right away. After unlocking, the file opens and shows either the old version or the new one, complete. Export it as a readable copy to be sure it isn't damaged.
- [x] **J5. Edit open.** Open a file with **Edit in another app**, make a change in the editor, and kill the app **without** saving in Portfolio Jockey. After unlocking, note what happens: either "An edit wasn't finished" is offered (save or discard), or a message says the edit's changes weren't saved. Either is fine; which one shows tells us how Flatpak treats the memory folder.

## I. Clean up
- [ ] **I1.** Remove the test data: `flatpak uninstall --user --delete-data io.github.seven11ven.portfolio_jockey`. Only do this if you won't keep using this build. It deletes the vault in the app's own data folder; a storage folder moved elsewhere (H3) stays.
- [ ] **I2.** Delete the test exports and the moved storage folder by hand.

---

## Results to send back

| Item | Pass / Fail | Notes (error text, what you expected) |
|---|---|---|
| A1–A6 | Pass | PM, 2026-10-23 |
| B1–B6 | Pass | PM, 2026-10-23 |
| C1–C5 | Pass | PM, 2026-10-23 |
| D1–D3 | Pass | PM, 2026-10-23 |
| D4–D7 | | (retest: now plays in the desktop's player) |
| E1–E8 | Pass | PM, 2026-10-23 |
| F1–F5 | Pass | PM, 2026-10-23 |
| G1–G7 | Pass | PM, 2026-10-23 |
| H1–H8 | Pass | PM, 2026-10-23 |
| J1–J5 | Pass | PM, 2026-10-23 |

Also include:
- your distribution and version (`cat /etc/os-release | head -3`)
- your desktop (GNOME, KDE, Cinnamon, COSMIC, …)
- whether you're on Wayland or X11 (`echo $XDG_SESSION_TYPE`)
- if anything failed: the app's output when started from a terminal (`flatpak run io.github.seven11ven.portfolio_jockey`)

**Before sending, read the output over.** It can contain your username and folder names. Remove anything you don't want shared.
