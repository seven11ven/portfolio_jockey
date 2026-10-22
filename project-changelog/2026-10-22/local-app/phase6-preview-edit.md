# Phase 6: preview and "Edit in another app"

**Date:** 2026-10-22
**Performed by:** Claude Code
**Decided by:** project manager

## Step 0: stop VS Code from flagging the backups
**Time:** 2026-10-22 16:14 UTC

- **Why:** VS Code showed 794 "Problems". They all came from the backed-up `.dart` files in `version-control/local-app/2026-10-22_before-trash/`. Outside `app/`, their imports can't be resolved. The app itself had no problems, and `flutter analyze` was clean.
- **Change:** `"dart.analysisExcludedFolders": ["version-control"]` in `.devcontainer/devcontainer.json`, next to the other Dart settings, with a comment. The same setting was added to this container's VS Code machine settings, which are untracked.
- **Verification:**
  - After a window reload, the Problems panel was empty.
  - `app/` is still analysed: a temporary lint probe was flagged, then deleted.
- **Backup:** `version-control/local-app/2026-10-22_before-analysis-exclude/`.
- **Impact:** editor only. The app, its tests and `flutter analyze` are unchanged.

## Step 1: research and decision point 1
**Time:** 2026-10-22, before 17:00 UTC

The options for audio/video, PDF and Markdown were researched and reported. The PM chose:
- **Audio and video:** media_kit + the system libmpv, with its network features switched off.
- **PDF:** our own FFI bindings to poppler-glib, rendered in memory.
- **Markdown:** flutter_markdown_plus, always with our own image builder, so it never loads images from the network or disk.

The research came from reading the packages' code. It is checked again in the code before each package is added (step 3).

## Step 2: mockup additions and decision point 2
**Time:** 2026-10-22, before 17:58 UTC

- **`project-mockups/preview.html`:** added scenes 6–12:
  - 6: PDF preview
  - 7: Markdown preview
  - 8: "Edit in…" inside a Flatpak, which uses the desktop's app chooser
  - 9: "Discard your changes?" confirmation
  - 10: lock while editing
  - 11: an unfinished edit found at unlock
  - 12: refusal when there's no private memory-only folder
- **Scene 1's note** now says audio and video play in the app via media_kit + libmpv.
- **Approved** by the PM on 2026-10-22.
- **Impact:** mockup only. No application code changed.
