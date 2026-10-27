# Flatpak folder test results

**Time:** 2026-10-27 03:07 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Results received
The project manager supplied the folder test results for the new build kit:
- **K1–K8 passed:** opening an old vault, folder creation and nesting, adding files to folders, views and sorting, whole-project search and tags, drag/drop, Move to/Rename/Delete, and folder export/import.
- **K9 remains untested:** kill the app during folder deletion and confirm the project is whole after unlocking.
- The earlier media retest **D4–D7 remains pending** in the checklist.

## Change
Updated `packaging/flatpak/TESTING.md` to mark K1–K8 passed, record the result in the table, and leave K9 and D4–D7 open. No distribution or desktop details were included in the report, so none were added.

## Impacts
Test documentation only. No app or package changes. **Not committed.**
