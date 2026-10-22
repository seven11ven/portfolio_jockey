# UI mockups for portfolio_jockey v1

**Date:** 2026-10-22
**Time:** 2026-10-22 01:24 UTC
**Performed by:** Claude Code
**Guideline:** Floor Planning (mockups before any UI is built)

## Change
Added static HTML mockups in `project-mockups/`. They use fake sample data only and have no build step. Open `project-mockups/index.html` in a browser.

| File | Screen |
|------|--------|
| `index.html` | Links to every mockup |
| `login.html` | GitHub sign-in, limited to approved accounts |
| `dashboard.html` | Project cards sorted by most recently opened |
| `project.html` | Notes and media timeline with a composer |
| `upload.html` | Drag-and-drop upload with progress and an error state |
| `delete.html` | Type-the-name delete confirmation with an export option |
| `styles.css` | Shared styles, with light and dark themes and a phone layout |

## Impacts
- No application code exists yet. These are design references only, so no `version-control/` backup is required.
- App UI work waits until the project manager approves or revises these mockups.
- Checked at desktop and phone widths in light and dark themes, with no horizontal scrolling.

---

# Display name changed to "Portfolio Jockey"

**Time:** 2026-10-22 01:26 UTC

Replaced the displayed app name "portfolio_jockey" with "Portfolio Jockey" in every mockup page title, header and the shared stylesheet comment.

## Impacts
- The app UI will use "Portfolio Jockey" as its display name.
- The repository name and folder paths are unchanged.

---

# Storage meter added to dashboard mockup

**Time:** 2026-10-22 01:30 UTC

Added a "2.1 of 9 GB used" storage bar under the dashboard header in `project-mockups/dashboard.html`.

## Impacts
- Supports the zero-cost goal. The app will refuse uploads past a 9 GB quota, which keeps usage inside Cloudflare R2's 10 GB free tier.
- The owner approved keeping the header search bar and a 500 MB per-file upload limit.
