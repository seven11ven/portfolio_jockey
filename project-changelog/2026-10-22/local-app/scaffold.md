# Flutter app scaffold (plan phase 3)

**Date:** 2026-10-22
**Time:** 2026-10-22 14:10–14:17 UTC
**Performed by:** Claude Code
**Approved by:** project manager

## Decisions made during this phase
- **The app lives in `app/`,** separate from the docs, notes and guidelines.
- **App ID: `io.github.seven11ven.portfolio_jockey`.** It meets Flathub's rules for code-hosting IDs, checked on Flathub's requirements page:
  - It has 4 parts.
  - It maps to the repo's URL, `github.com/seven11ven/portfolio_jockey`.

  `io.github.pjockey` was considered. Flathub requires at least 4 parts, and the second part must be the GitHub account that hosts the repo.
- **Lints:** the first-party `flutter_lints`, plus the analyzer's strict modes and extra rules. No third-party lint package.
- **Linux only.** The approved plan's Android platform and Android manifest check are left out, because the Android port is on hold.
- **New guideline applied:** the project manager added "examine the code, never take it at face value" (see `guideline-code-review-rule.md`). Every package's code was reviewed, and the review is enforced by the privacy check.

## Change
- **`app/` (new)**, created with `flutter create --empty --platforms=linux --org io.github.seven11ven --project-name portfolio_jockey`:
  - `pubspec.yaml`: `publish_to: 'none'`, version `0.1.0+1`, and one dev dependency, `flutter_lints`. `pubspec.lock` is committed.
  - `lib/main.dart`: a placeholder screen showing "Portfolio Jockey". It is **not** a designed UI; phase 5 builds the approved mockups.
  - `test/app_test.dart`: a widget test that the app starts and shows its name.
  - `analysis_options.yaml`: `strict-casts`, `strict-inference` and `strict-raw-types`, plus 21 extra rules (safe futures and streams, error handling, no dynamic calls, imports and style).
  - `linux/`: the generated GTK runner. The window title is set to "Portfolio Jockey".
  - **Removed** from the generated files:
    - the nested `app/.gitignore` and `app/linux/.gitignore` (one root `.gitignore` only)
    - `app/README.md`
    - `app/portfolio_jockey.iml` and `app/.idea/`
- **`app/tool/check-privacy.sh` (new):**
  - an allowlist of packages at exact versions
  - a blocklist of known network, analytics and crash-reporting packages
  - network-API scans of `app/lib`, `app/test` and `app/linux`
  - a scan of every dependency's code. Each hit must be reviewed for that exact package version.
- **`app/tool/allowed-packages.txt` and `app/tool/reviewed-hits.txt` (new):** 26 packages and 22 reviewed hits, each with a reason.
- **`.gitignore`:** added `/app/linux/flutter/ephemeral/`, `/app/coverage/`, `.widget_preview/`, `**/doc/api/`, `app.*.symbols`, `app.*.map.json` and `*.swp` from the generated ignore files. The existing entries already covered the rest.
- **`docs/dependencies.md`:** added the app packages table, the code-review findings, the engine binary and runner review, and how the privacy check works.
- **`CLAUDE.md`:** project state (phase 3 done) plus the lint, test, build and privacy-check commands.

## Code review findings
- **No telemetry or tracking** was found in any package, the Linux runner or the release engine binary.
- **leak_tracker** (dev-only) can start the Dart VM's **local** debug server, but only when "retaining path" collection is turned on. That's off by default. The privacy check now fails if app code or tests turn it on.
- **Network code in `flutter`** exists only in the opt-in `NetworkImage`, `Image.network` and `NetworkAssetBundle` APIs. The privacy check blocks them in app code.
- **`flutter_test`** blocks network access in tests by default: every HTTP request gets an empty 400 response.
- **The Flutter engine** is precompiled, so its C++ source couldn't be reviewed here. The binary was checked instead: its linked libraries, URLs and telemetry strings.
- **Side note:** `~/flutter/bin/cache/artifacts/engine/` has Android engine folders. They came inside the official Flutter 3.47.7 archive, dated 2026-10-08, and nothing downloaded them. They're Flutter's own BSD-licensed binaries, not the declined Android SDK, and Android is disabled in the Flutter config.

## Verification
- `check-lockdown.sh` passed before and after. `~/.dart-tool` still holds only the opt-out config, with no client ID and no telemetry log.
- `flutter analyze --fatal-infos --fatal-warnings`: no issues.
- `flutter test`: 1 test passed.
- `flutter build linux --debug`: built `build/linux/x64/debug/bundle/portfolio_jockey`. It wasn't launched, because the container has no display.
- `bash app/tool/check-privacy.sh`: passed.
- **The privacy check fails as intended** on throwaway copies in the session's temporary folder, deleted afterwards. The cases were:
  - an injected and allowlisted `http` package
  - `HttpClient` in `lib/`
  - an unlisted package version
  - an allowlisted package containing a Google Analytics URL
  - an upgraded `vm_service` with the same code
  - a test turning on retaining paths
  - curl and libsoup in the Linux runner
  - a package from another server
- **A bug found and fixed during that testing:** the comment filter treated C++ `#include` lines as CMake comments, so `#include <curl/curl.h>` slipped through. Now only `# ...` lines count as comments.
- No servers, ports or background processes were left running.

## Impacts
- **Phase 4 (vault core) is next.** `sodium_libs` will be the first real dependency. It must pass the full review: its license, cost and code, including its native libsodium build and any build hooks. Then it gets added to the allowlist and reviewed hits.
- **Every `flutter pub get` or package upgrade** must be followed by `bash app/tool/check-privacy.sh`. A version change fails until its code is re-reviewed.
- **A Flutter upgrade** changes the SDK packages' identity (`flutter@flutter-<version>`), so their reviewed hits must be re-checked too.
- **Backup:** `version-control/local-app/edit002-2026-10-22_before-scaffold/` holds the previous root `.gitignore`. To restore, copy it back and delete `app/`.
