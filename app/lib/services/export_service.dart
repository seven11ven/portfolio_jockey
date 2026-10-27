import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/services/archive/archive_entry.dart';
import 'package:portfolio_jockey/services/archive/tar_reader.dart';
import 'package:portfolio_jockey/services/archive/tar_writer.dart';
import 'package:portfolio_jockey/services/archive/zip_writer.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/vault/atomic_write.dart';
import 'package:portfolio_jockey/vault/export_format.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/journal.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

enum ArchiveFormat {
  zip('zip'),
  tar('tar');

  const ArchiveFormat(this.extension);

  final String extension;
}

/// How an export is protected: one of exactly two options (PM decision,
/// 2026-10-22). The vault passphrase is never used for exports.
sealed class ExportLock {
  const ExportLock();
}

/// A regular ZIP or TAR that anyone can open.
final class Unlocked extends ExportLock {
  const Unlocked(this.format);

  final ArchiveFormat format;
}

/// A `.pjx` file locked with a passphrase the user chose for this export.
final class LockedWith extends ExportLock {
  const LockedWith(this.passphrase);

  final String passphrase;
}

/// The extension a locked export uses.
const String lockedExtension = 'pjx';

final class ExportProgress {
  const ExportProgress({required this.projectName, required this.fileNumber, required this.fileCount, required this.bytesDone, required this.bytesTotal});

  final String projectName;
  final int fileNumber;
  final int fileCount;
  final int bytesDone;
  final int bytesTotal;
}

/// Lets the user stop an export or import part-way.
final class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void check() {
    if (_cancelled) {
      throw const Cancelled();
    }
  }
}

/// The user cancelled. Nothing was kept.
final class Cancelled implements Exception {
  const Cancelled();

  @override
  String toString() => 'Cancelled';
}

/// One project in a locked export, as its manifest describes it.
final class ManifestProject {
  const ManifestProject({required this.name, required this.description, required this.tags, required this.cover, required this.files, this.folders = const []});

  final String name;
  final String description;
  final List<String> tags;
  final String? cover;
  final List<ManifestFile> files;

  /// Each folder comes after its parent. Empty in exports from before folders (manifest format 1).
  final List<ManifestFolder> folders;
}

/// A folder in a locked export. [parent] is the position of its parent in
/// [ManifestProject.folders] (always an earlier one), or null at the top level.
final class ManifestFolder {
  const ManifestFolder({required this.name, required this.parent, required this.createdAt});

  final String name;
  final int? parent;
  final DateTime createdAt;
}

final class ManifestFile {
  const ManifestFile({required this.path, required this.name, required this.size, required this.addedAt, required this.tags, this.folder});

  final String path;
  final String name;
  final int size;
  final DateTime addedAt;
  final List<String> tags;

  /// The position in [ManifestProject.folders] of the folder it's in, or null at the top level.
  final int? folder;
}

/// A file's path inside a ZIP would be longer than ZIP allows (65,535 bytes).
final class ArchivePathTooLong implements Exception {
  const ArchivePathTooLong(this.path);

  final String path;

  @override
  String toString() {
    final shown = path.length > 80 ? '${path.substring(0, 80)}…' : path;
    return "A file's path inside the archive would be too long for a ZIP (over 65,535 bytes): “$shown”. Export as TAR instead, or move it closer to the top level.";
  }
}

/// A locked export whose passphrase was right. Dispose it when done: it
/// holds the export's key.
final class LockedExport {
  LockedExport._(this.file, this._key, this.projects, this.importNames);

  final File file;
  final ExportKey _key;
  final List<ManifestProject> projects;

  /// The name each project gets when imported: its own, or "Name (2)" when a
  /// project of that name already exists.
  final List<String> importNames;

  int get fileCount => projects.fold(0, (sum, p) => sum + p.files.length);

  void dispose() => _key.dispose();
}

/// Exports projects as ZIP, TAR or locked `.pjx` files, and imports `.pjx`.
///
/// Every file is decrypted chunk by chunk straight into the archive, so no
/// readable copy is written anywhere except the export itself. Exports are
/// written to a temporary file next to the target and renamed into place;
/// if they fail or are cancelled, the temporary file is removed, and for an
/// unlocked export it's overwritten with zeros first.
final class ExportService {
  ExportService(this.projects, {this.kdf});

  final ProjectService projects;

