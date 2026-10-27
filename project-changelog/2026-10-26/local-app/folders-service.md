# Folders: the service layer (step 3)

**Time:** 2026-10-26 21:41 UTC
**Performed By:** GitHub Copilot
**Approved By:** Project manager

## Change
`app/lib/services/project_service.dart`, all new methods on `ProjectService` (no screen calls them yet):
- **`createFolder(id, name:, parentId:)`** and **`renameFolder`.** The name is trimmed and checked with `folderNameProblem`. A clash with a sibling folder (ignoring case) is refused with a `FolderNameError` whose message the UI can show as is: "A folder named “X” already exists here. Pick another name."
- **`moveItems(id, fileIds:, folderIds:, targetFolderId:)`** moves any mix of files and folders in **one saved index change**, so it's atomic. Moving a folder into itself or a folder inside it throws a `StateError` and writes nothing. A name the target already has gets "(2)", "(3)"… (for files, before the extension), and the renames come back in `MoveResult.renamed` so the UI can tell the user. Items already in the target are skipped, and nothing is written if nothing moves.
- **`deleteFolder(id, folderId)`** removes the folder, everything inside it at any depth, and the encrypted files, and returns what was removed (`FolderStats`) for the confirmation. It follows the existing crash-safety rule: the index is saved first, then the files are deleted. A crash in between leaves only unlisted encrypted files, which `cleanUp` already removes at the next unlock, so no journal entry is needed.
- **`addFiles(..., folderId:)`** puts new files in a folder, and refuses an unknown folder before encrypting anything.
- Moving never touches the encrypted files: they stay flat in `blobs/`.

## Tests
`test/services/folders_test.dart`, 17 new:
- nesting
- name rules and clashes
- renames
- adding into a folder
- every move rule
- the (2) naming
- no-op moves not written
- contents still readable after a move
- deleting nested trees
- a crash after the index is saved, then clean-up

**Full run:** 234 pass (13 skipped); `flutter analyze` is clean; the privacy check passes; the telemetry lockdown check passes and no client ID file reappeared.

## Backup
`version-control/local-app/edit036-2026-10-26_before-folders-service/` (`project_service.dart`).

## Impacts
Service code only. Nothing in the UI uses folders yet, so the app behaves as before. **Not committed.**
