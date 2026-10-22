# Flutter toolchain and telemetry lockdown (plan phase 2)

**Date:** 2026-10-22
**Time:** 2026-10-22 13:50 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Decisions made during this phase
- **Linux only; the Android port is on hold.** The project manager read a summary of Google's Android SDK License Agreement (April 28, 2026) and declined it for now. The concerns were the indemnity clause, Google's one-sided control, the usage-statistics terms, and the restrictions. No Android SDK or JDK is installed.
  - Plan phases affected: phase 3 creates only the Linux platform. The Kotlin bridge in phases 5–6 is postponed. Phase 8 packages for Linux only.
  - The approved mockups keep their phone layouts for a future port.
  - The details and options to research later are in the project manager's local notes (`project-notes/`, which Git ignores).
- **Telemetry removed from Flutter's source, not only switched off.** The project manager asked for this as an extra layer.

## Change
- **`.devcontainer/devcontainer.json`:**
  - Image changed to `mcr.microsoft.com/devcontainers/base:2-bookworm` (same Debian 12, without Node). The tag was confirmed in the registry. The user is now `vscode`.
  - `containerEnv` sets `FLUTTER_SUPPRESS_ANALYTICS=true`, `DASH__SUPPRESS_ANALYTICS=true` and `DO_NOT_TRACK=1`, and Flutter is added to `PATH`.
  - `postCreateCommand` runs `setup.sh`. `postStartCommand` re-applies `lockdown.sh` and runs `check-lockdown.sh` on every start.
  - Recommends the Dart and Flutter VS Code extensions, with `dart.allowAnalytics: false`.
- **`.devcontainer/lockdown.sh` (new):** blocks the telemetry hosts in `/etc/hosts` (IPv4 and IPv6). Writes the Dart/Flutter opt-out config (`reporting=0`) and the three legacy opt-out files **before any Dart or Flutter tool runs**, so no first-run or opt-out event can happen. Adds the suppression variables to shell profiles.
- **`.devcontainer/setup.sh` (new):** runs the lockdown first, then:
  - installs the Linux build packages listed in Flutter's docs
  - downloads Flutter **3.47.7** stable (released 2026-10-08), checking its SHA-256 against Flutter's official release list before unpacking
  - applies the telemetry patch and forces the tool to recompile
  - turns on only the Linux desktop target
  - ends with the lockdown check

  It's safe to re-run, and stops with an error if the patch doesn't apply.
- **`.devcontainer/flutter-remove-telemetry.patch` (new):** two small changes in `packages/flutter_tools/lib/src/reporting/`. `getAnalytics()` always returns `NoOpAnalytics`, except for Flutter's own test fake. `CrashReportSender.sendReport()` returns immediately.
- **`.devcontainer/check-lockdown.sh` (new):** checks every layer and fails, naming the problem, if any is missing:
  - the blocked hosts
  - the opt-out config and the legacy files
  - the three variables
  - that the patch is applied
  - that there's no telemetry log and no client ID
- **`docs/dependencies.md` (new):** license, cost and telemetry for every tool, the sources checked, the five layers, the one manual editor step (VS Code's own telemetry can only be turned off in user settings), and how to upgrade Flutter safely.
- **`.gitignore`:** removed the leftover Next.js, Vercel, Node and Yarn entries. Added Flutter and Dart build output, `.dart_tool/`, the plugin files, IDE files, `*.log`, and signing keys (`*.jks`, `*.keystore`, `key.properties`, `local.properties`) so keys can never be committed. No tracked file became ignored.

## Research behind it
All of this was checked in source code rather than docs or summaries:
- **`dart-lang/tools` → `unified_analytics` 8.2.0:**
  - the endpoint `www.google-analytics.com/mp/collect`
  - the config file, its `reporting=0` format and the legacy opt-out files
  - `DASH__SUPPRESS_ANALYTICS`, which suppresses even the opt-out event
  - a plain `--disable-analytics` sends a final opt-out event, which is why it's avoided
- **Flutter `flutter_tools` (stable):** `FLUTTER_SUPPRESS_ANALYTICS` returns a no-op analytics object. Crash reports go to `clients2.google.com/cr/report`, gated on the same check.
- **Dart-Code `analytics.ts`:** the extension stays off with `DO_NOT_TRACK=1` or `reporting=0`.
- **Android build tools:** their analytics settings file isn't documented in any source found, so no unverified file was written. This no longer matters, because Android isn't installed.

## Version control
- Backed up the previous `devcontainer.json` and `.gitignore` to `version-control/local-app/2026-10-22_before-flutter-toolchain/`. No secrets.

## Verification (in this Codespace)
- `setup.sh` ran end to end with exit code 0. The checksum matched (`flutter_linux_3.47.7-stable.tar.xz: OK`), and Flutter reports 3.47.7, Dart 3.13.5.
- **Patch test:** Flutter ran with every other layer removed (an empty home folder and no suppression variables). It created **no** `.dart-tool` folder, so no telemetry config, client ID or log. The only file it wrote was its local `tool_state`.
- Re-running `setup.sh` skips the download and the patch ("already installed" / "already applied"), and adds no duplicate `/etc/hosts` lines (10 lines: 5 hosts × IPv4/IPv6).
- `check-lockdown.sh`: all 15 checks pass.
- `flutter doctor`: no issues. Its `eglinfo` note is about graphics driver info in a container without a screen.
- After setup, the patch test and `flutter doctor`, `~/.dart-tool` holds only the pre-written opt-out file.
- No ports or servers were left running.

## Not verifiable here
- A fresh dev container build from this config (new image, `vscode` user, `containerEnv`). It's only exercised the next time a container is created. The same scripts were run in this Codespace, which still uses the old image until it's rebuilt.
- User namespaces aren't allowed in Codespaces, so a no-network sandbox for builds (`unshare`, `bubblewrap`) isn't possible here. It would be possible on a local Linux machine.

## Impacts
- **Any new dev container gets a pinned, patched, telemetry-locked Flutter for Linux desktop.**
- Flutter must be upgraded through `setup.sh`, never `flutter upgrade`. See `docs/dependencies.md`.
- **Manual step for the project manager:** set `telemetry.telemetryLevel` to `off` in VS Code user settings.
- Installed tools live outside the repo (`~/flutter`), so nothing large is committed.