  /// Argon2id settings for new locked exports. Null means MODERATE; tests
  /// pass smaller ones.
  final KdfParams? kdf;

  static const String _manifestPath = 'manifest.json';

  /// The manifest's format: 2 added folders. Exports of format 1 (from before
  /// folders) can still be imported.
  static const int manifestFormat = 2;
  static const int _maxManifestBytes = 16 * 1024 * 1024;
  static const int _maxCoverBytes = 64 * 1024 * 1024;

  /// Exports [projectIds] to [target].
  Future<void> export({
    required List<String> projectIds,
    required File target,
    required ExportLock lock,
    void Function(ExportProgress progress)? onProgress,
    CancelToken? cancel,
  }) async {
    final indexes = [for (final id in projectIds) (id, await projects.readProject(id))];
    if (lock case Unlocked(format: ArchiveFormat.zip)) {
      for (final (_, index) in indexes) {
        _checkZipPaths(safeName(index.name, fallback: 'Project'), [for (final (_, path) in _layout(index, null).files) path]);
      }
    }
    final fileCount = indexes.fold(0, (sum, p) => sum + p.$2.files.length);
    final bytesTotal = indexes.fold(0, (sum, p) => sum + p.$2.totalSize);
    var fileNumber = 0;
    var bytesDone = 0;

    // Wraps a file's content so it reports progress and can be cancelled.
    Stream<List<int>> tracked(String projectName, Stream<List<int>> content) async* {
      fileNumber++;
      onProgress?.call(ExportProgress(projectName: projectName, fileNumber: fileNumber, fileCount: fileCount, bytesDone: bytesDone, bytesTotal: bytesTotal));
      await for (final chunk in content) {
        cancel?.check();
        bytesDone += chunk.length;
        yield chunk;
      }
      onProgress?.call(ExportProgress(projectName: projectName, fileNumber: fileNumber, fileCount: fileCount, bytesDone: bytesDone, bytesTotal: bytesTotal));
    }

    // The temporary file is listed in the journal before anything is written,
    // so a crash mid-export doesn't leave it behind (readable, when unlocked).
    final journalId = newId();
    Future<void> listTemp(File temp) => projects.journalPut(ExportStarted(journalId, tempPath: temp.path));
    try {
      switch (lock) {
        case Unlocked(:final format):
          final entries = _readableEntries(indexes, tracked);
          await writeAtomically(
            target,
            onTemp: listTemp,
            (out) async {
              await for (final chunk in format == ArchiveFormat.zip ? zipStream(entries) : tarStream(entries)) {
                cancel?.check();
                await out.writeFrom(chunk);
              }
            },
            beforeDelete: PrivateFolders.overwriteWithZeros,
          );
        case LockedWith(:final passphrase):
          await writeLockedExport(target, passphrase, tarStream(_lockedEntries(indexes, tracked)), kdf: kdf, onTemp: listTemp);
      }
    } finally {
      await projects.journalRemove(journalId);
    }
  }

  /// Exports one folder of project [projectId], with everything inside it, as
  /// an unlocked ZIP or TAR: `<Folder>/<its subfolders and files>`. Each file
  /// is decrypted chunk by chunk straight into the archive. Empty folders
  /// aren't listed, because the archive writers only hold files.
  Future<void> exportFolder({
    required String projectId,
    required String folderId,
    required File target,
    required ArchiveFormat format,
    void Function(ExportProgress progress)? onProgress,
    CancelToken? cancel,
  }) async {
    final index = await projects.readProject(projectId);
    final folder = index.folderById(folderId) ?? (throw StateError('No folder $folderId in this project'));
    final layout = _layout(index, folderId);
    final root = safeName(folder.name, fallback: 'Folder');
    if (format == ArchiveFormat.zip) {
      _checkZipPaths(root, [for (final (_, path) in layout.files) path]);
    }
    final bytesTotal = layout.files.fold(0, (sum, f) => sum + f.$1.size);
    var bytesDone = 0;
    var fileNumber = 0;

    Stream<List<int>> tracked(Stream<List<int>> content) async* {
      fileNumber++;
      onProgress?.call(ExportProgress(projectName: folder.name, fileNumber: fileNumber, fileCount: layout.files.length, bytesDone: bytesDone, bytesTotal: bytesTotal));
      await for (final chunk in content) {
        cancel?.check();
        bytesDone += chunk.length;
        yield chunk;
      }
    }

    final entries = Stream.fromIterable([
      for (final (file, path) in layout.files)
        ArchiveEntry(path: '$root/$path', size: file.size, modified: file.addedAt, open: () => tracked(projects.openFile(projectId, file))),
    ]);
    final journalId = newId();
    try {
      await writeAtomically(
        target,
        onTemp: (temp) => projects.journalPut(ExportStarted(journalId, tempPath: temp.path)),
        (out) async {
          await for (final chunk in format == ArchiveFormat.zip ? zipStream(entries) : tarStream(entries)) {
            cancel?.check();
            await out.writeFrom(chunk);
          }
        },
        beforeDelete: PrivateFolders.overwriteWithZeros,
      );
    } finally {
      await projects.journalRemove(journalId);
    }
  }

