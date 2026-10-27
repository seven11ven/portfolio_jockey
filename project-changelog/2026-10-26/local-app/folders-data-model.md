# Folders: the data model (step 2)

**Time:** 2026-10-26 21:32 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
`app/lib/vault/project_index.dart`:
- **`FolderEntry`** (`id`, `name`, `parentId`, `createdAt`). A null `parentId` is the top level.
- **`ProjectIndex.folders`**, and **`FileEntry.folderId`** (null is the top level). Both are optional in the stored JSON and only written when used, so the index format version stays 1: older indexes load unchanged with everything at the top level, and indexes without folders are written exactly as before.
- **`ProjectIndex.validate()`**, run on load and before every save, so what's written can always be read back. It refuses: a bad or repeated folder ID, a bad name, a parent that doesn't exist, a loop (including a folder inside itself), and a file in a folder that doesn't exist. Failures are `FormatException`s, which the existing loader turns into the usual "could not be opened" error.
- **`folderNameProblem()`:** no length limit. Refused: empty or whitespace-only, `.` and `..`, a slash, and control characters (including NUL).
- **Helpers** (`folderById`, `foldersIn`, `filesIn`, `pathTo`, `subtreeIds`, `statsOf`, `canMoveFolder`). None recurse, so any depth works. `statsOf` gives the file count, folder count and total size a folder card and the delete confirmation need.

## Tests
`test/vault/project_index_test.dart`, 9 new:
- a round trip
- an old index loads
- every unsafe shape is refused on load
- a malformed ID is a `FormatException`, not an `ArgumentError`
- an unsafe index is never written
- names with no length limit, including emoji and 5,000-character names
- a 50,000-deep chain of folders (path, subtree, stats)
- statistics at any depth
- a folder can't move into itself or its own contents

**Full run:** 217 pass (13 skipped); `flutter analyze` is clean; the privacy check passes.

## Found along the way: telemetry lockdown
The lockdown check failed once (a Dart `CLIENT_ID` file in `~/.dart-tool/`). It was written at 20:50:43 UTC by the Dart MCP server VS Code starts, before any Flutter command ran this session. The opt-out variables were set on every Dart process, `reporting=0` was in the config, and the telemetry hosts were blocked, so nothing was sent. With the PM's OK, only that file was deleted, and the check passed again. It may reappear when that server restarts.

## Backup
`version-control/local-app/edit035-2026-10-26_before-folders-model/` (`project_index.dart` and its test).

## Impacts
The index gains optional fields; no stored file changes until a folder is created. Nothing uses folders yet, so the app behaves as before. **Not committed.**
