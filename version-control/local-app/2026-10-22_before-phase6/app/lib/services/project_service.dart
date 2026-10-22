import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/services/native/gio_trash.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';
import 'package:portfolio_jockey/vault/vault.dart';

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
  ProjectService(this.vault, {this.trasher = const GioTrash()});

  final UnlockedVault vault;

  /// Where originals go: the system Trash (tests use a fake).
  final Trasher trasher;

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
    if (key == null) {
      return null;
    }
    final buffer = SecureBuffer.takeBytes(base64.decode(key));
    try {
      return await vault.readCover(id, buffer);
    } on VaultException {
      return null;
    } finally {
      buffer.dispose();
    }
  }

  Future<String> createProject({required String name, String description = '', Uint8List? cover}) async {
    final index = ProjectIndex(name: name.trim(), description: description.trim());
    final id = await vault.createProject(index);
    if (cover != null) {
      await updateDetails(id, description: index.description, cover: ReplaceCover(cover));
    }
    return id;
  }

  Future<void> renameProject(String id, String name) => _update(id, (index) => index.name = name.trim());

  Future<void> updateDetails(String id, {required String description, required CoverChange cover}) async {
    final index = await vault.readIndex(id);
    index.description = description.trim();
    switch (cover) {
      case KeepCover():
        break;
      case RemoveCover():
        index.coverKey = null;
      case ReplaceCover(:final image):
        // Like file keys, the cover key is stored (encrypted) in the index.
        final encodedKey = base64.encode(Sodium.instance.randomBytes(Sodium.instance.streamKeyBytes));
        final key = SecureBuffer.takeBytes(base64.decode(encodedKey));
        try {
          await vault.writeCover(id, image, key);
        } finally {
          key.dispose();
        }
        index.coverKey = encodedKey;
    }
    await _save(id, index);
    if (cover is RemoveCover) {
      await vault.deleteCover(id);
    }
  }

  Future<void> deleteProject(String id) => vault.deleteProject(id);

  /// Encrypts each file into the project, saving the index after every file,
  /// so an interruption loses at most the file in progress. Originals aren't
  /// touched. [newTags] are added to the project's tags first.
  Future<AddResult> addFiles(
    String id,
    List<String> paths, {
    List<String> tags = const [],
    List<String> newTags = const [],
    void Function(AddProgress progress)? onProgress,
  }) async {
    final index = await vault.readIndex(id);
    _addProjectTags(index, newTags);
    final added = <FileEntry>[];
    final failed = <String, String>{};
    for (var i = 0; i < paths.length; i++) {
      final source = File(paths[i]);
      final name = source.uri.pathSegments.last;
      try {
        final size = await source.length();
        final entry = FileEntry.create(name: name, size: size, tags: [...tags], originalPath: source.absolute.path);
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
    await _update(id, (index) => index.files.removeWhere((f) => f.id == fileId));
    await vault.deleteBlob(id, fileId);
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
}
