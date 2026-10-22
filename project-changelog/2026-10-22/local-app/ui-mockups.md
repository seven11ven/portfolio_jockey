# UI mockups for the local app (plan phase 1)

**Date:** 2026-10-22
**Time:** 2026-10-22 13:30 UTC
**Performed by:** Claude Code
**Guideline:** Floor Planning (mockups before any UI is built). The format is static HTML with fake data, as agreed.

## Change
- **Old mockups moved:** the cloud-app mockups (login, dashboard, project, upload, delete, account menu, and their `styles.css`) moved to `project-mockups/cloud-service/` with `git mv`. They still open as before, and the new index links to them.
- **New mockups** in `project-mockups/`. Open `index.html` in a browser.
  - **`mockup.js`:** shows each screen twice, in a desktop (Linux) window and a phone (Android) frame, and adds light/dark and desktop/phone toggles. Each screen is written once; CSS container queries switch to the phone layout inside the narrow frame, with bottom sheets instead of popovers and two-column grids. It makes no network requests and stores nothing.
  - **`styles.css`:** new shared styles. They keep the approved colors and type from the cloud mockups.

| File | Screens |
|------|---------|
| `first-run.html` | Storage location and passphrase setup with the "can't be recovered" warning, unlock, wrong passphrase |
| `home.html` | Project grid, new project (name, cover art, description), the project "…" menu, rename confirmation, delete-project confirmation |
| `project.html` | File grid with tag filter, add-files confirmation, file right-click/long-press menu, the three delete confirmations, the greyed-out state when the original can't be deleted |
| `tags.html` | Tag manager, tag-changes confirmation, editing a file's tags |
| `preview.html` | Image and video preview, "Edit in another app" confirmation, editing banner, save confirmation |
| `export.html` | Project export (ZIP/TAR, readable or encrypted), bulk export, progress, import of an encrypted export |
| `settings.html` | Color scheme (mode and accent), storage location with move confirmation, bulk export, change passphrase, lock, version |

## Small additions shown for approval
These follow from the approved plan but weren't spelled out:
- **Lock button** (🔒) in the top bar and in Settings.
- **Import button** (⤓) on Home.
- **The file menu** also has Preview, Rename, Edit tags and "Export a readable copy" (single file).
- **The delete-project dialog** asks you to type the project's name, and offers "Export first…".
- **Settings › About** states that the app never connects to the internet.

## Verification
- Every page parses as well-formed HTML. Every scene has its screen, all links resolve, and `mockup.js` parses.
- No browser was available in the dev container. Playwright's telemetry status couldn't be confirmed from an official source, so it wasn't installed, as the Open Source and Privacy rule requires. The project manager reviews the pages visually.

## Impacts
- Documentation and design references only; no application code exists yet, so no `version-control/` backup is required.
- App UI work (plan phases 5–7) waits for the project manager's approval of these mockups.

---

# Mockups approved

**Time:** 2026-10-22 13:34 UTC
**Approved by:** project manager

All seven mockup pages are approved as shown, including the small additions listed above. App UI (plan phases 5–7) will be built to match them.

The preview server (port 8000, bound to 127.0.0.1) was stopped after review. The port was confirmed closed.

## Impacts
- No code changes. Phase 2 (toolchain and privacy lockdown) can start.
