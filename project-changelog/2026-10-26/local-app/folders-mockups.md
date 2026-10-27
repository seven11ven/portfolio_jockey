# Folders and file explorer: mockups (Floor Planning)

**Time:** 2026-10-26 21:09 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Why
The PM asked for folders inside projects (nestable, like Google Drive), drag and drop into them, and a file-explorer style view with sorting and a search bar. Mockups come first, as the guidelines require.

## PM decisions so far
- Search and tag chips cover the whole project; results show each item's folder path.
- Deleting a folder asks first, with a count of what's inside.
- Locked exports (`.pjx`) bump the manifest version and keep old exports importable.
- The grid stays the default view, with a list-view toggle.
- A folder shows its total size and date created in the list.
- No depth limit and no name length cap, with validation guards instead.

## Change
- **New page** `project-mockups/folders.html`, 13 scenes: grid view, inside a folder, list view, sort menu, search/tag results, two drag-and-drop states, confirm a move, new folder (and a name clash), folder menu, Move to…, delete folder, empty folder.
- **`project-mockups/styles.css`:** new styles for the toolbar, path row, folder cards, list view, drag states and the Move to… tree, plus phone rules (date column hidden, toolbar wraps).
- **`project-mockups/index.html`:** a link to the new page.
- **Backup:** `version-control/local-app/edit034-2026-10-26_before-folders-mockup/` (`styles.css` and `index.html`).

## Impacts
Static HTML only; no app code. Not yet checked in a browser (none available here). **Not committed.** Waiting on the PM's review before any app work.
