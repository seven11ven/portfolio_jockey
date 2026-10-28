# Flatpak original-file handoff desktop test

**Time:** 2026-10-27 21:04 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Result
- F2 passed: the file manager revealed the original; moving it to Trash and restoring it worked, and the encrypted project copy remained.
- F5 passed: after the original was moved outside the app, the handoff action was disabled; encrypted-copy deletion remained available.

## Impacts
Updated `packaging/flatpak/TESTING.md`. This confirms the manual handoff in the tested Flatpak; it does not make direct Trash available to the app.