# Tap-to-dismiss notifications

**Time:** 2026-10-27 21:29 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- Added `tapDismissibleSnackBar` in `app/lib/ui/common.dart`; tapping message content calls `hideCurrentSnackBar`, while a separate `SnackBarAction` remains available.
- Routed active error, project, export/import, and settings notifications through the helper.
- Added widget regression coverage for message-tap dismissal, preserved action buttons, and the project move-result toast.

## Backup
`version-control/local-app/edit045-2026-10-27_before_tap_dismiss_notifications/` contains the pre-change app files.

## Verification
Tests and analysis passed; details are recorded in `project-changelog/2026-10-28/local-app/tap-dismiss-notifications-verification.md`.

## Impacts
App changes remain uncommitted. The current build kit predates this change and must be regenerated after tests pass and the changes are explicitly approved for commit.