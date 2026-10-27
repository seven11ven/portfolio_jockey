# Folders: exports and imports, release-build check, docs (steps 5 to 7)

**Time:** 2026-10-26 22:30–22:55 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
- **Unlocked ZIP/TAR** (`app/lib/services/export_service.dart`): a project's folders are real folders, `<Project>/files/<folders>/<file>`. A name that clashes in the same folder (a file and a folder count too) becomes "name (2)". `project.json` lists every folder, empty ones too (the archive writers hold only files).
- **ZIP path guard:** with no depth limit, a ZIP path can pass its 65,535-byte limit. The export now checks every path first and stops with a clear message before writing anything (`ArchivePathTooLong`). TAR has no such limit.
- **Locked `.pjx`:** the manifest is now **format 2**: each project lists `folders` parents-first (`name`, `parent` as a position, `createdAt`) and each file has a `folder`. The vault's own folder IDs are never written. The `.pjx` container is unchanged, and **format 1 exports still import** (everything at the top level). The parser refuses a parent that isn't an earlier folder, a loop, a file in a missing folder and a bad date.
- **Import** recreates the folders with new IDs and their original dates (`ProjectService.importFolders`, one saved change). Unsafe folder names are repaired and clashes numbered, so a hand-made export can't make a project unreadable. `importFile` takes a `folderId`. Imports stay all or nothing.
- **Export one folder:** the folder menu's "Export a readable copy…" opens the export dialog in a folder mode: ZIP or TAR only, with **no lock option** (like the readable copy of one file; my reading of "readable copy" in the approved mockup, to confirm). `ExportService.exportFolder` writes `<Folder>/<subfolders and files>`, streams each file, and cleans up on failure or Cancel.
- `ProjectIndex.foldersParentsFirst()` gives the order exports list folders in.

## Release-build check (virtual screen)
`flutter build linux --release --no-tree-shake-icons`, run on Xvfb and driven with xdotool, as the kit builds it:
- The lock screen, home and project screens render, and every new icon shows.
- **The old test vault** (made before folders: 9 files) unlocked and showed all 9 files at the top level.
- Created a folder through the dialog, **dragged a file onto it with the real mouse** (the folder highlights, a chip follows the pointer, the source fades), confirmed, and saw "Moved 1 item to Docs". The folder card then read "1 file · 43 B", and opening it showed the path row and "Add files here".
- **Restarted the app:** the folder and the move were still there.
- Afterwards the app and Xvfb were stopped, the memory-only test folder removed, and no port or process was left.

## Docs
- `docs/dependencies.md`: the vault format (folders, the checks, no depth or length limit, delete order), the export layout, the ZIP path limit, folder export, manifest format 2 and old-format imports.
- `CLAUDE.md`: a Folders entry in the project state, and the export rules.
- `packaging/flatpak/TESTING.md`: new section K (K1–K9) for the next test round on the PM's PC, including a kill during a folder delete.

## Tests
- `test/services/export_service_test.dart`, 9 new groups of checks: nested folders in ZIP and TAR, one-folder export for both, cancelling, a locked round trip (folders, placement, dates, empty folders, new IDs, nothing readable in the file), an old format-1 export, hostile manifests (loops, missing folders, bad parents), repaired and numbered names, and the ZIP path guard on a 340-level chain (TAR still works).
- `test/ui/folders_test.dart`: one new test (folder export: no lock option; an empty folder has nothing to export; the ZIP keeps the tree).
- **Full run:** 256 pass (15 skipped); `flutter analyze` is clean; the privacy check passes; the telemetry lockdown check passes and no client ID file reappeared.

## Backup
`version-control/local-app/edit038-2026-10-26_before-folders-export/` (the changed code and tests; documentation is exempt).

## Not done, on purpose
- **Nothing is committed or pushed.** There are many changes in the working tree (steps 1 to 7 plus the backup renames and your guideline edit). A secrets review comes before any commit.
- No new kit was built. The next kit needs a PM test round (K1–K9), and the release checklist in `public-notes/phase8-packaging.md` still applies.
- The `README.md` feature list doesn't mention folders; it's your text, so I left it.

## Impacts
A new manifest format for locked exports (old ones import; exports made now can't be imported by an older build of the app). Everything else is additive, and existing vaults open unchanged.
