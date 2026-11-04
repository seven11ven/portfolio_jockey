# Debian packaging repair

**Time:** 2026-11-04 20:10 UTC
**Performed By:** Claude Opus 5.5 (Anthropic), in Claude Code
**Approved By:** Jay 3.20 (project manager)
**Backup:** `version-control/local-app/edit056-2026-11-04_before-debian-packaging-repair/`

## Why
A review of the 2026-11-03 Debian packaging found that `portfolio-jockey_0.1.0-1_amd64.deb` could not be installed on Debian 13 or Ubuntu 24.04. It depended on `libgtk-3-0`, `libglib2.0-0`, `libatk1.0-0` and `libpoppler-glib8`, which those releases renamed with a `t64` suffix, and the new packages do not Provide the old names. Other problems found:
- `libsodium23` only, although the app also loads `libsodium.so.26`
- a placeholder maintainer address on a domain the project doesn't own
- packaging of whatever was in `app/build/`, which put leftover `media_kit` and `wakelock_plus` folders in the package
- an absolute `/usr/bin` link
- no md5sums and no Installed-Size

## Changes
- **`packaging/debian/changelog` (new):** a Debian changelog. Its top entry (`0.1.0-2`) sets the package version and the maintainer (the GitHub noreply address, PM decision).
- **`packaging/debian/build.sh`:**
  - It takes no arguments and reads the version and maintainer from the changelog. It checks the version against `appVersion`.
  - It runs the lockdown and privacy checks, `flutter analyze` and `flutter test`, deletes `app/build` and makes a clean release build (`--no-tree-shake-icons`). It refuses to continue if the worktree changes during the build.
  - Dependencies: the four renamed libraries are listed as `<name>t64 | <name>`, plus `libpoppler-glib8t64 | libpoppler-glib8` and `libsodium23 | libsodium26`. The names were checked on packages.debian.org (trixie) and packages.ubuntu.com (noble) on 2026-11-04. Any dependency outside the reviewed list stops the build.
  - Package details: a relative `/usr/bin` link, `DEBIAN/md5sums`, `Installed-Size`, a longer description, and the source commit and SHA-256 in the build summary. The duplicate `chmod` is removed.
- **`packaging/debian/check.sh`:** it checks md5sums, Installed-Size and every `t64` alternative, and rejects a renamed library listed without its alternative.
- **`packaging/debian/portfolio-jockey.1`:** the `flatpak(1)` "see also" is removed and the date updated.
- **`project-changelog/2026-11-03/.md`:** renamed to `project-changelog/2026-11-03/local-app/debian-packaging.md`.
- **Guideline lists:** `linux_packaging.md` and `documentation.md` were added to `AGENTS.md`, `CLAUDE.md` and `GEMINI.md`. `.cursorrules` and `.github/copilot-instructions.md` already point to every guideline file. `CLAUDE.md` also gained a short "Debian package" note.
- **Dev container (untracked):** a stray `~/.dart-tool/CLIENT_ID` (created 2026-11-03 07:19 UTC) was deleted, and the lockdown check passes again. Telemetry reporting was off (`reporting=0`) and the event log was empty. Only the pinned SDK is on PATH; what created the ID is unknown.

## Verification
- `bash -n` passes on both scripts.
- **Dry run:** a scratchpad copy of `build.sh`, without the clean-tree check and the Flutter rebuild, packaged the existing release bundle. Both `check.sh` modes passed, and so did the Lintian gate: the two documented overrides and one expected warning (`shared-library-lacks-prerequisites` on Dart's `libapp.so`). The absolute-symlink and changelog warnings are gone.
- **Negative tests:** `check.sh` rejected a package missing the `libgtk-3-0t64` alternative and a package with a changed file (md5sums mismatch).

## Impacts and next steps
- The real `0.1.0-2` build has not been made yet. `build.sh` needs a clean, committed worktree, and the PM's uncommitted guideline edits are still pending.
- **Not yet verified:** a clean install and launch on Debian 12, Debian 13, Ubuntu 22.04 and Ubuntu 24.04. It needs a real machine or VM, because this Codespace can't run containers. Don't attach the .deb to the GitHub release until this passes.
- The old `0.1.0-1` package and logs in `project-builds/` (git-ignored) were left in place. Don't distribute them.

## Follow-up: build cache fix
**Time:** 2026-11-04 20:20 UTC
**Performed By:** Claude Opus 5.5 (Anthropic), in Claude Code
**Approved By:** Jay 3.20 (project manager)
**Backup:** `version-control/local-app/edit057-2026-11-04_before-build-cache-fix/`

- **What failed:** the first real run of `build.sh`. The checks and all 260 tests passed, but the release build failed. CMake could not find `app/build/native_assets/linux`.
- **Why:** `build.sh` deleted `app/build` but kept Flutter's build cache in `app/.dart_tool/flutter_build`. The cache treated the native-assets step as done and skipped it. The earlier packages only worked because of leftover files in `app/build`.
- **Fix:** `build.sh` now also deletes `app/.dart_tool/flutter_build`. `package_config.json` is kept, so no package download is needed.

## Release build 0.1.0-2
**Time:** 2026-11-04 20:27 UTC (built 2026-11-04 20:26 UTC)
**Performed By:** Claude Opus 5.5 (Anthropic), in Claude Code
**Approved By:** Jay 3.20 (project manager)

- `bash packaging/debian/build.sh` from commit `32fcd9d` built `project-builds/release-builds/portfolio-jockey_0.1.0-2_amd64.deb` (git-ignored), SHA-256 `2d3c8ce7515a00257f505fe813b152e6ecb04eb5f1c3795ab4fb7dcce23efdf3`.
- **Checks passed:** lockdown, privacy, analyze, all 260 tests, both `check.sh` modes, and the Lintian gate (two documented overrides; one expected warning on Dart's `libapp.so`).
- **No leftovers:** no `media_kit` or `wakelock_plus` files are in the package.
- **Still outstanding before release:** a clean install and launch on Debian 12, Debian 13, Ubuntu 22.04 and Ubuntu 24.04.
