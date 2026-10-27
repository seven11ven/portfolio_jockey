import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:portfolio_jockey/services/native/gio_trash.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/inbox.dart';
import 'package:portfolio_jockey/vault/journal.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';
import 'package:portfolio_jockey/vault/vault.dart';

/// A file is larger than a preview may decrypt into memory.
final class TooLargeToPreview implements Exception {
  const TooLargeToPreview(this.size, this.limit);

  final int size;
  final int limit;

  @override
  String toString() => 'The file is too large to preview ($size bytes; the limit is $limit)';
}

/// A project as the home screen shows it.
final class ProjectSummary {
  const ProjectSummary({required this.id, required this.index, this.cover});

  final String id;
  final ProjectIndex index;

  /// The decrypted cover image, or null if the project has none.
  final Uint8List? cover;
}

/// The result of listing projects. Projects whose index can't be read are
/// listed separately rather than hidden.
final class ProjectListing {
  const ProjectListing(this.projects, this.unreadable);

  final List<ProjectSummary> projects;
  final List<String> unreadable;
}

/// How a cover changes in "Change cover art and description".
sealed class CoverChange {
  const CoverChange();
}

final class KeepCover extends CoverChange {
  const KeepCover();
}

final class RemoveCover extends CoverChange {
  const RemoveCover();
}

final class ReplaceCover extends CoverChange {
  const ReplaceCover(this.image);

  final Uint8List image;
}

