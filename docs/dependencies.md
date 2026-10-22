# Dependencies: cost, license and telemetry

Every tool, package and service Portfolio Jockey uses is listed here. The project guidelines require each one to be:
- **free**, with no card or payment
- **checked for telemetry**, preferring privacy-respecting options
- **checked for security**

Each was checked on the provider's own site, documentation or source code. Update this file whenever a dependency is added, removed or upgraded.

Last reviewed: 2026-10-22 (app packages added in plan phase 3).

## Development tools (dev container)

| Tool | Version | License | Cost | Telemetry | How it's handled |
|---|---|---|---|---|---|
| Dev container base image `mcr.microsoft.com/devcontainers/base` | `2-bookworm` (Debian 12) | MIT (image definition); Debian packages under their own free licenses | Free | None found | n/a |
| Flutter SDK (includes the Dart SDK) | 3.47.7 stable (Dart 3.13.5), checksum-verified | BSD-3-Clause | Free | **Yes, opt-out.** The `flutter` and `dart` tools send Google Analytics usage events and crash reports by default ([Flutter docs](https://docs.flutter.dev/reference/crash-reporting)). Opting out with `--disable-analytics` sends one last "opt-out" event. | Blocked in three layers before the first run. See below. |
| Linux build packages: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libstdc++-12-dev` | Debian 12 versions | Free/open-source licenses (various) | Free | None | n/a |
| VS Code extensions `Dart-Code.dart-code`, `Dart-Code.flutter` | Latest | MIT | Free | **Yes, opt-out.** Sends some usage analytics, per its [README](https://github.com/Dart-Code/Dart-Code#analytics). | Off three ways (its source code checks each one): `DO_NOT_TRACK=1`, the Dart/Flutter opt-out file, and `dart.allowAnalytics: false`. See "Background services" below for the local ports it opens. |

**Not used:**
- **Android SDK.** The project manager declined Google's Android SDK License Agreement, so the Android port is on hold. No Android SDK or JDK is installed.
- **Playwright.** Its telemetry status couldn't be confirmed from an official source, so it was not installed.

### Background services the Dart extension starts
Checked in the extension's code (Dart-Code 3.144.0) on 2026-10-22. None of these is telemetry, and all of them stay on this machine.

| Service | Port | Starts automatically? |
|---|---|---|
| Analysis server (language server) | None: it talks to the editor directly, without a port | Yes. It's needed for errors, completion and lints in the editor. |
| Dart Tooling Daemon (DTD) | `127.0.0.1` only, random port | Yes. **There's no user setting to turn it off.** The extension disables it only for Bazel and Fuchsia workspaces, and the analysis server connects to it. |
| DevTools server | `127.0.0.1` only (was 9100) | **No.** `dart.shareDevToolsWithFlutter: false` in `devcontainer.json` stops it starting as soon as a Flutter project opens. It still starts on demand when you open DevTools while debugging. |

## How Flutter and Dart telemetry is blocked

These details were verified in the source code on 2026-10-22:
- `dart-lang/tools` → `pkgs/unified_analytics` (version 8.2.0)
- `flutter/flutter` → `packages/flutter_tools/lib/src/reporting/` on the stable branch

| Layer | What | Where |
|---|---|---|
| 1. Network | `www.google-analytics.com`, `ssl.google-analytics.com`, `region1.google-analytics.com`, `analytics.google.com` and `clients2.google.com` (Flutter crash reports) resolve to `0.0.0.0` / `::`. Re-applied on every container start. | `.devcontainer/lockdown.sh` |
| 2. Opt-out written before the first run | `~/.dart-tool/dart-flutter-telemetry.config` holds `reporting=0` before any tool runs, so no "first run" or opt-out event ever happens. The legacy opt-out files (`~/.flutter`, `~/.dart/dartdev.json`, `~/.flutter-devtools/.devtools`) are written too. | `.devcontainer/lockdown.sh` |
| 3. Environment | `FLUTTER_SUPPRESS_ANALYTICS=true`: the Flutter tool uses a no-op analytics object, and crash reports are gated on the same check. `DASH__SUPPRESS_ANALYTICS=true`: nothing is sent, not even the opt-out event. `DO_NOT_TRACK=1`: the Dart VS Code extension sets up no analytics. | `.devcontainer/devcontainer.json` (`containerEnv`) and shell profiles |
| 4. Removed from the source | The Flutter tool is patched so its analytics factory always returns the built-in no-op object and its crash reporter returns before sending. The tool is recompiled from the patched source. Tested with every other layer removed (an empty home folder and no variables): Flutter created no telemetry files at all. The `dart` command ships precompiled, so it can't be patched realistically. It relies on layers 1–3, which its source honours. | `.devcontainer/flutter-remove-telemetry.patch`, applied by `setup.sh` |
| Check | Fails if any layer is missing, if the patch isn't applied, or if a telemetry log or client ID exists. Runs on every container start. | `.devcontainer/check-lockdown.sh` |

**Upgrading Flutter:**
1. Don't use `flutter upgrade` or `flutter channel`. They would replace the patched source.
2. Change `FLUTTER_VERSION` and `FLUTTER_SHA256` in `setup.sh`, taking the checksum from Flutter's official release list.
3. Check that the patch still applies. `setup.sh` stops with an error if it doesn't.
4. Update this file.

**Still allowed (needed, and not telemetry):**
- Flutter downloads engine files and checks for updates from `storage.googleapis.com`.
- `flutter pub get` downloads packages from `pub.dev`. The `pub` client sends standard request headers. Every package is listed in the table above.
- Flutter's survey list is also hosted on `storage.googleapis.com`. It is only fetched when analytics are allowed to send, which never happens here.

## Your editor (one manual step)
VS Code's own telemetry can only be turned off in **your user settings**. Dev container settings can't change it.

In VS Code: **Settings** → search `telemetry.telemetryLevel` → set it to **off**. In Codespaces in a browser, do the same there; Settings Sync carries it across.

The hosting service you use (GitHub Codespaces, DevPod, Coder) has its own policies, which this repo can't control.

## App packages (`app/pubspec.lock`)

Each package's code was reviewed on 2026-10-22, as the Open Source and Privacy guideline requires. That means its downloaded source, not its web page. The exact versions are in `app/tool/allowed-packages.txt`.

The app's direct dependencies are `file_selector_linux` and `file_selector_platform_interface` (phase 5), `flutter_markdown_plus`, `media_kit`, `media_kit_video` and `wakelock_plus_platform_interface` (phase 6), and the dev-only `flutter_lints`. The packages in the first table come with the Flutter SDK, which pins their versions. `cupertino_icons`, an iOS icon font, isn't used; the `--empty` template leaves it out.

| Package(s) | Version | Ships in the app? | License (from its LICENSE file) | Cost | Code review |
|---|---|---|---|---|---|
| `flutter`, `sky_engine` (Flutter SDK) | Flutter 3.47.7 | Yes | BSD-3-Clause. `sky_engine`'s LICENSE also bundles the engine's third-party licenses | Free | No telemetry. The only network code is `NetworkImage` / `Image.network` / `NetworkAssetBundle`, which run only if app code calls them, and `check-privacy.sh` blocks that. The `analytics` hits are Material icon names. The `dart:js_interop` / `XMLHttpRequest` files are web-only and never compiled for Linux. `sky_engine` is the Dart standard library, which *defines* `dart:io`'s `HttpClient` but doesn't use it. |
| `characters`, `collection`, `meta` | 1.4.1, 1.19.1, 1.18.3 | Yes | BSD-3-Clause | Free | No network, telemetry or process code. |
| `material_color_utilities` | 0.13.0 | Yes | Apache-2.0 | Free | No network or telemetry code. Its only URL is in an error message. |
| `vector_math` | 2.4.0 | Yes | BSD-3-Clause | Free | No network or telemetry code. |
| `flutter_lints`, `lints` | 6.0.0, 6.1.0 | No (dev) | BSD-3-Clause | Free | Their `lib/` holds only YAML lint config, with no Dart code. `lints/tool/gen_docs.dart` downloads a rules file over HTTP, but it's a script for the package's maintainers. It's outside `lib/` and never runs here. |
| `flutter_test` (Flutter SDK) | Flutter 3.47.7 | No (dev) | BSD-3-Clause (Flutter repo) | Free | Its test binding **replaces `HttpClient` with a mock** that gives every request an empty 400 response, so tests can't reach the network. Its `fetch(` hits are web-only. |
| `leak_tracker`, `leak_tracker_flutter_testing`, `leak_tracker_testing` | 11.0.2, 3.0.10, 3.0.2 | No (dev) | BSD-3-Clause | Free | "Tracker" means memory leaks in tests, not users. **One finding:** if "retaining path" collection is turned on (`collectRetainingPathForNotGCed`, off by default), it starts the Dart VM's **local** debug server and connects to it. That's not telemetry, but it opens a local port, so `check-privacy.sh` fails if app code or tests turn it on. |
| `vm_service` | 15.4.0 | No (dev) | BSD-3-Clause | Free | The client for the Dart VM's local debug protocol (`WebSocket` in `vm_service_io.dart`). Only `leak_tracker`'s retaining-path code uses it, as above. |
| `async`, `boolean_selector`, `matcher`, `path`, `source_span`, `stack_trace`, `stream_channel`, `string_scanner`, `term_glyph`, `test_api` | see allowlist | No (dev) | BSD-3-Clause | Free | No network or telemetry code. `async`'s `fetch(` hit is an in-memory cache method. |
| `clock`, `fake_async` | 1.1.3, 1.3.3 | No (dev) | Apache-2.0 | Free | No network or telemetry code. |

### File picker (plan phase 5)

Reviewed on 2026-10-22, including the plugin's C++ code. The app depends on **only the Linux part** of the Flutter team's `file_selector`, not on the 6-platform umbrella package.

| Package | Version | Ships in the app? | License | Cost | Code review |
|---|---|---|---|---|---|
| `file_selector_linux` | 0.9.4+1 | Yes, Dart and C++ | BSD-3-Clause (flutter/packages) | Free | The C++ opens GTK's **native** file dialog (`GtkFileChooserNative`), which uses the desktop's file-dialog portal inside a Flatpak, and returns the chosen paths. There's no network, process, environment or file-writing code. Its build file downloads googletest from GitHub **only** when the plugin's own tests are switched on (`include_file_selector_linux_tests`). Our build never does that, and the package doesn't even ship those tests. |
| `file_selector_platform_interface` | 2.7.0 | Yes | BSD-3-Clause | Free | It's the shared interface. Its `web_helpers.dart` (`dart:html`) is never imported. **It lists the `http` networking package as a dependency but never uses it** (see below). |
| `cross_file` | 0.3.5+5 | Yes | BSD-3-Clause | Free | It picks its `dart:io` variant on Linux. The browser variant (`html.dart`) only compiles for web builds. |
| `plugin_platform_interface` | 2.1.8 | Yes | BSD-3-Clause | Free | A 127-line check that plugins are registered properly. |
| `web` | 1.1.1 | No: web builds only | BSD-3-Clause (dart-lang/web) | Free | Declarations of browser APIs, pulled in by `cross_file`'s browser variant, and never compiled into the Linux app. Its `amplitude` hit is an SVG filter attribute, not the analytics service. |

**`http` is replaced by an empty stand-in.** `file_selector_platform_interface` lists `http` (plus `http_parser` and `typed_data`) but never imports it. The project manager chose to keep all networking code out of the tree:
- `app/pubspec.yaml` overrides `http` with `app/tool/stubs/http/`, a package with **no code**: only a pubspec and a README.
- If anything ever imports `package:http`, the build fails instead of silently gaining network access.
- `check-privacy.sh` fails if the stand-in ever holds code or dependencies, or if a path dependency points anywhere else.

**How the review was done:**
1. Listed every file in each package.
2. Checked for native code and build hooks (`hook/build.dart`, which runs at build time). None were found.
3. Grepped the compiled code (`lib/`) for network APIs, telemetry and tracking words, process spawning and environment reads.
4. Read every hit.

The 22 hits that remain after the review are listed, with reasons, in `app/tool/reviewed-hits.txt`.

**Engine binary and Linux runner:**
- **Engine:** the Flutter engine ships as a precompiled library (`libflutter_linux_gtk.so`). Its C++ source isn't on this machine, so the binary was checked instead. The **release** engine links only to GTK, GLib, Cairo, Pango, fontconfig, epoxy and libc. There's no curl, libsoup or TLS library. It holds no telemetry or crash-reporting strings, and its only URLs are license text and error-message links.
- **Linux runner:** the generated runner (`app/linux/runner/`) was read in full. It creates a GTK window and registers no plugins. `g_application_register` uses D-Bus, the desktop's local message bus, not the network.

### Previews (plan phase 6)

Reviewed on 2026-10-22, including media_kit_video's C++ code (1,133 lines). Each package's `lib/` was grepped for file, process, socket, HTTP, native-library and environment code, and every hit was read. The 12 hits that remain are in `app/tool/reviewed-hits.txt`.

| Package(s) | Version | Ships in the app? | License | Cost | Code review |
|---|---|---|---|---|---|
| `flutter_markdown_plus` | 1.0.12 | Yes | BSD-3-Clause | Free | The maintained successor to the discontinued `flutter_markdown`. Its only I/O is the **default image builder**, which calls `Image.network` / `Image.file` / `Image.asset`. It runs only when no `imageBuilder` is given, and the app always gives one: it shows a placeholder instead. Links do nothing without `onTapLink`, which the app doesn't set. A widget test checks that no `Image` is built for a Markdown file's images. |
| `markdown`, `args` | 7.3.1, 2.7.0 | Yes | BSD-3-Clause | Free | Pure Dart parsers with no I/O. `markdown`'s `bin/` command-line tool (the only `dart:io` user, and the only user of `args`) isn't compiled into the app. |
| `media_kit` | 1.2.6 | Yes | MIT | Free | Dart bindings to the system **libmpv**. Four findings, each handled in `app/lib/ui/preview/preview_views.dart`: <br>1. **Temp files.** `Player.open()` always writes a playlist file holding the media's path to `/tmp` (deleted 5 s later, or never after a crash). `Media.memory()` writes the whole file to `/tmp`, and subtitle data tracks write temp files too. The app uses none of these: it loads the file with mpv's own `loadfile` command through `NativePlayer.command`. <br>2. **Network defaults.** It sets `cache-on-disk=yes`, and FFmpeg's protocol whitelist allows `http`, `https`, `tcp`, `udp`, `tls`, `rtp` and `crypto`. The app passes `protocolWhitelist: ['file']` and sets the mpv options listed under "Readable copies" below. <br>3. **Library lookup.** The `LIBMPV_LIBRARY_PATH` environment variable can point it at another library, so the app names `libmpv.so.2` explicitly. <br>4. **Options set before mpv starts:** only `vid`, so `load-scripts` can't be changed. mpv's source shows this is safe (see libmpv below). |
| `media_kit_video` | 2.0.1 | Yes, Dart and C++ | MIT | Free | Draws libmpv's video into a Flutter texture through mpv's render API (OpenGL via epoxy, or software). The C++ has no network, process, `getenv` or file code. It needs `wakelock_plus` (below), and only uses it when the `Video` widget's `wakelock` flag is on. The app passes `false`. |
| `media_kit_libs_linux` | — | **Not used** | MIT | — | Its CMake **downloads mimalloc from GitHub at build time**, checked only by MD5. The app doesn't depend on it. `app/linux/CMakeLists.txt` sets `MEDIA_KIT_LIBS_AVAILABLE` itself, and media_kit_video links the system libmpv through pkg-config. |
| `wakelock_plus`, `wakelock_plus_platform_interface` | 1.8.1, 1.7.0 | Yes (never active) | BSD-3-Clause | Free | On Linux it asks the desktop's Inhibit portal over **D-Bus** and reads the app name through `package_info_plus`. It's never enabled. As a second guard, the app registers a no-op wakelock before any player exists, so neither runs. |
| `dbus` | 0.8.0 | Yes (never connects) | MPL-2.0 (file-level copyleft, compatible with AGPL-3.0) | Free | Can reach a **TCP** bus if `DBUS_SESSION_BUS_ADDRESS` says `tcp:`, but `DBusClient` connects lazily on its first call, and the only caller is the wakelock above. Its server class is never created. |
| `package_info_plus` (+ `_platform_interface`) | 10.2.2, 4.1.0 | Yes (never called) | BSD-3-Clause | Free | On Linux, `getAll()` resolves `/proc/self/exe` and runs `stat` as a process. Only wakelock_plus calls it, as above. Its `package:http` hit is web-only code. |
| `posix`, `ffi` | 6.5.2, 2.2.0 | Yes | MIT, BSD-3-Clause | Free | libc bindings and `malloc` helpers (dbus uses `getuid`). |
| `image`, `archive`, `xml`, `petitparser` | 4.12.0, 4.5.2, 7.0.1, 7.0.2 | Yes | MIT | Free | Only media_kit's `screenshot()` uses `image`, and the app never calls it. Their file APIs run only when called. `image`'s hits are a WebP field named `amplitude` and a `dart:html` error string. |
| `safe_local_storage`, `uri_parser`, `uuid`, `synchronized`, `universal_platform` | 2.0.6, 3.0.2, 4.6.0, 3.5.0, 1.1.0 | Yes | MIT | Free | Helpers for media_kit's temporary files (never created by the app's usage), path parsing, IDs, locks and platform checks. There's no network code. |
| `crypto`, `typed_data`, `fixnum`, `flutter_web_plugins` | 3.0.7, 1.4.0, 1.1.1, SDK | Yes | BSD-3-Clause | Free | Pure Dart. `flutter_web_plugins` is only used by web builds. |
| `win32`, `ffi_leak_tracker` | 6.4.0, 0.1.2 | No: Windows only | BSD-3-Clause | Free | Never compiled into the Linux app. The `telemetry` hit is a Windows IOCTL constant name. |

## Native libraries

The vault calls these through Dart's built-in `dart:ffi`. That keeps the app free of extra pub packages. `app/tool/allowed-native-libs.txt` lists which file may load which library and which functions, and `check-privacy.sh` enforces it.

| Library | Version | License | Cost | Where it comes from | Code review |
|---|---|---|---|---|---|
| **libsodium** (the vault's cryptography) | 1.0.18 (Debian `libsodium23` 1.0.18-1+deb12u1). The app accepts 1.0.18 or newer, loading `libsodium.so.26` (1.0.19+) or `libsodium.so.23` (1.0.18) | ISC. In plain words: use, copy, change and share it for any purpose, free, as long as the copyright notice stays with it. No warranty | Free | Dev container: Debian's signed package. Release: bundled in the Flatpak, built from the official tarball after checking its signature (phase 8) | See below |
| **GLib / GIO** (`libgio-2.0.so.0`, `libgobject-2.0.so.0`, `libglib-2.0.so.0`) | The system's (Debian 12: 2.74), or the Flatpak runtime's | LGPL-2.1+ | Free | Already loaded by Flutter's GTK engine | The app binds only `g_file_new_for_path`, `g_file_trash`, `g_object_unref` and `g_error_free`, to move originals to the Trash. GIO's network functions stay out of reach. The code was reviewed in GLib's source (`gio/glocalfile.c`, `gio/gtrashportal.c`). Inside a Flatpak, `g_file_trash()` opens the file read/write and hands it to the Trash portal over the **session D-Bus** (local). Otherwise it moves the file into the freedesktop Trash (`~/.local/share/Trash` or `<drive>/.Trash-<uid>`) and writes a `.trashinfo`. Neither path uses the network or starts processes. |
| **GIO app info** (same libraries, `app/lib/services/native/gio_apps.dart`) | as above | LGPL-2.1+ | Free | as above | "Edit in another app" lists the apps for a file type (`g_content_type_guess` gets the file's **name only**, never its contents), then launches one with `g_app_info_launch`, or `g_app_info_launch_default_for_uri` when the desktop chooses. Reviewed in GLib 2.74.6's `gio/gappinfo.c` and `gio/gdesktopappinfo.c`: inside a Flatpak, the latter falls back to the **OpenURI portal**, which shows the desktop's app chooser. Each launch sends a local `org.gtk.gio.DesktopAppInfo.Launched` signal on the session D-Bus, with the app ID, its process ID and the file's URI. It never leaves the machine; desktops use it for "recent apps". 14 functions are allowed. |
| **Poppler** (`libpoppler-glib.so.8`) and **cairo** (`libcairo.so.2`) | Debian 12: 22.12.0, cairo 1.16 | Poppler "GPL-2 or GPL-3" (Debian's copyright file). The GPL-3 option is compatible with the app's AGPL-3.0. cairo: LGPL-2.1 or MPL-1.1 | Free | Dev container: Debian's `libpoppler-glib8` (installed by `setup.sh`). Release: decided in phase 8 | PDF previews are rendered **from memory**: `poppler_document_new_from_bytes` with `g_bytes_new_static` over a C buffer the app owns and wipes on close, then each page is drawn into a cairo image surface. Opening from a path or `GFile` is never bound (gvfs could fetch remote files). Poppler links Mozilla's NSS, but only for checking signed PDFs, and no signature, link, form or attachment function is bound. 20 functions are allowed. |
| **libmpv** (`libmpv.so.2`) and **epoxy** | Debian 12: mpv 0.35.1, epoxy 1.5.10 | mpv: LGPL-2.1+ for most files, with some GPL-2+ parts (Debian's copyright file), all compatible with AGPL-3.0. epoxy: MIT | Free | Dev container: `libmpv-dev`, `libepoxy-dev` (`setup.sh`). Release: decided in phase 8 | Loaded by media_kit (Dart FFI) and linked by media_kit_video's plugin. Reviewed in mpv 0.35.1's source (`etc/builtin.conf`, `options/path.c`, `player/scripting.c`, `demux/cache.c`). libmpv's built-in profile sets `config=no`, so the config folder is empty, and nothing from `~/.config/mpv` (config or scripts) is loaded. The built-in `ytdl_hook.lua` follows the `ytdl` option and unloads when it's set to `no`. Through FFmpeg, libmpv links gnutls, OpenSSL, libssh, SRT, libbluray, libcdio and libarchive. These are kept unreachable by the options under "Readable copies" below, by only ever opening plain file paths, and, in the Flatpak, by having no network permission. A test (`test/services/media_lockdown_test.dart`) checks that the real libmpv accepts every option and plays a local file. |
| **libc** (`libc.so.6`) | The system's | LGPL-2.1+ (glibc) | Free | Part of every Linux system | The app may bind only `malloc`, `free`, `open`, `fsync`, `close` and `mkdir` (phase 6, for the private 0700 folders), so libc's network functions stay out of reach. |

**libsodium review (2026-10-22):**
1. **Signature verified.** The official `libsodium-1.0.18.tar.gz` (SHA-256 `6f504490b342a4f8a4c4a02fc9b866cbef8622d5df4e5452b46be121e46636c1`) passed its minisign check, using the key `RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3`. The key was read from two separately hosted official sources: doc.libsodium.org and the `jedisct1/libsodium-doc` repository on GitHub.
2. **Source code.** All 106 C files were grepped and every hit was read. There is no network code, no process spawning, no environment reads and no printing or logging. Its only file access is reading `/dev/random` and `/dev/urandom`, as a fallback for randomness after the `getrandom` system call.
3. **The installed binary.** Debian's `libsodium.so.23` links only to libc, and imports only memory, locking, randomness and `open`/`read`/`poll`. There are no network imports. (Debian's package description says "Network communication…". That's libsodium's historical "NaCl" (Networking and Cryptography library) wording, not real network code.)
4. **Debian's patch.** `+deb12u1` backports the fix for CVE-2025-69277, an elliptic-curve point check the vault doesn't use.
5. **Bindings checked.** The app's bindings reproduce libsodium's own published test results: the XChaCha20-Poly1305 vector, and Argon2id vectors 0, 3 (an intentional refusal) and 4 from `test/default/`.

**Why not the `sodium` / `sodium_libs` packages:** `sodium_libs` is discontinued. Its successor, `sodium`, would add 12+ dependencies to review, plus a build hook that compiles a bundled libsodium on every build.

## Vault format

| File | Holds | Protection |
|---|---|---|
| `<root>/.pj/vault` (112 bytes) | Argon2id settings, salt, and the 256-bit master key | The master key is encrypted with XChaCha20-Poly1305 under a key derived from the passphrase with Argon2id: libsodium's MODERATE preset, 3 passes over 256 MiB, about 0.5 s on a 2-core cloud machine. The settings, salt and nonce are authenticated. Settings beyond 10 passes or 2 GiB are refused before any work is done. |
| `<root>/<id>/index.enc` | Project name, description, tags, file list, and each file's own key | XChaCha20-Poly1305 under the master key. The project ID is authenticated, so indexes can't be swapped between projects. |
| `<root>/<id>/blobs/<id>.enc`, `cover.enc` | File contents | libsodium secretstream (XChaCha20-Poly1305) in 64 KiB chunks, each file with its own random key. Changed, reordered, dropped or extra chunks are detected, and so is a file cut short. |

- **Folder and file names** are random 128-bit IDs, so they reveal nothing about the contents.
- **Every write** goes to a temporary file, is flushed, and is then renamed into place, so a crash can't leave a half-written file.
- **In memory:** keys and the passphrase are held in libsodium's guarded memory, which is locked against reading except while in use, and wiped when freed.
- **Known limits:**
  - A Dart `String` can't be wiped, so the typed passphrase exists briefly as a string.
  - While a project is open, its decrypted names and per-file keys are in Dart's normal memory. The master key never is.
  - Decrypting a file streams it, so if a file turns out to be damaged, the earlier chunks have already been delivered. Callers must discard everything from a stream that ends in an error.

## Readable copies (plan phase 6)

- **Previews:**
  - Images, text, Markdown and PDF are decrypted **fully into memory** before anything is shown, so a damaged file shows nothing. The limits are 200 MB, 5 MB, 5 MB and 200 MB.
  - The bytes are zeroed when the preview closes, and the decoded image is evicted from Flutter's image cache.
- **Audio, video and "Edit in another app"** need a real file. It's put in a private memory-only folder: `$XDG_RUNTIME_DIR/portfolio_jockey/<view|edit>-<random>/`.
  - **Creation:** the folder is made with mode 0700 by libc's `mkdir`.
  - **Checks:** the app refuses, and writes nothing, unless `$XDG_RUNTIME_DIR` is set, has no group or other permissions, isn't a link, and is on tmpfs or ramfs according to `/proc/self/mountinfo`.
  - **Wiping:** every file in the folder (including editors' backups and lock files) is overwritten with zeros and deleted. Links are deleted, never followed.
  - **Media copies** are wiped when the preview closes, at lock and at unlock.
- **Edits:**
  - Only one at a time.
  - **Save** compares the copy with the stored version, then re-encrypts it into the same blob with the file's key, atomically.
  - **Discard** asks first.
  - **Locking** waits until the edit is saved or discarded.
  - **Crashes:** an edit left by a crash is found at the next unlock through its `session.json`, and the user chooses to save or discard it.
- **mpv options the app sets** (media_kit's defaults differ):

  | Option | Value | Why |
  |---|---|---|
  | FFmpeg protocol whitelist | `file` | No `http`, `https`, `tcp`, `udp`, `tls`, `rtp` or `crypto` |
  | `stream-lavf-o` | `protocol_whitelist=[file]` | The same, for streams mpv opens through FFmpeg |
  | `cache-on-disk` | `no` | Keep the cache in memory (newer mpv versions default `cache-dir` to `~/.cache/mpv`) |
  | `ytdl` | `no` | Unload the youtube-dl script |
  | `access-references` | `no` | Don't follow references to other files inside media files |
  | `load-unsafe-playlists` | `no` | Don't load unsafe playlist entries |
  | `sub-auto` | `no` | Don't look for subtitles next to the copy |
  | `cover-art-auto` | `no` | Don't look for cover images next to the copy |
  | `save-position-on-quit` | `no` | Don't write "watch later" files |

- **Known limits:**
  - **Swap:** memory-only folders can still be written to swap if the system has swap and it isn't encrypted.
  - **The other app's own copies:** while editing, the other app has the readable file and may keep its own copies (recent files, autosave, backups) elsewhere. The confirmation says so inside a Flatpak, where the app is chosen by the desktop.
  - **Text in Dart memory:** the text of a text or Markdown preview lives in a Dart `String`, which can't be wiped.
  - **Large videos:** the tmpfs size (often 10% of RAM for `/run/user/<uid>`) limits how large a video can be played.
  - **Images during decoding:** Flutter's decoded image and Poppler's own parsing buffers can't be wiped by the app.
  - **The "Launched" message:** GIO's launch signal carries the copy's path on the local session bus.

## The app itself
- **`bash app/tool/check-privacy.sh`** must pass after every `flutter pub get` and before every commit. It fails if:
  1. a package isn't in `app/tool/allowed-packages.txt` at its exact version, or comes from anywhere but pub.dev, the Flutter SDK or an empty stand-in in `app/tool/stubs/`
  2. a package name matches a known network, analytics or crash-reporting package (even if allowlisted)
  3. the app's own code (`app/lib`, `app/test`) uses network APIs, telemetry markers or leak_tracker's retaining-path switch
  4. the Linux runner (`app/linux`) uses network libraries (curl, libsoup, sockets)
  5. any package's code (its Dart `lib/`, build `hook/` and, for plugins, the C/C++ in `linux/`) has a network, telemetry or build-time download (`FetchContent`) hit that isn't in `app/tool/reviewed-hits.txt` **for that exact version**, so upgrading a package forces a fresh review
  6. native code loads a library or function that isn't in `app/tool/allowed-native-libs.txt`, uses a name that isn't a plain string (so it can't be checked), or looks up symbols without naming a library
- Tested against deliberately broken copies: an injected and allowlisted `http` package, `HttpClient` in `lib/`, an unlisted version, an allowlisted package containing a Google Analytics URL, an upgraded `vm_service`, retaining paths turned on in a test, curl and libsoup in the runner, and a package from another server. Each one failed the check. For check 6, these also failed: opening libcurl from a new file or from the libsodium bindings, binding libc's `socket`, a library or function name that isn't a plain string, and `DynamicLibrary.process()`. For phase 5: curl in the plugin's C++, code or a dependency added to the `http` stand-in, a path dependency outside `tool/stubs/`, and `FetchContent` in the app's Linux build. For phase 6: binding `poppler_document_new_from_file` in the Poppler bindings, and binding `g_socket_client_new` in the GIO app-info bindings.
- **Limits:** it scans source that pub downloaded and verified by checksum into `~/.pub-cache`. It can't see inside the precompiled Flutter engine (see above). Renamed or obfuscated network calls would need a human review, which is why every new package also gets one.
- **The Linux release** will be a Flatpak with no network permission (phase 8).

**Adding or upgrading a package:**
1. Check its license and cost, and read its code.
2. Run `bash app/tool/check-privacy.sh --list-hits` and read every hit for that package.
3. Add the package to `allowed-packages.txt`, add the reviewed hits with reasons to `reviewed-hits.txt`, and update this table.
