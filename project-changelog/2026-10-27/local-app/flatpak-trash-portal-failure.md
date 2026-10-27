# Flatpak Trash portal failure

**Time:** 2026-10-27 04:01 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Result received
The project manager reported that **F2 (Move the original to the Trash)** failed in the Flatpak. The screenshot showed:

> Nothing was changed. FileSystemException: Couldn't move it to the Trash: Trash portal failed on [document portal path].

The path and filename are intentionally omitted because this repository is public. The dialog also confirms that the encrypted project copy stays. The error indicates `g_file_trash()` reached the desktop Trash portal but the request was rejected. The screenshot alone does not distinguish a read-only document-portal grant from another Trash portal/backend failure.

## Change
- `packaging/flatpak/TESTING.md`: F2 is recorded as failed on 2026-10-27; F4 records the sanitized error. Previous F1, F3 and F5 passes remain dated 2026-10-23.

## Impacts
Test documentation only. No app code changed. **Not committed.**

## Decision needed before a code fix
The phase 8 notes already list the possible behavior if the picker grants read-only access: request write access at selection time, request it again at delete time, or disable "Move to Trash" with an explanation. First confirm whether the app can open this portal path read/write; the screenshot's generic portal error is not conclusive. No fallback to direct filesystem Trash is safe inside the sandbox because the app has no permission to reach the original outside the document portal.
