# Backup folders numbered in creation order

**Time:** 2026-10-26 21:07 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Why
The PM asked for the `version-control/local-app/` folders to sort by when they were made, each prefixed with a number.

## Change
- All 34 folders were renamed from `<date>_before-<change>` to `edit<NNN>-<date>_before-<change>`, for example `edit001-2026-10-22_before-flutter-toolchain` up to `edit034-2026-10-26_before-folders-mockup`.
- **Order:** git's first-commit time, with ties (many folders were committed together) settled by the order and times in the changelogs. `edit023-2026-10-23_before-gdb` sits between the delete-label and shared-player backups, because the shared-player entry mentions it.
- **Three digits**, so the numbers sort correctly past 99 without renaming again.
- Tracked folders were renamed with `git mv`, so their history follows. The newest folder wasn't committed yet, so it was moved with `mv`.
- **References:** the 33 mentions in the ten `local-app` changelogs were rewritten to the new names, and each was checked to point at an existing folder. The cloud-era changelogs refer to the separate `cloud-service-abandoned/` folders, which are unchanged.
- **Convention:** `CLAUDE.md` now says new backups are named `edit<NNN>-<date>_before-<change>`, with the next number.

## Impacts
Folder names and documentation only; no application code changed. **Not committed.**
