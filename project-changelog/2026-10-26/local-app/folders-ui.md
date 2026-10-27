# Folders: the project screen (step 4)

**Time:** 2026-10-26 21:55–22:30 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
Built to the approved mockups:
- **`app/lib/ui/project/project_screen.dart`** (rewritten around folders):
  - **Navigation:** click a folder to open it; a path row (`Kitchen Remodel > Invoices > 2026`) opens any level. Add files goes into the folder you're in ("Add files here"), and the Add files dialog names the folder.
  - **Toolbar** under the tag chips: search, sort, grid/list toggle, New folder.
  - **Grid view (default):** folders first, then files. A folder card shows its file count and total size.
  - **List view (toggle):** name, size and date columns. A folder shows its total size and date created. The column headings sort.
  - **Sorting:** name, size or date added, ascending or descending. Folders always stay first. The choice is kept for the session in `AppController.explorer` and never saved.
  - **Search and tag chips** cover the whole project: a flat list of matches, each with its folder path ("Kitchen Remodel / Invoices / 2026"). "Show in folder" is in the file menu.
  - **Drag and drop:** files, folders, or a whole selection can be dragged onto a folder card, a list row, or any part of the path row. A drop only asks; the move happens after the confirmation. A folder can't be dropped on itself or anything inside it.
  - **Menus:** a folder menu (Open, Rename, Move to, Delete folder), and "Move to…" in the file menu and the selection bar. The selection now holds folders as well as files.
- **`app/lib/ui/project/folder_dialogs.dart`** (new): new/rename folder (live name checks), "Move to…" (a folder list that greys out a folder's own contents) and the drop confirmation, and the delete confirmation with counts of the files and folders inside and their total size.
- **`app/lib/ui/project/explorer.dart`** (new): the sorting and matching rules, kept separate from the widgets.
- **`app/lib/vault/project_index.dart`:** `allFolderStats()` gives every folder's totals in one pass (so the grid stays quick with many folders).
- **`app/lib/ui/project/file_dialogs.dart`, `app/lib/app/app_controller.dart`:** the small supporting changes above.
- **Previous/next in the preview** now follows the order shown on screen, so `test/ui/preview_test.dart` changed one step (previous instead of next) because it had assumed insertion order.

## Found while testing
- The sort menu rows overflowed while the menu animated open. Fixed with flexible rows, as the file menu already did.
- The drag feedback had a heavy black ring (no surface colour). Fixed.

## Tests
- `test/ui/folders_test.dart`, 10 new: new folder (cancel, live checks, create), opening a folder and adding files into it, search and tag chips with paths, sorting in both views, dragging a file (cancel, then confirm), dragging a selection and refusing a drop on itself, dragging a folder up to the path, rename and Move to…, delete with counts (cancel, then confirm), and sort/view carrying over to the next project.
- `test/vault/project_index_test.dart`: one new test (`allFolderStats` matches `statsOf`, including a 50,000-deep chain).
- `test/screenshots/screenshots_test.dart`: 11 folder scenes in light and dark, compared against the mockups by eye (not committed).
- **Full run:** 245 pass (15 skipped); `flutter analyze` is clean; the privacy check passes; the telemetry lockdown check passes.

## Backup
`version-control/local-app/edit037-2026-10-26_before-folders-ui/` (every changed file, as it was).

## Not done yet
- Folders in exports and imports (step 5): the "Export a readable copy…" item in the folder menu is left out until then. Unlocked ZIP/TAR need nested folders, and the locked `.pjx` manifest needs the version bump.
- The release build hasn't been checked on the virtual screen (the rule applies before a kit goes to the PM).
- Docs and `TESTING.md` (step 7).

## Impacts
The project screen looks and behaves differently, as approved in the mockups. Existing vaults open unchanged, with every file at the top level. **Not committed.**
