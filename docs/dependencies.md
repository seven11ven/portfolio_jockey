# Dependencies: cost, license and telemetry

Every tool, package and service Portfolio Jockey uses is listed here. The project guidelines require each one to be:
- **free**, with no card or payment
- **checked for telemetry**, preferring privacy-respecting options
- **checked for security**

Each was checked on the provider's own site, documentation or source code. Update this file whenever a dependency is added, removed or upgraded.

Last reviewed: 2026-10-22.

## Development tools (dev container)

| Tool | Version | License | Cost | Telemetry | How it's handled |
|---|---|---|---|---|---|
| Dev container base image `mcr.microsoft.com/devcontainers/base` | `2-bookworm` (Debian 12) | MIT (image definition); Debian packages under their own free licenses | Free | None found | n/a |
| Flutter SDK (includes the Dart SDK) | 3.47.7 stable (Dart 3.13.5), checksum-verified | BSD-3-Clause | Free | **Yes, opt-out.** The `flutter` and `dart` tools send Google Analytics usage events and crash reports by default ([Flutter docs](https://docs.flutter.dev/reference/crash-reporting)). Opting out with `--disable-analytics` sends one last "opt-out" event. | Blocked in three layers before the first run. See below. |
| Linux build packages: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libstdc++-12-dev` | Debian 12 versions | Free/open-source licenses (various) | Free | None | n/a |
| VS Code extensions `Dart-Code.dart-code`, `Dart-Code.flutter` | Latest | MIT | Free | **Yes, opt-out.** Sends some usage analytics, per its [README](https://github.com/Dart-Code/Dart-Code#analytics). | Off three ways (its source code checks each one): `DO_NOT_TRACK=1`, the Dart/Flutter opt-out file, and `dart.allowAnalytics: false`. |

**Not used:**
- **Android SDK.** The project manager declined Google's Android SDK License Agreement, so the Android port is on hold. No Android SDK or JDK is installed.
- **Playwright.** Its telemetry status couldn't be confirmed from an official source, so it was not installed.

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

## The app itself (from plan phase 3)
These are enforced once the app exists:
- **No network or analytics packages** in the dependency tree. `tool/check-privacy.sh` will fail the build if any appear.
- **The Linux release** is a Flatpak with no network permission.
