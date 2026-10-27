# Flatpak original-file workaround mockup

**Time:** 2026-10-27 18:47 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- Updated the project and preview menu mockups to open the original in the desktop file manager in the Flatpak, where the user can move it to Trash manually.
- Kept the combined Trash-and-delete action disabled because the app cannot verify that the manual Trash step succeeded. Deleting the encrypted project copy remains available.
- Removed the earlier reselect-and-verify flow after portal source and host logs showed the failure is caused by the document-portal mount, not a missing file grant.

## Impacts
This mockup-only proposal was superseded by the portal-backed file-manager handoff in `flatpak-original-file-handoff.md`. The combined Trash-and-delete action remains unavailable in Flatpak.