# Tap-to-dismiss notification verification and release build

**Time:** 2026-10-28 05:14 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Verification
- Focused `test/ui/folders_test.dart`: 13 passed.
- Full `flutter test`: 260 passed, 15 skipped.
- `flutter analyze --fatal-infos --fatal-warnings`: passed.
- `bash .devcontainer/check-lockdown.sh`: passed after removing the generated `~/.dart-tool/CLIENT_ID` created during the test run.
- `bash app/tool/check-privacy.sh`: passed.
- `git diff --check`: passed before resuming the test run.
- No running Flutter app was connected to DTD, so no hot restart was available.
- `bash app/tool/package-bundle.sh`: passed and built the Linux x64 release.

## Impacts
Tap-to-dismiss notifications are verified in tests and included in commit `9404dd68aa7873e0c9591481fe6f91eef6889d63`. The build kit `packaging/flatpak/dist/portfolio-jockey-build-kit-0.1.0.tar.gz` was generated from that commit (SHA-256 `96bb9af70f03ff0bd96084167457330d107ec1413249fc878e48f43c3915cdf5`). The app bundle SHA-256 is `73c98d6955571d23db13ddcb634c0a5ff0073732081fa780a32aefae81c64349`. Both generated artifacts are git-ignored.