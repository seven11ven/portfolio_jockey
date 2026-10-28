# Hide combined Trash action in Flatpak

**Time:** 2026-10-28 05:35 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- Removed the disabled **Trash original, delete copy** item from Flatpak file menus; it remains available outside Flatpak.
- Updated the project-menu test to assert the option is absent in Flatpak.

## Backup
`version-control/local-app/edit046-2026-10-28_before-hide-flatpak-combined-trash/` contains the prior project menu and test.

## Impacts
Mockup and menu are now consistent. The manual **Show original in file manager** handoff and **Delete from project** remain available.

## Verification
- `flutter test test/ui/projects_test.dart`: 10 passed.
- `flutter analyze --fatal-infos --fatal-warnings`: passed.
- `bash .devcontainer/check-lockdown.sh` and `bash app/tool/check-privacy.sh`: passed.