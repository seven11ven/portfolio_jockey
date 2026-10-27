# Flatpak original-file handoff

**Time:** 2026-10-27 20:11 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- In Flatpak file menus, replace direct Trash with a portal-mediated action to show the original in the desktop file manager.
- Reuse the project file menu from the preview's three-dot button so the full action set remains consistent.
- Keep encrypted-copy deletion available. Disable the combined Trash-and-delete action because the app cannot verify a manual Trash operation.
- Keep direct Trash actions unchanged outside Flatpak.
- Add focused tests and update Flatpak test/install/phase-8 guidance.

## Backup
`version-control/local-app/edit043-2026-10-27_before-flatpak-original-handoff/` contains the prior launcher, project and preview screens, and test files.

## Verification
- `flutter analyze --fatal-infos --fatal-warnings` passed.
- `flutter test` passed: 259 passed, 15 skipped.
- `bash app/tool/check-privacy.sh` passed.
- `bash .devcontainer/check-lockdown.sh` passed.
- Focused project and preview menu tests passed (23 tests).
- The Flatpak handoff still needs a real-desktop test with the release build.

## Impacts
No new package, native symbol, file format, or filesystem permission. The user moves the original to Trash in the desktop file manager, then removes the encrypted project copy separately.