/// A folder name that can't be used; [message] says why, in plain words.
final class FolderNameError implements Exception {
  const FolderNameError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a move did: how many items moved, and the ones renamed (old name, new
/// name) because the target already had that name.
final class MoveResult {
  const MoveResult({required this.moved, required this.renamed});

  final int moved;
  final List<(String, String)> renamed;
}

/// Progress while adding files: which file, and how far through it.
final class AddProgress {
  const AddProgress({required this.fileNumber, required this.fileCount, required this.fileName, required this.bytesDone, required this.bytesTotal});

  final int fileNumber;
  final int fileCount;
  final String fileName;
  final int bytesDone;
  final int bytesTotal;
}

/// What happened when adding files: the files that were added, and the ones
/// that failed (path → reason).
final class AddResult {
  const AddResult(this.added, this.failed);

  final List<FileEntry> added;
  final Map<String, String> failed;
}

/// Every change the screens make to projects and files.
///
/// Nothing here asks for confirmation: each method is called only after the
/// screen's confirm step. Every write records the project's [ProjectIndex.changedAt].
final class ProjectService {
  ProjectService(this.vault, {this.trasher = const GioTrash(), String? Function(String path)? hostPathOf}) : _hostPathOf = hostPathOf ?? portalHostPath;

  final UnlockedVault vault;

  /// Where originals go: the system Trash (tests use a fake).
  final Trasher trasher;

  Future<void> _journalQueue = Future<void>.value();

  /// Adds or replaces [entry] in the vault's journal of unfinished work
  /// (journal.dart). Changes are made one at a time.
  Future<void> journalPut(JournalEntry entry) => _journal((entries) => [...entries.where((e) => e.id != entry.id), entry]);

  /// Removes the entry [id] once its work has finished or been tidied up.
  Future<void> journalRemove(String id) => _journal((entries) => [...entries.where((e) => e.id != id)]);

  /// The inbox's notices, oldest first.
  Future<List<InboxNotice>> inbox() async {
    await _journalQueue;
    return vault.readInbox();
  }

  /// Changes the inbox, one change at a time (shares the journal's queue).
  Future<List<InboxNotice>> changeInbox(List<InboxNotice> Function(List<InboxNotice> notices) change) {
    final next = _journalQueue.then((_) async {
      final changed = change(await vault.readInbox());
      await vault.writeInbox(changed);
      return changed;
    });
    _journalQueue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// The unfinished work listed in the journal.
  Future<List<JournalEntry>> journalEntries() async {
    await _journalQueue;
    return vault.readJournal();
  }

  Future<void> _journal(List<JournalEntry> Function(List<JournalEntry> entries) change) {
    final next = _journalQueue.then((_) async => vault.writeJournal(change(await vault.readJournal())));
    _journalQueue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Tidies up work the journal still lists, so after a crash or power cut
  /// nothing is half done or left readable. Call after unlocking, once
  /// [EditSessions.findLeftovers] has run. [openEditIds] are the edit folders
  /// that still exist (they're offered to the user as usual). Returns one
  /// plain-language notice (a title and a text) per thing that was tidied up.
  Future<List<({String title, String text})>> recoverJournal({required Set<String> openEditIds}) async {
    final notices = <({String title, String text})>[];
    final currentRoot = vault.layout.root.absolute.path;
    for (final entry in await journalEntries()) {
      try {
        switch (entry) {
          case ExportStarted(:final tempPath):
            final temp = File(tempPath);
            if (await temp.exists()) {
              await PrivateFolders.overwriteWithZeros(temp);
              await temp.delete();
              notices.add((title: 'Export cleaned up', text: 'An export was interrupted. Its unfinished file was removed.'));
            }
          case ImportStarted(:final projectIds):
            var removed = 0;
            for (final id in projectIds) {
              if (await vault.layout.projectDir(id).exists()) {
                await vault.deleteProject(id);
                removed++;
              }
            }
            if (removed > 0) {
              notices.add((title: 'Import undone', text: 'An import was interrupted, so it was undone. Nothing from it was kept.'));
            }
          case MoveStarted(:final source, :final target):
            if (target == currentRoot && source != currentRoot) {
              // The switch was saved; only the old folder's removal was cut off.
              final old = Directory(source);
              if (await File('$source/.pj/vault').exists()) {
                await old.delete(recursive: true);
                notices.add((title: 'Storage move finished', text: 'Moving the storage location was interrupted at the end. The move is complete, and the old folder was removed.'));
              }
            } else if (source == currentRoot && target != currentRoot) {
              // Cut off before the switch: the copy at the target is unfinished.
              final copy = Directory(target);
              if (await copy.exists()) {
                await for (final child in copy.list(followLinks: false)) {
                  await child.delete(recursive: true);
                }
                notices.add((title: 'Storage move undone', text: 'Moving the storage location was interrupted. Your projects stay where they were, and the unfinished copy was removed.'));
              }
            }
          case EditStarted(:final projectName, :final fileName):
            if (openEditIds.contains(entry.id)) {
              continue; // still there: it's offered to save or discard as usual
            }
            notices.add((
              title: "An edit wasn't saved",
              text:
                  "An edit of $fileName in $projectName was open when the app closed. Its changes weren't saved; "
                  'the project still has the previous version.',
            ));
        }
        await journalRemove(entry.id);
      } on Object catch (e) {
        notices.add((title: "Couldn't tidy up", text: "Couldn't tidy up after an interrupted task: $e"));
      }
    }
    return notices;
  }

  /// Deletes leftovers a crash can leave inside projects: encrypted files no
  /// index refers to, old covers, and unfinished temporary files. Only
  /// projects whose index can be read are touched; nothing an index refers
  /// to is ever deleted, and nothing written after the clean-up started (an
  /// add or edit the user began meanwhile). Returns how many files it removed.
  Future<int> cleanUp() async {
    final startedAt = DateTime.now();
    var removed = 0;
    Future<void> remove(FileSystemEntity entity) async {
      if ((await entity.stat()).modified.isBefore(startedAt)) {
        await entity.delete();
        removed++;
      }
    }

    bool isTemp(String name) => name.startsWith('.') && name.contains('.tmp-');
    for (final id in await vault.projectIds()) {
      final ProjectIndex index;
      try {
        index = await vault.readIndex(id);
      } on VaultException {
        continue; // unreadable: reported by listProjects, never deleted here
      }
      final cover = index.coverKey == null ? null : vault.layout.coverFile(id, index.coverId).uri.pathSegments.last;
      await for (final entity in vault.layout.projectDir(id).list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && (isTemp(name) || (name.startsWith('cover') && name.endsWith('.enc') && name != cover))) {
          await remove(entity);
        }
      }
      final blobDir = vault.layout.blobDir(id);
      if (await blobDir.exists()) {
        final blobs = {for (final f in index.files) '${f.blob}.enc'};
        await for (final entity in blobDir.list(followLinks: false)) {
          final name = entity.uri.pathSegments.last;
          if (entity is File && (isTemp(name) || (name.endsWith('.enc') && !blobs.contains(name)))) {
            await remove(entity);
          }
        }
      }
    }
    await for (final entity in vault.layout.metadataDir.list(followLinks: false)) {
      if (entity is File && isTemp(entity.uri.pathSegments.last)) {
        await remove(entity);
      }
    }
    return removed;
  }

  /// Tests only: called between the steps of a multi-step write, so a test
  /// can throw there to simulate a crash or power cut at that point.
  @visibleForTesting
  void Function(String step)? crashPoint;

  /// The real path behind a document portal path, or null (tests use a fake).
  final String? Function(String path) _hostPathOf;

  /// Every project, most recently changed first.
  Future<ProjectListing> listProjects() async {
    final projects = <ProjectSummary>[];
    final unreadable = <String>[];
    for (final id in await vault.projectIds()) {
      try {
        final index = await vault.readIndex(id);
        projects.add(ProjectSummary(id: id, index: index, cover: await readCover(id, index)));
      } on VaultException {
        unreadable.add(id);
      }
    }
    projects.sort((a, b) => b.index.changedAt.compareTo(a.index.changedAt));
    return ProjectListing(projects, unreadable);
  }

  Future<ProjectIndex> readProject(String id) => vault.readIndex(id);

  /// The project's cover, or null if it has none or it can't be read.
  Future<Uint8List?> readCover(String id, ProjectIndex index) async {
    final key = index.coverKey;
    final coverId = index.coverId;
    if (key == null) {
      return null;
    }
    final buffer = SecureBuffer.takeBytes(base64.decode(key));
    try {
      return await vault.readCover(id, buffer, coverId: coverId);
    } on VaultException {
      return null;
    } finally {
      buffer.dispose();
    }
  }

  Future<String> createProject({required String name, String description = '', Uint8List? cover, String? id}) async {
    final index = ProjectIndex(name: name.trim(), description: description.trim());
    final projectId = await vault.createProject(index, id: id);
    if (cover != null) {
      await updateDetails(projectId, description: index.description, cover: ReplaceCover(cover));
    }
    return projectId;
  }

  Future<void> renameProject(String id, String name) => _update(id, (index) => index.name = name.trim());

  Future<void> updateDetails(String id, {required String description, required CoverChange cover}) async {
    final index = await vault.readIndex(id);
    index.description = description.trim();
    // The old cover is only deleted once the index no longer points at it, so
    // a crash leaves either the old cover or the new one, both readable.
    final oldCoverKey = index.coverKey;
    final oldCoverId = index.coverId;
    switch (cover) {
      case KeepCover():
        break;
      case RemoveCover():
        index
          ..coverKey = null
          ..coverId = null;
      case ReplaceCover(:final image):
        // Like file keys, the cover key is stored (encrypted) in the index.
        final encodedKey = base64.encode(Sodium.instance.randomBytes(Sodium.instance.streamKeyBytes));
        final coverId = newId();
        final key = SecureBuffer.takeBytes(base64.decode(encodedKey));
        try {
          await vault.writeCover(id, image, key, coverId: coverId);
        } finally {
          key.dispose();
        }
        crashPoint?.call('cover written');
        index
          ..coverKey = encodedKey
          ..coverId = coverId;
    }
    await _save(id, index);
    if (cover is! KeepCover && oldCoverKey != null) {
      crashPoint?.call('index saved');
      await vault.deleteCover(id, coverId: oldCoverId);
    }
  }

  Future<void> deleteProject(String id) => vault.deleteProject(id);

  /// Encrypts each file into the project, saving the index after every file,
  /// so an interruption loses at most the file in progress. Originals aren't
  /// touched. [newTags] are added to the project's tags first. Files go into
  /// [folderId] (null is the top level).
  Future<AddResult> addFiles(
    String id,
    List<String> paths, {
    List<String> tags = const [],
    List<String> newTags = const [],
    String? folderId,
    void Function(AddProgress progress)? onProgress,
  }) async {
    final index = await vault.readIndex(id);
    _checkFolder(index, folderId);
    _addProjectTags(index, newTags);
    final added = <FileEntry>[];
    final failed = <String, String>{};
    for (var i = 0; i < paths.length; i++) {
      final source = File(paths[i]);
      final name = source.uri.pathSegments.last;
      try {
        final size = await source.length();
        final original = source.absolute.path;
        final entry = FileEntry.create(name: name, size: size, tags: [...tags], originalPath: original, originalShownPath: _hostPathOf(original), folderId: folderId);
        var done = 0;
        final counted = source.openRead().map((chunk) {
          done += chunk.length;
          onProgress?.call(AddProgress(fileNumber: i + 1, fileCount: paths.length, fileName: name, bytesDone: done, bytesTotal: size));
          return chunk;
        });
        final key = entry.openKey();
        try {
          await vault.writeBlob(id, entry.id, counted, key);
        } finally {
          key.dispose();
        }
        index.files.add(entry);
        await _save(id, index);
        added.add(entry);
      } on FileSystemException catch (e) {
        failed[paths[i]] = e.osError?.message ?? e.message;
      }
    }
    if (added.isEmpty && newTags.isNotEmpty) {
      await _save(id, index);
    }
    return AddResult(added, failed);
  }

  Future<void> renameFile(String id, String fileId, String name) =>
      _update(id, (index) => _file(index, fileId).name = name.trim());

  /// Creates a folder inside [parentId] (null is the top level). Throws
  /// [FolderNameError] for a name that's empty, unsafe, or already used by
  /// another folder there (ignoring case).
  Future<FolderEntry> createFolder(String id, {required String name, String? parentId}) async {
    late FolderEntry folder;
    await _update(id, (index) {
      _checkFolder(index, parentId);
      folder = FolderEntry.create(name: _checkedFolderName(index, name, parentId), parentId: parentId);
      index.folders.add(folder);
    });
    return folder;
  }

  /// Renames a folder, with the same name rules as [createFolder].
  Future<void> renameFolder(String id, String folderId, String name) => _update(id, (index) {
    final folder = _folder(index, folderId);
    folder.name = _checkedFolderName(index, name, folder.parentId, ignoring: folderId);
  });

  /// Moves files and folders into [targetFolderId] (null is the top level) in
  /// one saved change. A name the target already has gets "(2)", "(3)"… so
  /// nothing clashes. Throws [StateError] if a folder would go into itself or
  /// a folder inside it. Items already in the target are left alone, and
  /// nothing is written if nothing moves.
  Future<MoveResult> moveItems(String id, {List<String> fileIds = const [], List<String> folderIds = const [], String? targetFolderId}) async {
    final index = await vault.readIndex(id);
    _checkFolder(index, targetFolderId);
    final folders = [for (final folderId in folderIds) _folder(index, folderId)];
    final files = [for (final fileId in fileIds) _file(index, fileId)];
    for (final folder in folders) {
      if (!index.canMoveFolder(folder.id, targetFolderId)) {
        throw StateError('A folder can\'t be moved into itself or into a folder inside it');
      }
    }
    final takenFolders = {for (final f in index.foldersIn(targetFolderId)) f.name.toLowerCase()};
    final takenFiles = {for (final f in index.filesIn(targetFolderId)) f.name.toLowerCase()};
    final renamed = <(String, String)>[];
    var moved = 0;
    for (final folder in folders.where((f) => f.parentId != targetFolderId)) {
      final name = _uniqueName(folder.name, takenFolders);
      if (name != folder.name) {
        renamed.add((folder.name, name));
      }
      folder
        ..name = name
        ..parentId = targetFolderId;
      moved++;
    }
    for (final file in files.where((f) => f.folderId != targetFolderId)) {
      final name = _uniqueName(file.name, takenFiles, isFile: true);
      if (name != file.name) {
        renamed.add((file.name, name));
      }
      file
        ..name = name
        ..folderId = targetFolderId;
      moved++;
    }
    if (moved > 0) {
      await _save(id, index);
    }
    return MoveResult(moved: moved, renamed: renamed);
  }

  /// Permanently deletes a folder and everything inside it, at any depth, and
  /// returns what was removed. Like [deleteFromProject], the index is saved
  /// first and the encrypted files are deleted after: a crash in between
  /// leaves only unlisted files, which [cleanUp] removes at the next unlock.
  Future<FolderStats> deleteFolder(String id, String folderId) async {
    final index = await vault.readIndex(id);
    _folder(index, folderId);
    final stats = index.statsOf(folderId);
    final inside = index.subtreeIds(folderId);
    final blobs = [for (final f in index.files) if (inside.contains(f.folderId)) f.blob];
    index.folders.removeWhere((f) => inside.contains(f.id));
    index.files.removeWhere((f) => inside.contains(f.folderId));
    await _save(id, index);
    crashPoint?.call('index saved');
    for (final blob in blobs) {
      await vault.deleteBlob(id, blob);
    }
    return stats;
  }

  /// Sets the tags of the files in [tagsByFile] (file ID → its new tags).
  /// [newTags] are added to the project's tags.
  Future<void> setFileTags(String id, Map<String, List<String>> tagsByFile, {List<String> newTags = const []}) =>
      _update(id, (index) {
        _addProjectTags(index, newTags);
        for (final MapEntry(key: fileId, value: tags) in tagsByFile.entries) {
          // Use the project's spelling of each tag; drop tags it doesn't have.
          final canonical = <String>{
            for (final tag in tags) ...index.tags.where((t) => t.toLowerCase() == tag.trim().toLowerCase()),
          };
          _file(index, fileId).tags
            ..clear()
            ..addAll(canonical);
        }
      });

  /// Applies a reviewed batch from "Manage tags". Removing a tag only removes
  /// the label: files are never deleted this way.
  Future<void> applyTagChanges(String id, TagChanges changes) => _update(id, (index) {
    String renamed(String tag) => changes.renames[tag] ?? tag;
    final tags = [
      for (final tag in index.tags)
        if (!changes.removed.contains(tag)) renamed(tag),
    ];
    for (final tag in changes.added) {
      final clean = cleanTagName(tag);
      if (clean != null && !hasTag(tags, clean)) {
        tags.add(clean);
      }
    }
    index.tags
      ..clear()
      ..addAll(tags);
    for (final file in index.files) {
      final fileTags = [
        for (final tag in file.tags)
          if (!changes.removed.contains(tag)) renamed(tag),
      ];
      file.tags
        ..clear()
        ..addAll(fileTags);
    }
  });

  /// Deletes the encrypted copy. The index is saved first, so an interrupted
  /// delete can't leave the project listing a file it no longer has.
  Future<void> deleteFromProject(String id, String fileId) async {
    var blob = fileId;
    await _update(id, (index) {
      blob = _file(index, fileId).blob;
      index.files.removeWhere((f) => f.id == fileId);
    });
    await vault.deleteBlob(id, blob);
  }

  /// Moves the original file on this device to the Trash, where it can be
  /// restored until the Trash is emptied. The encrypted copy stays.
  Future<void> trashOriginal(String id, String fileId) async {
    final index = await vault.readIndex(id);
    final path = _file(index, fileId).originalPath;
    if (path == null) {
      throw StateError('The original location is unknown');
    }
    await trasher.trash(path);
  }

  /// Trashes the original first: if that fails, the project copy is kept.
  /// The project copy is then deleted permanently.
  Future<void> trashOriginalAndDeleteCopy(String id, String fileId) async {
    await trashOriginal(id, fileId);
    await deleteFromProject(id, fileId);
  }

  /// Decrypts file [fileId] fully into memory, for a preview. Nothing is
  /// returned unless the whole file decrypts and authenticates, so a damaged
  /// file never shows half its content. Throws [TooLargeToPreview] above
  /// [maxBytes]. Wipe the result when it's no longer shown.
  Future<Uint8List> readFile(String id, FileEntry file, {required int maxBytes}) async {
    if (file.size > maxBytes) {
      throw TooLargeToPreview(file.size, maxBytes);
    }
    final chunks = <Uint8List>[];
    var total = 0;
    final key = file.openKey();
    try {
      await for (final chunk in vault.readBlob(id, file.blob, key)) {
        chunks.add(chunk);
        total += chunk.length;
        if (total > maxBytes) {
          throw TooLargeToPreview(total, maxBytes);
        }
      }
      final bytes = Uint8List(total);
      var at = 0;
      for (final chunk in chunks) {
        bytes.setAll(at, chunk);
        at += chunk.length;
      }
      return bytes;
    } finally {
      key.dispose();
      for (final chunk in chunks) {
        chunk.fillRange(0, chunk.length, 0);
      }
    }
  }

  /// Decrypts [file] chunk by chunk, for exports. The file's key is wiped
  /// when the stream ends, fails or is cancelled. As with every decryption
  /// stream, if it ends in an error, everything received must be discarded.
  Stream<Uint8List> openFile(String id, FileEntry file) async* {
    final key = file.openKey();
    try {
      yield* vault.readBlob(id, file.blob, key);
    } finally {
      key.dispose();
    }
  }

  /// Encrypts [content] into project [id] as a new file with a fresh key, for
  /// imports. [tags] missing from the project are added to it. Throws
  /// [FormatException] if [content] isn't [size] bytes, and nothing is added.
  Future<void> importFile(
    String id, {
    required String name,
    required int size,
    required List<String> tags,
    required DateTime addedAt,
    required Stream<List<int>> content,
    String? folderId,
  }) async {
    final index = await vault.readIndex(id);
    _checkFolder(index, folderId);
    final entry = FileEntry.create(name: name, size: size, tags: [...tags], addedAt: addedAt, folderId: folderId);
    var received = 0;
    final counted = content.map((chunk) {
      received += chunk.length;
      return chunk;
    });
    final key = entry.openKey();
    try {
      await vault.writeBlob(id, entry.id, counted, key);
    } finally {
      key.dispose();
    }
    if (received != size) {
      await vault.deleteBlob(id, entry.id);
      throw FormatException('$name: expected $size bytes, got $received');
    }
    _addProjectTags(index, tags);
    index.files.add(entry);
    await _save(id, index);
  }

  /// Adds folders to project [id] in one saved change, for imports. Each has
  /// the position of its parent in [folders] (always an earlier one), or null
  /// at the top level. An unsafe name is repaired, and one a sibling already
  /// has gets "(2)"…, so nothing from a damaged or hand-made export can make
  /// the index unreadable. Returns the new folders' IDs, in order.
  Future<List<String>> importFolders(String id, List<({String name, int? parent, DateTime createdAt})> folders) async {
    final ids = <String>[];
    await _update(id, (index) {
      final taken = <String?, Set<String>>{};
      for (final folder in folders) {
        final parent = folder.parent == null ? null : ids[folder.parent!];
        var name = folder.name.trim();
        if (folderNameProblem(name) != null) {
          name = name.replaceAll(RegExp(r'[/\x00-\x1F\x7F]'), '_').trim();
        }
        if (folderNameProblem(name) != null) {
          name = 'Folder';
        }
        final created = FolderEntry.create(name: _uniqueName(name, taken.putIfAbsent(parent, () => {})), parentId: parent, createdAt: folder.createdAt);
        index.folders.add(created);
        ids.add(created.id);
      }
    });
    return ids;
  }

  /// Decrypts file [fileId] into [target], which must be in a private
  /// memory-only folder (see PrivateFolders). If decryption fails part-way,
  /// [target] is overwritten with zeros and deleted.
  Future<void> decryptTo(String id, FileEntry file, File target) async {
    final key = file.openKey();
    final out = target.openWrite();
    try {
      await out.addStream(vault.readBlob(id, file.blob, key));
      await out.close();
    } on Object {
      await out.close().catchError((_) {});
      if (await target.exists()) {
        await PrivateFolders.overwriteWithZeros(target);
        await target.delete();
      }
      rethrow;
    } finally {
      key.dispose();
    }
  }

  /// Whether [edited] differs from file [fileId]'s current content.
  Future<bool> differsFrom(String id, FileEntry file, File edited) async {
    if (await edited.length() != file.size) {
      return true;
    }
    final key = file.openKey();
    final reader = await edited.open();
    try {
      await for (final chunk in vault.readBlob(id, file.blob, key)) {
        final other = await reader.read(chunk.length);
        var same = other.length == chunk.length;
        for (var i = 0; same && i < chunk.length; i++) {
          same = chunk[i] == other[i];
        }
        chunk.fillRange(0, chunk.length, 0);
        other.fillRange(0, other.length, 0);
        if (!same) {
          return true;
        }
      }
      return (await reader.read(1)).isNotEmpty;
    } finally {
      key.dispose();
      await reader.close();
    }
  }

  /// Encrypts [edited] as the new content of file [fileId] with the file's
  /// key, replacing the encrypted copy atomically, then records the new size.
  /// The new version goes under a new blob ID, then the index points at it
  /// (with its size), and only then is the old blob deleted. A crash at any
  /// point leaves the old version or the new one complete; a leftover blob is
  /// removed by [cleanUp].
  Future<void> replaceContent(String id, String fileId, File edited) async {
    final index = await vault.readIndex(id);
    final entry = _file(index, fileId);
    final oldBlob = entry.blob;
    final newBlob = newId();
    final size = await edited.length();
    final key = entry.openKey();
    try {
      await vault.writeBlob(id, newBlob, edited.openRead(), key);
    } finally {
      key.dispose();
    }
    crashPoint?.call('blob written');
    entry
      ..blobId = newBlob
      ..size = size;
    await _save(id, index);
    crashPoint?.call('index saved');
    await vault.deleteBlob(id, oldBlob);
  }

  /// Whether the original is still where it was added from.
  Future<bool> originalExists(FileEntry file) async {
    final path = file.originalPath;
    return path != null && await File(path).exists();
  }

  Future<void> _update(String id, void Function(ProjectIndex index) change) async {
    final index = await vault.readIndex(id);
    change(index);
    await _save(id, index);
  }

  Future<void> _save(String id, ProjectIndex index) {
    index.changedAt = DateTime.now().toUtc();
    return vault.writeIndex(id, index);
  }

  static void _addProjectTags(ProjectIndex index, List<String> tags) {
    for (final tag in tags) {
      final clean = cleanTagName(tag);
      if (clean != null && !hasTag(index.tags, clean)) {
        index.tags.add(clean);
      }
    }
  }

  static FileEntry _file(ProjectIndex index, String fileId) => index.files.firstWhere(
    (f) => f.id == fileId,
    orElse: () => throw StateError('No file $fileId in this project'),
  );

  static FolderEntry _folder(ProjectIndex index, String folderId) => index.folderById(folderId) ?? (throw StateError('No folder $folderId in this project'));

  /// Checks that [folderId] exists; null (the top level) always does.
  static void _checkFolder(ProjectIndex index, String? folderId) {
    if (folderId != null) {
      _folder(index, folderId);
    }
  }

  static String _checkedFolderName(ProjectIndex index, String name, String? parentId, {String? ignoring}) {
    final clean = name.trim();
    final problem = folderNameProblem(clean);
    if (problem != null) {
      throw FolderNameError(problem);
    }
    final lower = clean.toLowerCase();
    if (index.foldersIn(parentId).any((f) => f.id != ignoring && f.name.toLowerCase() == lower)) {
      throw FolderNameError('A folder named “$clean” already exists here. Pick another name.');
    }
    return clean;
  }

  /// [name], or "name (2)", "name (3)"… if [taken] (lowercase) has it; a file's
  /// number goes before its extension. The chosen name is added to [taken].
  static String _uniqueName(String name, Set<String> taken, {bool isFile = false}) {
    final dot = isFile ? name.lastIndexOf('.') : -1;
    final (stem, ext) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
    var candidate = name;
    for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
      candidate = '$stem ($n)$ext';
    }
    taken.add(candidate.toLowerCase());
    return candidate;
  }
}

/// Whether [path] is inside a document portal mount, where files picked
/// inside a Flatpak arrive: `/run/user/<uid>/doc/` or `/run/flatpak/doc/`.
bool isPortalPath(String path) => RegExp(r'^/run/(user/\d+|flatpak)/doc/').hasMatch(path);

/// The real path of a file picked through the document portal, or null for
/// any other path. Outside a Flatpak, nothing is read.
String? portalHostPath(String path) => isPortalPath(path) ? Libc.instance.hostPath(path) : null;
