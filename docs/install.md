# Installing Portfolio Jockey on Linux

Portfolio Jockey is offered as a single **`.flatpak` file**. Flatpak is a standard way to install desktop apps on Linux. It runs each app in a **sandbox**, walled off from the rest of your computer, and it works on any 64-bit desktop distribution. The supported systems are listed in [`public-notes/linux-support.md`](../public-notes/linux-support.md).

- **Processor:** x64 (Intel or AMD) only for now. ARM computers come later.
- **Price:** free and open source (`AGPL-3.0-or-later`).
- **Privacy:** the app has **no network access** at all, and no accounts, telemetry, analytics or crash reports.

## 1. Install Flatpak (once per computer)
Many distributions (Fedora, Linux Mint, Pop!_OS, elementary OS, …) already have it. Check with:

```sh
flatpak --version
```

If you get "command not found", on Ubuntu or Debian run the line below, then log out and back in once:

```sh
sudo apt install flatpak
```

For other distributions, see the official setup guide: <https://flathub.org/setup>.

## 2. Add Flathub (once per computer)
The app runs on the free **freedesktop runtime**, a shared set of system libraries that comes from Flathub. Add Flathub for your own user:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

## 3. Check the download
Each release publishes the SHA-256 checksum of its `.flatpak` file. A matching checksum shows the file arrived intact and unchanged. In the folder where you saved it, run:

```sh
sha256sum portfolio-jockey-0.1.0-x86_64.flatpak
```

The long string it prints must match the published one exactly. If it doesn't, delete the file and don't install it.

## 4. Install

```sh
flatpak install --user portfolio-jockey-0.1.0-x86_64.flatpak
```

Flatpak lists the permissions the app asks for, then installs. The first time, it also fetches the freedesktop runtime from Flathub. That's a few hundred MB, downloaded once and shared with other Flatpak apps.

Start **Portfolio Jockey** from your applications menu. If it isn't there after your first Flatpak install for your user, log out and back in once: the menu picks up per-user Flatpak apps at login. Or start it with:

```sh
flatpak run io.github.seven11ven.portfolio_jockey
```

## What the app may and may not do
You can check this yourself at any time:

```sh
flatpak info --show-permissions io.github.seven11ven.portfolio_jockey
```

- **Allowed:**
  - showing its window (Wayland, or X11 as a fallback)
  - using the graphics card, to draw its window
- **Not needed any more:** sound. Audio and video play in your desktop's own player, outside the app.
- **Not allowed:**
  - **the network**: the `shared=` line says `ipc` only, never `network`
  - **your files**: the app sees only the files and folders you pick in your desktop's own file dialogs
- **Original files:** inside the Flatpak, **Show original in file manager** uses the portal to reveal a picked original. Move it to Trash in the file manager, then delete the encrypted project copy separately in Portfolio Jockey.

## Licenses and source code
- **In the app:** Settings → "Show licenses" lists the licenses of Flutter and every package the app uses.
- **The libraries bundled in the Flatpak** (libsodium and Poppler) have their license texts installed with the app. You can list them with:
  `flatpak run --command=ls io.github.seven11ven.portfolio_jockey /app/share/licenses/io.github.seven11ven.portfolio_jockey`
- **Source code:** each release publishes two more files next to the `.flatpak`:
  - `portfolio-jockey-<version>-sources.flatpak`: the exact source of every bundled library
  - `portfolio-jockey-source-<version>.tar.gz`: the app's own source at the release's git tag

## Where your data lives
- **Your vault** (the encrypted projects) is in `~/.var/app/io.github.seven11ven.portfolio_jockey/data/Portfolio Jockey/`, unless you chose or moved it somewhere else in Settings → Storage location.
- **Settings** are in `~/.var/app/io.github.seven11ven.portfolio_jockey/config/`.
- Everything in the vault is encrypted with your passphrase. **There's no way to recover a forgotten passphrase.** To keep a backup, use **Export projects…**, either locked with a passphrase or as an ordinary ZIP or TAR.

## Temporary files
To preview audio and video, and to edit files in other apps, the app makes readable copies, kept in memory only (never on disk). They're cleared when the app opens and closes, and you can clear them yourself in Settings → Security → Temporary files. Flatpak can't run anything when an app is uninstalled, but there's nothing temporary on disk to remove; the memory folders are cleared when you log out or restart.

## Updating
Download the newer `.flatpak` file, check it as in step 3, and install it the same way. Your vault and settings are kept.

## Uninstalling
Uninstall the app but **keep** your vault and settings:

```sh
flatpak uninstall --user io.github.seven11ven.portfolio_jockey
```

Uninstall the app and **delete** its data folder, including the vault inside it (this can't be undone):

```sh
flatpak uninstall --user --delete-data io.github.seven11ven.portfolio_jockey
```

A storage location you moved outside the app's data folder isn't touched; delete it by hand if you want it gone. To remove runtimes no other app needs any more, run `flatpak uninstall --user --unused`.

## If something doesn't work
- **"Show original in file manager" fails in the Flatpak.** Your desktop needs its portal service: `xdg-desktop-portal` plus one for your desktop, such as `xdg-desktop-portal-gnome`, `-kde` or `-gtk`. Most desktops install them already. Install the missing one with your package manager and log in again. Move the original to Trash from the file manager; the app does not directly trash document-portal files.
- **Audio, video or "Edit in another app" refuses, saying no memory-only folder is available.** The app keeps the readable copies these need only in memory (`$XDG_RUNTIME_DIR`, a tmpfs), never on disk, and refuses rather than fall back to the disk. That folder exists on all normal desktop logins. It can be missing in unusual sessions, such as a root shell or some remote logins.
- **Play doesn't open anything, or opens the wrong app.** Audio and video play in your desktop's default app for that file type. Set one in your desktop's settings (for example "Preferred Applications" or "Default Applications"), then press Play again.
- **Something else.** Start the app from a terminal with `flatpak run io.github.seven11ven.portfolio_jockey` to see its messages. Before sharing them, remove anything personal, such as your username or folder names.

## Building it yourself
The packaging files are in [`packaging/flatpak/`](../packaging/flatpak/):
- `app/tool/package-bundle.sh` builds the app and a "build kit".
- The kit's `build.sh` builds and installs the Flatpak on your own computer, and makes the `.flatpak` file.
- `TESTING.md` is the checklist for testing a build.

Every library the Flatpak builds is pinned to a checked version, as recorded in [`docs/dependencies.md`](dependencies.md) ("Flatpak modules").
