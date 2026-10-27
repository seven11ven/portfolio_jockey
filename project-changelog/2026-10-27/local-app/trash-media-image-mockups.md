# Trash, image and media preview mockups

**Time:** 2026-10-27 04:17 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Scope
The project manager chose to request Trash access again at deletion time, explore a built-in audio/video player, and add project-grid image thumbnails plus SVG full-preview support.

## Mockups
- `project-mockups/project.html`: Move to Trash now explains the reselect step, verifies the selected original before a second confirmation, and shows a mismatch state that leaves both copies unchanged. Combined Trash-and-delete notes that both copies stay if the original cannot be verified/trashed.
- `project-mockups/folders.html`: the grid now shows example raster thumbnails and an SVG thumbnail in place of generic image badges.
- `project-mockups/preview.html`: raster image canvas, SVG vector preview, and exploratory paused/playing video and audio in-app player states. The mockup explicitly leaves the media engine undecided pending security and platform review.
- `project-mockups/styles.css`: local, mockup-only visuals for image thumbnails, transparent SVG canvas, media controls, and Trash result states.
- `project-mockups/index.html`: updated Preview page description.

## Backup
`version-control/local-app/edit039-2026-10-27_before-trash-media-image-mockups/` contains the five original mockup files and a restore README.

## Impacts
Static mockups only; no application code or dependencies changed. Awaiting project-manager review before implementation. **Not committed.**