  /// Saves a readable copy of one [file] of project [id] to [target],
  /// decrypted chunk by chunk straight into it. [target] is written
  /// atomically; if anything fails, the partial copy is overwritten with
  /// zeros and removed.
  Future<void> exportReadableCopy(String id, FileEntry file, File target) async {
    final journalId = newId();
    try {
      await _writeReadableCopy(id, file, target, (temp) => projects.journalPut(ExportStarted(journalId, tempPath: temp.path)));
    } finally {
      await projects.journalRemove(journalId);
    }
  }

  Future<void> _writeReadableCopy(String id, FileEntry file, File target, Future<void> Function(File temp) listTemp) => writeAtomically(
    target,
    onTemp: listTemp,
    (out) async {
      var written = 0;
      await for (final chunk in projects.openFile(id, file)) {
        written += chunk.length;
        await out.writeFrom(chunk);
      }
      if (written != file.size) {
        throw FormatException('${file.name}: expected ${file.size} bytes, got $written');
      }
    },
    beforeDelete: PrivateFolders.overwriteWithZeros,
  );

  /// The unlocked layout: `<Project>/project.json`, `<Project>/cover.<ext>`
  /// and `<Project>/files/<folders>/<real name>`, each file once. Names are
  /// made safe and unique within their folder.
  Stream<ArchiveEntry> _readableEntries(
    List<(String, ProjectIndex)> indexes,
    Stream<List<int>> Function(String projectName, Stream<List<int>> content) tracked,
  ) async* {
    final now = DateTime.now();
    final folders = _UniqueNames();
    for (final (id, index) in indexes) {
      final folder = folders.take(safeName(index.name, fallback: 'Project'));
      final cover = await projects.readCover(id, index);
      final coverName = cover == null ? null : 'cover.${_imageExtension(cover)}';
      final layout = _layout(index, null);
      final description = utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'name': index.name,
          'description': index.description,
          'tags': index.tags,
          'cover': coverName,
          'folders': layout.folders,
          'files': [
            for (final (file, path) in layout.files)
              {'file': 'files/$path', 'name': file.name, 'tags': file.tags, 'addedAt': file.addedAt.toIso8601String(), 'size': file.size},
          ],
        }),
      );
      yield ArchiveEntry(path: '$folder/project.json', size: description.length, modified: now, open: () => Stream.value(description));
      if (cover != null) {
        yield ArchiveEntry(path: '$folder/$coverName', size: cover.length, modified: index.changedAt, open: () => Stream.value(cover));
      }
      for (final (file, path) in layout.files) {
        yield ArchiveEntry(path: '$folder/files/$path', size: file.size, modified: file.addedAt, open: () => tracked(index.name, projects.openFile(id, file)));
      }
    }
  }

  /// Every file under folder [rootId] (null is the top level) with its path
  /// relative to it, and every folder's relative path (empty ones too). A name
  /// that's unsafe or taken, by a folder or a file in the same place, is
  /// changed, so the archive can be extracted anywhere. No recursion.
  static ({List<(FileEntry, String)> files, List<String> folders}) _layout(ProjectIndex index, String? rootId) {
    final files = <(FileEntry, String)>[];
    final folders = <String>[];
    final pending = [(rootId, '')];
    for (var i = 0; i < pending.length; i++) {
      final (folderId, prefix) = pending[i];
      final names = _UniqueNames();
      for (final folder in index.foldersIn(folderId)) {
        final name = names.take(safeName(folder.name, fallback: 'Folder'));
        folders.add('$prefix$name');
        pending.add((folder.id, '$prefix$name/'));
      }
      for (final file in index.filesIn(folderId)) {
        files.add((file, '$prefix${names.take(safeName(file.name, fallback: 'file'))}'));
      }
    }
    return (files: files, folders: folders);
  }

  /// ZIP can't hold a path of 65,535 bytes or more. [root] is the folder the
  /// paths sit under (with room for a "(2)" added to it).
  static void _checkZipPaths(String root, List<String> relativePaths) {
    for (final path in relativePaths) {
      if (utf8.encode('$root (99)/files/$path').length > 65535) {
        throw ArchivePathTooLong(path);
      }
    }
  }

  /// The locked layout (inside the encryption): `manifest.json` first, then
  /// `covers/<p>` and `files/<p>/<f>` in manifest order. Real names are only
  /// in the manifest.
  Stream<ArchiveEntry> _lockedEntries(
    List<(String, ProjectIndex)> indexes,
    Stream<List<int>> Function(String projectName, Stream<List<int>> content) tracked,
  ) async* {
    final now = DateTime.now();
    final covers = [for (final (id, index) in indexes) await projects.readCover(id, index)];
    // Folders are listed parents-first and referred to by their position, so
    // the manifest never carries the vault's own folder IDs.
    final orders = [for (final (_, index) in indexes) index.foldersParentsFirst()];
    final manifest = utf8.encode(
      jsonEncode({
        'app': 'Portfolio Jockey',
        'format': manifestFormat,
        'createdAt': now.toUtc().toIso8601String(),
        'projects': [
          for (var p = 0; p < indexes.length; p++)
            () {
              final index = indexes[p].$2;
              final position = {for (var i = 0; i < orders[p].length; i++) orders[p][i].id: i};
              return {
                'name': index.name,
                'description': index.description,
                'tags': index.tags,
                'cover': covers[p] == null ? null : 'covers/$p',
                'folders': [
                  for (final folder in orders[p]) {'name': folder.name, 'parent': folder.parentId == null ? null : position[folder.parentId], 'createdAt': folder.createdAt.toUtc().toIso8601String()},
                ],
                'files': [
                  for (var f = 0; f < index.files.length; f++)
                    {
                      'path': 'files/$p/$f',
                      'name': index.files[f].name,
                      'size': index.files[f].size,
                      'addedAt': index.files[f].addedAt.toIso8601String(),
                      'tags': index.files[f].tags,
                      'folder': index.files[f].folderId == null ? null : position[index.files[f].folderId],
                    },
                ],
              };
            }(),
        ],
      }),
    );
    yield ArchiveEntry(path: _manifestPath, size: manifest.length, modified: now, open: () => Stream.value(manifest));
    for (var p = 0; p < indexes.length; p++) {
      final (id, index) = indexes[p];
      final cover = covers[p];
      if (cover != null) {
        yield ArchiveEntry(path: 'covers/$p', size: cover.length, modified: now, open: () => Stream.value(cover));
      }
      for (var f = 0; f < index.files.length; f++) {
        final file = index.files[f];
        yield ArchiveEntry(path: 'files/$p/$f', size: file.size, modified: now, open: () => tracked(index.name, projects.openFile(id, file)));
      }
    }
  }

  /// Opens a locked export with its [passphrase] and reads its manifest.
  /// Throws [WrongExportPassphrase] for a wrong passphrase.
  Future<LockedExport> openLocked(File file, String passphrase) async {
    final key = await openLockedExport(file, passphrase);
    try {
      final reader = TarReader(readLockedExport(file, key));
      try {
        final first = await reader.next();
        if (first == null || first.path != _manifestPath) {
          throw const BadArchive('the manifest is missing');
        }
        final manifest = _parseManifest(await reader.readAll(first, maxBytes: _maxManifestBytes));
        final existing = {for (final p in (await projects.listProjects()).projects) p.index.name.toLowerCase()};
        final names = [for (final p in manifest) _uniqueAgainst(p.name, existing)];
        return LockedExport._(file, key, manifest, names);
      } finally {
        await reader.cancel();
      }
    } on Object {
      key.dispose();
      rethrow;
    }
  }

  /// Imports every project in [export] as a new project, with new file keys.
  /// If anything fails or is cancelled, every project created so far is
  /// deleted, so an import is all or nothing. Returns the new project IDs.
  Future<List<String>> import(LockedExport export, {void Function(ExportProgress progress)? onProgress, CancelToken? cancel}) async {
    final created = <String>[];
    // Each project is listed in the journal before it's created, so an
    // import cut off by a crash is undone at the next unlock too.
    final journalId = newId();
    final plan = export.projects;
    final expected = <String>{
      for (final p in plan) ...[?p.cover, for (final f in p.files) f.path],
    };
    final bytesTotal = plan.fold(0, (sum, p) => sum + p.files.fold(0, (s, f) => s + f.size));
    var bytesDone = 0;
    var fileNumber = 0;
    final folderIds = <int, List<String>>{};

    Future<String> projectFor(int p) async {
      while (created.length <= p) {
        final i = created.length;
        final projectId = newId();
        await projects.journalPut(ImportStarted(journalId, projectIds: [...created, projectId]));
        created.add(await projects.createProject(name: export.importNames[i], description: plan[i].description, id: projectId));
        if (plan[i].tags.isNotEmpty) {
          await projects.applyTagChanges(created[i], TagChanges(added: plan[i].tags));
        }
        if (plan[i].folders.isNotEmpty) {
          folderIds[i] = await projects.importFolders(created[i], [for (final f in plan[i].folders) (name: f.name, parent: f.parent, createdAt: f.createdAt)]);
        }
      }
      return created[p];
    }

    final reader = TarReader(readLockedExport(export.file, export._key));
    try {
      final first = await reader.next();
      if (first == null || first.path != _manifestPath) {
        throw const BadArchive('the manifest is missing');
      }
      await reader.readAll(first, maxBytes: _maxManifestBytes);
      for (var next = await reader.next(); next != null; next = await reader.next()) {
        final entry = next;
        cancel?.check();
        if (!expected.remove(entry.path)) {
          throw BadArchive('unexpected entry ${entry.path}');
        }
        final parts = entry.path.split('/');
        final p = int.parse(parts[1]);
        final id = await projectFor(p);
        if (parts[0] == 'covers') {
          final image = await reader.readAll(entry, maxBytes: _maxCoverBytes);
          await projects.updateDetails(id, description: plan[p].description, cover: ReplaceCover(image));
          continue;
        }
        final file = plan[p].files.firstWhere((f) => f.path == entry.path);
        if (file.size != entry.size) {
          throw BadArchive('${entry.path} has the wrong size');
        }
        fileNumber++;
        final content = reader.content(entry).map((chunk) {
          cancel?.check();
          bytesDone += chunk.length;
          onProgress?.call(ExportProgress(projectName: export.importNames[p], fileNumber: fileNumber, fileCount: export.fileCount, bytesDone: bytesDone, bytesTotal: bytesTotal));
          return chunk;
        });
        await projects.importFile(id, name: file.name, size: file.size, tags: file.tags, addedAt: file.addedAt, content: content, folderId: file.folder == null ? null : folderIds[p]![file.folder!]);
      }
      await reader.finish();
      if (expected.isNotEmpty) {
        throw BadArchive('${expected.length} files are missing');
      }
      if (plan.isNotEmpty) {
        await projectFor(plan.length - 1); // projects with no files or cover
      }
      await projects.journalRemove(journalId);
      return created;
    } on Object {
      await reader.cancel();
      for (final id in created) {
        await projects.deleteProject(id);
      }
      await projects.journalRemove(journalId);
      rethrow;
    }
  }

  static List<ManifestProject> _parseManifest(Uint8List bytes) {
    T field<T>(Map<String, Object?> json, String key) {
      final value = json[key];
      if (value is! T) {
        throw BadArchive('manifest field "$key" is missing or invalid');
      }
      return value;
    }

    List<String> strings(Map<String, Object?> json, String key) => [
      for (final v in field<List<Object?>>(json, key))
        if (v is String) v else throw BadArchive('manifest field "$key" is invalid'),
    ];

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const BadArchive('the manifest is not valid JSON');
    }
    if (json is! Map<String, Object?> || (json['format'] != 1 && json['format'] != manifestFormat)) {
      throw const BadArchive('unknown manifest format');
    }
    final hasFolders = json['format'] == manifestFormat;
    final result = <ManifestProject>[];
    final projectList = field<List<Object?>>(json, 'projects');
    for (var p = 0; p < projectList.length; p++) {
      final project = projectList[p];
      if (project is! Map<String, Object?>) {
        throw const BadArchive('invalid project in manifest');
      }
      final cover = project['cover'];
      if (cover != null && cover != 'covers/$p') {
        throw const BadArchive('invalid cover path');
      }
      final folders = <ManifestFolder>[];
      if (hasFolders) {
        final folderList = field<List<Object?>>(project, 'folders');
        for (var i = 0; i < folderList.length; i++) {
          final folder = folderList[i];
          if (folder is! Map<String, Object?>) {
            throw const BadArchive('invalid folder in manifest');
          }
          final parent = folder['parent'];
          // A parent always comes first, so no folder can end up inside itself.
          if (parent != null && (parent is! int || parent < 0 || parent >= i)) {
            throw const BadArchive('invalid folder parent');
          }
          final createdAt = DateTime.tryParse(field<String>(folder, 'createdAt'));
          if (createdAt == null) {
            throw const BadArchive('invalid folder date');
          }
          folders.add(ManifestFolder(name: field<String>(folder, 'name'), parent: parent as int?, createdAt: createdAt));
        }
      }
      final files = <ManifestFile>[];
      final fileList = field<List<Object?>>(project, 'files');
      for (var f = 0; f < fileList.length; f++) {
        final file = fileList[f];
        if (file is! Map<String, Object?> || file['path'] != 'files/$p/$f') {
          throw const BadArchive('invalid file in manifest');
        }
        final size = field<int>(file, 'size');
        final addedAt = DateTime.tryParse(field<String>(file, 'addedAt'));
        if (size < 0 || addedAt == null) {
          throw const BadArchive('invalid file size or date');
        }
        final folder = hasFolders ? file['folder'] : null;
        if (folder != null && (folder is! int || folder < 0 || folder >= folders.length)) {
          throw const BadArchive('a file is in a folder that does not exist');
        }
        files.add(
          ManifestFile(path: 'files/$p/$f', name: safeName(field<String>(file, 'name'), fallback: 'file'), size: size, addedAt: addedAt, tags: strings(file, 'tags'), folder: folder as int?),
        );
      }
      result.add(
        ManifestProject(
          name: field<String>(project, 'name').trim().isEmpty ? 'Imported project' : field<String>(project, 'name').trim(),
          description: field<String>(project, 'description'),
          tags: strings(project, 'tags'),
          cover: cover as String?,
          files: files,
          folders: folders,
        ),
      );
    }
    return result;
  }

  /// [name], or "name (2)", "name (3)"… if [taken] (lowercase) has it.
  /// The chosen name is added to [taken].
  static String _uniqueAgainst(String name, Set<String> taken) {
    var candidate = name;
    for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
      candidate = '$name ($n)';
    }
    taken.add(candidate.toLowerCase());
    return candidate;
  }
}

