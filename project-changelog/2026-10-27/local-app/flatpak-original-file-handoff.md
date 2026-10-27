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

## Build
**Time:** 2026-10-27 20:35 UTC
- `bash app/tool/package-bundle.sh` completed from source commit `34f882c2e38968f3a837de507f839dfbcbe12ace`.
- Build kit: `packaging/flatpak/dist/portfolio-jockey-build-kit-0.1.0.tar.gz`
- Build-kit SHA-256: `f832f712649ec374b0ddb37d8f3d2da1d0524e7e46682788e61914c891a4b8fd`
- App bundle SHA-256: `a735b5bdf8ef7f51478b29b9a0bd3121e1d78d9bace61c68822bb7f3e30ac4b5`
- The build kit is git-ignored; it contains the release app, manifest, and desktop test checklist.

## Impacts
No new package, native symbol, file format, or filesystem permission. The user moves the original to Trash in the desktop file manager, then removes the encrypted project copy separately.