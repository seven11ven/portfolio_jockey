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

- [ ] **A1. No network permission.**
      `flatpak info --show-permissions io.github.seven11ven.portfolio_jockey`
      Under `[Context]`, the `shared=` line must say `ipc` only. It must **not** say `network`.
- [ ] **A2. No network inside the sandbox.**
      `flatpak run --command=sh io.github.seven11ven.portfolio_jockey -c 'cat /proc/net/dev'`
      Only the `lo` line (loopback, the PC talking to itself) should be listed. No `eth0`, `wlan0`, `enp…` or `wlp…`.
- [ ] **A3. The memory-only folder is tmpfs and private.**
      `flatpak run --command=sh io.github.seven11ven.portfolio_jockey -c 'stat -f -c %T "$XDG_RUNTIME_DIR"; stat -c %a "$XDG_RUNTIME_DIR"'`
      The first line should say `tmpfs`, and the second `700`.
- [ ] **A4. The video codecs are installed.**
      `flatpak list --runtime | grep -i codecs-extra`
      There should be one line with `org.freedesktop.Platform.codecs-extra`.
- [ ] **A5. The app is in the menu,** with the stacked-cards icon and the name "Portfolio Jockey". If it's missing after your first install, log out and back in once, then check again. The menu only finds apps installed for your user after Flatpak has set that up at login. Only count it as a fail if it's still missing after that.

- [ ] **A6. License files are installed.**
      `flatpak run --command=ls io.github.seven11ven.portfolio_jockey /app/share/licenses/io.github.seven11ven.portfolio_jockey`
      It should list `libass  libmpv  libplacebo  libsodium  poppler  portfolio_jockey`.

## B. First run and unlocking
- [ ] **B1.** Start the app from the menu. The first-run screen appears.
- [ ] **B2. Storage default.** The suggested storage location is inside the app's own data folder (`~/.var/app/io.github.seven11ven.portfolio_jockey/data/Portfolio Jockey`), with a note saying why.
- [ ] **B3. Passphrase field.** It's hidden as you type, and the eye button shows and hides it. The "Confirm" field only appears once the strength reaches **Fair**.
- [ ] **B4.** Click **Create vault**. The home screen appears.
- [ ] **B5. Storage folder survives a restart** (test item 5). Close the app, start it again, and unlock with your passphrase. Your vault is still there.
- [ ] **B6.** A wrong passphrase is refused with a clear message.

## C. Projects and files
- [ ] **C1.** Click **New project**, give it a name and description, and confirm. It appears in the list.
- [ ] **C2. Adding files through the portal** (test item 1). Open the project and click **Add files**. Pick a few test files from your home folder. The file dialog is your desktop's own. Confirm **Encrypt and add**. The files appear.
- [ ] **C3. Real location, not the portal path** (test item 3). Open a file's details (**Preview**). Its "Original" line shows the real place, for example `/home/<you>/Pictures/photo.jpg`, **not** `/run/user/…/doc/…`.
- [ ] **C4. Still works after a restart** (test item 1). Close and reopen the app, unlock, and open the same file's details. The real location still shows.
- [ ] **C5.** **Rename**, **Edit tags…**, **Change cover art and description**, and **Delete from project** each work. Their **Cancel** changes nothing.