/// A file or folder name that's safe inside an archive and on any desktop:
/// no slashes, backslashes or control characters, not `.` or `..`, at most
/// 200 characters (keeping the extension).
String safeName(String name, {required String fallback}) {
  var clean = name.replaceAll(RegExp(r'[/\\\x00-\x1F\x7F]'), '_').trim();
  if (clean.isEmpty || clean == '.' || clean == '..') {
    clean = fallback;
  }
  if (clean.length > 200) {
    final dot = clean.lastIndexOf('.');
    final ext = dot > 0 && clean.length - dot <= 16 ? clean.substring(dot) : '';
    clean = '${clean.substring(0, 200 - ext.length)}$ext';
  }
  return clean;
}

/// Hands out names that are unique ignoring case: "a.txt", "a (2).txt"…
final class _UniqueNames {
  final Set<String> _taken = {};

  String take(String name) {
    final dot = name.lastIndexOf('.');
    final (stem, ext) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
    var candidate = name;
    for (var n = 2; _taken.contains(candidate.toLowerCase()); n++) {
      candidate = '$stem ($n)$ext';
    }
    _taken.add(candidate.toLowerCase());
    return candidate;
  }
}

/// The extension matching an image's first bytes.
String _imageExtension(Uint8List bytes) {
  bool starts(List<int> magic) => bytes.length >= magic.length && List.generate(magic.length, (i) => bytes[i] == magic[i]).every((b) => b);
  if (starts([0x89, 0x50, 0x4E, 0x47])) {
    return 'png';
  }
  if (starts([0xFF, 0xD8, 0xFF])) {
    return 'jpg';
  }
  if (starts([0x47, 0x49, 0x46])) {
    return 'gif';
  }
  if (starts([0x52, 0x49, 0x46, 0x46]) && bytes.length > 12 && ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'webp';
  }
  return 'img';
}
