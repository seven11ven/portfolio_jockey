# Remove Flatpak handoff snackbar

**Time:** 2026-10-28 05:32 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- Removed the post-handoff "Move the original to Trash in the file manager" snackbar.
- Added a widget assertion that choosing the file-manager handoff does not show that message.
- General tap-to-dismiss behavior remains for other snackbar notifications.

## Backup
`version-control/local-app/edit047-2026-10-28_before-remove-handoff-snackbar/` contains the prior project menu and test.

## Verification
- `flutter test test/ui/projects_test.dart`: 10 passed.
- `flutter analyze --fatal-infos --fatal-warnings`: passed.
- `bash .devcontainer/check-lockdown.sh` and `bash app/tool/check-privacy.sh`: passed.