## D. Previews
Open each type by **clicking it once** (right-click or a long press opens the file's menu). Audio and video open **paused**: press Play.
- [ ] **D1.** An image (zoom in and out).
- [ ] **D2.** A text file and a Markdown file.
- [ ] **D3.** A PDF (go to the next and previous page).
- [ ] **D4. Audio** (test item 10). It plays through your speakers.
- [ ] **D5. Video** (test items 9 and 10). An MP4 (H.264) plays, with sound. If you have one, try a WebM too. Then close the preview **while it's playing**, a few times. The app must stay responsive every time; it must not freeze or show "not responding". Do the same with an audio file. Open and close audio and video **10 times** in a row: a preview must never stay stuck on a spinner. If one ever does, it should say "The player stopped responding" within a few seconds; note that, and send the terminal output.
- [ ] **D5b. Play on a second file.** Close a video, open another one (or the same again), and press Play once. It must start on the first click.
- [ ] **D5c. Memory levels off.** Open your system monitor, find Portfolio Jockey, and note its memory. Open and close a video 15–20 times. Memory may rise for the first few, then should level off (it was measured flat at about 350–415 MB here). Note the first and last numbers.
- [ ] **D6. Readable copies are cleaned up.** This looks inside the running app, so keep it open.
      1. Find the app's instance number: `flatpak ps --columns=instance,application`
      2. With a video preview **open**, run `flatpak enter <instance> sh -c 'ls -la "$XDG_RUNTIME_DIR/portfolio_jockey"'`. A readable copy should be listed.
      3. Close the preview and run the same command again. The copy should be gone: the folder is empty, or "No such file or directory".
      If `flatpak enter` asks for permission, add `sudo` in front of it.
      **Edit copies** ("Edit in another app") are in the shared memory folder instead: `ls -la /run/user/$(id -u)/app/io.github.seven11ven.portfolio_jockey/portfolio_jockey/` shows an `edit-…` folder while an edit is open, and nothing after Save or Discard.
- [ ] **D7. Hardware decoding.** Settings → Video playback → Hardware decoding is on by default. Play a large video (1080p or bigger) and note how smooth it is, and the app's CPU use in your system monitor. Then turn Hardware decoding off, close and reopen the video, and compare (the setting applies to the next video you open). Note anything that looks wrong with it on (glitches or wrong colours).

## E. "Edit in another app" (test item 8)
- [ ] **E1.** On a text file, choose **Edit in another app…**, then **Open**. Your desktop's "Open With…" chooser appears **every time**, even if you picked an app before. Pick a text editor. If nothing appears, or the app shows an error, note the exact message.
- [ ] **E2.** The editor opens the file and **can save it**. Make a small change and save. If the editor says the file is read-only, note the exact message.
- [ ] **E3.** Back in Portfolio Jockey, the edit banner shows. **Save changes…** stores the edit, and the preview shows the new text.
- [ ] **E4.** Repeat with **Discard…**: the project copy stays as it was.
- [ ] **E5.** Try an image editor such as GIMP, if you have one. Some editors save by replacing the file; check that the edit still arrives.
- [ ] **E6. Saving too early.** In the editor, start saving a large change, and press **Save changes** in Portfolio Jockey right away. If the editor is still writing, the app says "The other app is still saving this file…" and writes nothing. **Try again** then works.
- [ ] **E7. Empty file.** In the editor, delete all the text and save. **Save changes** shows "The edited copy is empty" and only saves after **Save the empty file**. Cancel keeps the old version.
- [ ] **E8. Save As.** In the editor, use **Save As** to a different place, then **Save changes** in the app. It says there are no changes and that the editor may have saved to a different place.

## F. Moving originals to the Trash (test items 2, 4, 6)
- [ ] **F1.** On a file you added, open the menu and choose **Move to Trash**. The dialog shows the **real** location (not a portal path). Cancel changes nothing.
- [ ] **F2.** Confirm. The app says the original was moved to the Trash, and the project copy stays.
- [ ] **F3.** Open your desktop's Trash. The file is there and can be **restored** to where it was.
- [ ] **F4.** If F2 fails, write down the exact error. A likely one is that the portal gave the app read-only access to the file.
- [ ] **F5. Original missing** (test item 4). Add another test file, then delete that original yourself in your file manager. Back in the app, **Move to Trash** is greyed out, with a note saying the original is no longer there.

## G. Export, import and readable copies (test items 11 and 12)
- [ ] **G1.** **Export projects…**: no location is preset ("No location chosen yet"). **Choose…** opens your desktop's save dialog. Export as **ZIP** to your Documents folder. The ZIP opens in your archive manager, and the files are readable.
- [ ] **G2.** The same with **TAR**.
- [ ] **G3.** Export again with **Lock with a custom passphrase** ticked. A `.pjx` file is made.
- [ ] **G4.** Look in the folder you exported to. Apart from the export itself, no leftover temporary file should be there.
- [ ] **G5.** **Import a locked export**: pick the `.pjx` and enter its passphrase. The projects come in as copies. A wrong passphrase is refused.
- [ ] **G6.** **Export a readable copy…** of one file: choose a location, and the copy appears there.
- [ ] **G7.** **Cancel export** and **Cancel import** leave nothing behind.

## H. Settings
- [ ] **H1. Change passphrase.** Lock the vault, then unlock it with the new passphrase. The old one is refused.
- [ ] **H2. Allow copying passphrases.** With it switched **off**, Ctrl+C in a passphrase field copies nothing. Switched **on**, it copies.
- [ ] **H3. Storage location → Move…** to a new folder you pick (for example `~/Documents/PJ test`). The move finishes. After a restart, the vault opens from the new place.
- [ ] **H4.** **Light**, **Dark** and **System** themes all look right.
- [ ] **H5.** **Show licenses** opens the list of licenses.
- [ ] **H8. Temporary files.** Settings → Security → Temporary files → **Clear…** asks first, then says "Temporary files cleared." With a file open in another app, the confirmation says that file's copy is kept. Closing the window while editing asks you to save or discard first; otherwise the app closes at once.
- [ ] **H7. Inbox.** After a J test, the inbox icon (next to the folder button) shows a red number. Opening it lists the notice, with an ✕ to dismiss it, and the number goes away. **Clear all** asks first.
- [ ] **H6. Open vault folder.** On the home screen, the folder button (first icon in the top bar) opens your file manager at the vault's folder. You'll see only folders with long random names and a hidden `.pj` folder; nothing in it is readable.

## J. Pull the plug
These check that a crash or power cut never loses data or leaves a readable file behind. To "pull the plug", run `flatpak kill io.github.seven11ven.portfolio_jockey` in a terminal at the moment described. Then start the app again and unlock it.
- [ ] **J1. Export.** Start an unlocked ZIP export of a project with a big file, and kill the app while it's still writing. After unlocking, a message says "An export was interrupted. Its unfinished file was removed." In the export folder, no hidden `.….tmp-…` file is left (`ls -la` shows hidden files).
- [ ] **J2. Import.** Start importing a `.pjx` with several projects, and kill the app partway. After unlocking, a message says the import was undone, and none of its projects are in the list.
- [ ] **J3. Storage move.** Start **Move…** to a new folder, and kill the app while it's copying. After restarting, your projects are all there, at the old location, and a message says the unfinished copy was removed. The new folder is empty.
- [ ] **J4. Edit save.** Open a file with **Edit in another app**, change and save it in the editor, press **Save changes** and confirm, and kill the app right away. After unlocking, the file opens and shows either the old version or the new one, complete. Export it as a readable copy to be sure it isn't damaged.
- [ ] **J5. Edit open.** Open a file with **Edit in another app**, make a change in the editor, and kill the app **without** saving in Portfolio Jockey. After unlocking, note what happens: either "An edit wasn't finished" is offered (save or discard), or a message says the edit's changes weren't saved. Either is fine; which one shows tells us how Flatpak treats the memory folder.

## I. Clean up
- [ ] **I1.** Remove the test data: `flatpak uninstall --user --delete-data io.github.seven11ven.portfolio_jockey`. Only do this if you won't keep using this build. It deletes the vault in the app's own data folder; a storage folder moved elsewhere (H3) stays.
- [ ] **I2.** Delete the test exports and the moved storage folder by hand.

---

## Results to send back

| Item | Pass / Fail | Notes (error text, what you expected) |
|---|---|---|
| A1–A6 | | |
| B1–B6 | | |
| C1–C5 | | |
| D1–D7 | | |
| E1–E8 | | |
| F1–F5 | | |
| G1–G7 | | |
| H1–H8 | | |
| J1–J5 | | |

Also include:
- your distribution and version (`cat /etc/os-release | head -3`)
- your desktop (GNOME, KDE, Cinnamon, COSMIC, …)
- whether you're on Wayland or X11 (`echo $XDG_SESSION_TYPE`)
- if anything failed: the app's output when started from a terminal (`flatpak run io.github.seven11ven.portfolio_jockey`)

**Before sending, read the output over.** It can contain your username and folder names. Remove anything you don't want shared.
