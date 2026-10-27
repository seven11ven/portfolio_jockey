import 'dart:convert';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/aead.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

/// Everything about a project except its files' contents: its name,
/// description, tags and file list. Stored encrypted as `index.enc`.
final class ProjectIndex {
  ProjectIndex({required this.name, this.description = '', List<String>? tags, List<FileEntry>? files, List<FolderEntry>? folders, this.coverKey, this.coverId, DateTime? changedAt})
    : tags = tags ?? [],
      files = files ?? [],
      folders = folders ?? [],
      changedAt = (changedAt ?? DateTime.now()).toUtc();

  factory ProjectIndex.fromJson(Map<String, Object?> json) {
    final index = ProjectIndex(
      name: _field<String>(json, 'name'),
      description: _field<String>(json, 'description'),
      tags: _field<List<Object?>>(json, 'tags').map(_asString).toList(),
      files: _field<List<Object?>>(json, 'files').map((f) => FileEntry.fromJson(_asMap(f))).toList(),
      folders: json['folders'] == null ? null : _field<List<Object?>>(json, 'folders').map((f) => FolderEntry.fromJson(_asMap(f))).toList(),
      coverKey: json['coverKey'] as String?,
      coverId: json['coverId'] as String?,
      changedAt: _optionalDate(json, 'changedAt'),
    );
    index.validate();
    return index;
  }

  String name;
  String description;
  final List<String> tags;
  final List<FileEntry> files;

  /// Every folder in the project, at any depth. Indexes from before folders
  /// existed have none, and all their files sit at the top level.
  final List<FolderEntry> folders;

  /// The cover art's key (base64), or null if the project has no cover.
  String? coverKey;

  /// Which cover file holds the cover: `cover-<coverId>.enc`, or `cover.enc`
  /// when null (vaults from before 2026-10-23). A new cover gets a new ID, so
  /// the old one stays readable until the index points at the new one.
  String? coverId;

  /// When the project was last changed. Updated only by confirmed changes;
  /// opening a project never writes to disk.
  DateTime changedAt;

  /// Every file's size added up, in bytes.
  int get totalSize => files.fold(0, (sum, f) => sum + f.size);

  /// Throws a [FormatException] if the folders or where files sit are unsafe:
  /// a bad or repeated ID or name, a missing parent, a loop, or a file in a
  /// folder that doesn't exist. Loading and saving both check, so what's
  /// written can always be read back. Nothing here recurses, so any depth works.
  void validate() {
    final byId = <String, FolderEntry>{};
    for (final folder in folders) {
      if (!isValidId(folder.id)) {
        throw const FormatException('A folder has an ID that is not a vault ID');
      }
      if (byId.containsKey(folder.id)) {
        throw const FormatException('Two folders share one ID');
      }
      final problem = folderNameProblem(folder.name);
      if (problem != null) {
        throw FormatException(problem);
      }
      byId[folder.id] = folder;
    }
    for (final folder in folders) {
      final parent = folder.parentId;
      if (parent != null && !byId.containsKey(parent)) {
        throw const FormatException('A folder is inside a folder that does not exist');
      }
    }
    final checked = <String>{};
    for (final start in folders) {
      final walked = <String>{};
      String? current = start.id;
      while (current != null && !checked.contains(current)) {
        if (!walked.add(current)) {
          throw const FormatException('The folders contain a loop');
        }
        current = byId[current]!.parentId;
      }
      checked.addAll(walked);
    }
    for (final file in files) {
      final folder = file.folderId;
      if (folder != null && !byId.containsKey(folder)) {
        throw const FormatException('A file is in a folder that does not exist');
      }
    }
  }

  FolderEntry? folderById(String id) {
    for (final folder in folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }

  /// The folders directly inside [parentId] (null is the top level).
  List<FolderEntry> foldersIn(String? parentId) => [for (final f in folders) if (f.parentId == parentId) f];

  /// The files directly inside [folderId] (null is the top level).
  List<FileEntry> filesIn(String? folderId) => [for (final f in files) if (f.folderId == folderId) f];

  /// The folders from the top level down to [folderId], inclusive; empty for the top level.
  List<FolderEntry> pathTo(String? folderId) {
    final byId = {for (final f in folders) f.id: f};
    final path = <FolderEntry>[];
    var current = folderId;
    while (current != null && path.length <= folders.length) {
      final folder = byId[current];
      if (folder == null) {
        break;
      }
      path.add(folder);
      current = folder.parentId;
    }
    return path.reversed.toList();
  }

  /// [folderId] and the ID of every folder inside it, however deep.
  Set<String> subtreeIds(String folderId) {
    final children = <String?, List<String>>{};
    for (final folder in folders) {
      children.putIfAbsent(folder.parentId, () => []).add(folder.id);
    }
    final found = <String>{folderId};
    final pending = [folderId];
    while (pending.isNotEmpty) {
      for (final child in children[pending.removeLast()] ?? const <String>[]) {
        if (found.add(child)) {
          pending.add(child);
        }
      }
    }
    return found;
  }

  /// What a folder holds, counting everything inside it at any depth.
  FolderStats statsOf(String folderId) {
    final inside = subtreeIds(folderId);
    var fileCount = 0;
    var bytes = 0;
    for (final file in files) {
      if (inside.contains(file.folderId)) {
        fileCount++;
        bytes += file.size;
      }
    }
    return FolderStats(files: fileCount, folders: inside.length - 1, bytes: bytes);
  }

  /// What every folder holds, for the whole project in one pass (the folder
  /// cards and rows need all of them). Same numbers as [statsOf].
  Map<String, FolderStats> allFolderStats() {
    final ownFiles = <String, int>{};
    final ownBytes = <String, int>{};
    for (final file in files) {
      final folder = file.folderId;
      if (folder != null) {
        ownFiles[folder] = (ownFiles[folder] ?? 0) + 1;
        ownBytes[folder] = (ownBytes[folder] ?? 0) + file.size;
      }
    }
    final children = <String?, List<FolderEntry>>{};
    for (final folder in folders) {
      children.putIfAbsent(folder.parentId, () => []).add(folder);
    }
    // Parents come before their children, so walking it backwards adds each folder to its parent.
    final order = [...children[null] ?? const <FolderEntry>[]];
    for (var i = 0; i < order.length; i++) {
      order.addAll(children[order[i].id] ?? const <FolderEntry>[]);
    }
    final fileTotal = {for (final f in folders) f.id: ownFiles[f.id] ?? 0};
    final byteTotal = {for (final f in folders) f.id: ownBytes[f.id] ?? 0};
    final folderTotal = {for (final f in folders) f.id: 0};
    for (final folder in order.reversed) {
      final parent = folder.parentId;
      if (parent != null) {
        fileTotal[parent] = fileTotal[parent]! + fileTotal[folder.id]!;
        byteTotal[parent] = byteTotal[parent]! + byteTotal[folder.id]!;
        folderTotal[parent] = folderTotal[parent]! + folderTotal[folder.id]! + 1;
      }
    }
    return {for (final f in folders) f.id: FolderStats(files: fileTotal[f.id]!, folders: folderTotal[f.id]!, bytes: byteTotal[f.id]!)};
  }

  /// Whether the folder may go into [newParentId] (null is the top level): never into itself or its own contents.
  bool canMoveFolder(String folderId, String? newParentId) => newParentId == null || !subtreeIds(folderId).contains(newParentId);

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'tags': tags,
    'files': [for (final f in files) f.toJson()],
    if (folders.isNotEmpty) 'folders': [for (final f in folders) f.toJson()],
    'coverKey': coverKey,
    if (coverId != null) 'coverId': coverId,
    'changedAt': changedAt.toIso8601String(),
  };
}

/// Why [name] can't be a folder's name, or null if it can. There's no length
/// limit; only names that would break paths or exports are refused.
String? folderNameProblem(String name) {
  if (name.trim().isEmpty) {
    return 'A folder needs a name.';
  }
  if (name.trim() == '.' || name.trim() == '..') {
    return 'A folder can\'t be called "." or "..".';
  }
  for (final unit in name.codeUnits) {
    if (unit == 0x2f) {
      return 'A folder name can\'t contain a slash.';
    }
    if (unit < 0x20 || unit == 0x7f) {
      return 'A folder name can\'t contain control characters.';
    }
  }
  return null;
}

/// What a folder holds, counting everything inside it at any depth.
final class FolderStats {
  const FolderStats({required this.files, required this.folders, required this.bytes});

  final int files;

  /// Folders inside it, not counting itself.
  final int folders;
  final int bytes;
}

/// A folder inside a project. Folders exist only in the encrypted index: they
/// never change where a file's encrypted contents are stored.
final class FolderEntry {
  FolderEntry({required this.id, required this.name, required this.createdAt, this.parentId}) {
    checkId(id);
  }

  /// A new folder with a fresh ID. [parentId] null puts it at the top level.
  factory FolderEntry.create({required String name, String? parentId, DateTime? createdAt}) =>
      FolderEntry(id: newId(), name: name, parentId: parentId, createdAt: (createdAt ?? DateTime.now()).toUtc());

  factory FolderEntry.fromJson(Map<String, Object?> json) {
    final id = _field<String>(json, 'id');
    if (!isValidId(id)) {
      throw const FormatException('A folder has an ID that is not a vault ID');
    }
    return FolderEntry(
      id: id,
      name: _field<String>(json, 'name'),
      parentId: _optionalString(json, 'parentId'),
      createdAt: DateTime.parse(_field<String>(json, 'createdAt')).toUtc(),
    );
  }

  final String id;
  String name;

  /// The folder this one is inside, or null at the top level.
  String? parentId;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {'id': id, 'name': name, if (parentId != null) 'parentId': parentId, 'createdAt': createdAt.toUtc().toIso8601String()};
}

/// One file in a project. [key] is the file's own random key (base64); its
/// contents are in `blobs/<id>.enc`.
final class FileEntry {
  FileEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.addedAt,
    required this.key,
    List<String>? tags,
    this.originalPath,
    this.originalShownPath,
    this.blobId,
    this.folderId,
  }) : tags = tags ?? [] {
    checkId(id);
  }

  /// A new entry with a fresh ID and a fresh random key. [addedAt] defaults
  /// to now; imports keep the original date.
  factory FileEntry.create({required String name, required int size, List<String>? tags, String? originalPath, String? originalShownPath, DateTime? addedAt, String? folderId}) => FileEntry(
    id: newId(),
    name: name,
    size: size,
    addedAt: (addedAt ?? DateTime.now()).toUtc(),
    key: base64.encode(Sodium.instance.randomBytes(Sodium.instance.streamKeyBytes)),
    tags: tags,
    originalPath: originalPath,
    originalShownPath: originalShownPath,
    folderId: folderId,
  );

  factory FileEntry.fromJson(Map<String, Object?> json) => FileEntry(
    id: _field<String>(json, 'id'),
    name: _field<String>(json, 'name'),
    size: _field<int>(json, 'size'),
    addedAt: DateTime.parse(_field<String>(json, 'addedAt')),
    key: _field<String>(json, 'key'),
    tags: _field<List<Object?>>(json, 'tags').map(_asString).toList(),
    originalPath: json['originalPath'] as String?,
    originalShownPath: json['originalShownPath'] as String?,
    blobId: json['blobId'] as String?,
    folderId: _optionalString(json, 'folderId'),
  );

  final String id;
  String name;
  int size;
  final DateTime addedAt;
  final String key;
  final List<String> tags;

  /// Where the file was added from, for "Delete from device". Like everything
  /// in the index, it's stored encrypted. Null if unknown.
  final String? originalPath;

  /// The original's real location when [originalPath] is a document portal
  /// path (inside a Flatpak). Only shown; Trash and checks use [originalPath].
  final String? originalShownPath;

  /// Which encrypted file holds the contents: `blobs/<blobId>.enc`, or the
  /// file's [id] when null (vaults from before 2026-10-23). Saving an edit
  /// writes a new blob under a new ID, then points the index at it, so a crash
  /// leaves either the old version or the new one, never a mix.
  String? blobId;

  /// The folder the file is in, or null at the top level (see [ProjectIndex.folders]).
  String? folderId;

  /// The blob that holds the contents.
  String get blob => blobId ?? id;

  /// The original's location as the user should see it.
  String? get shownOriginal => originalShownPath ?? originalPath;

  /// The file's key, copied into guarded memory. Dispose it after use.
  SecureBuffer openKey() => SecureBuffer.takeBytes(base64.decode(key));

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'addedAt': addedAt.toUtc().toIso8601String(),
    'key': key,
    'tags': tags,
    'originalPath': originalPath,
    if (originalShownPath != null) 'originalShownPath': originalShownPath,
    if (blobId != null) 'blobId': blobId,
    if (folderId != null) 'folderId': folderId,
  };
}

// index.enc layout:
//    0   4  magic "PJIX"
//    4   1  format version (1)
//    5   3  reserved, zero
//    8  24  nonce
//   32   …  the index as UTF-8 JSON, XChaCha20-Poly1305 encrypted (+ 16-byte tag)
// The associated data is bytes 0–7 plus the project ID, so an index can't be
// moved to another project's folder without failing its integrity check.
const List<int> _magic = [0x50, 0x4a, 0x49, 0x58]; // "PJIX"
const int _formatVersion = 1;
const int _prefixLength = 8;

/// Encrypts [index] for the project [projectId] under the master key.
Uint8List encryptIndex(ProjectIndex index, {required String projectId, required SecureBuffer masterKey}) {
  checkId(projectId);
  index.validate();
  final sodium = Sodium.instance;
  final prefix = Uint8List(_prefixLength)
    ..setAll(0, _magic)
    ..[4] = _formatVersion;
  final nonce = sodium.randomBytes(sodium.aeadNonceBytes);
  final plaintext = utf8.encode(jsonEncode(index.toJson()));
  try {
    final ciphertext = aeadEncrypt(plaintext, ad: _associatedData(prefix, projectId), nonce: nonce, key: masterKey);
    return Uint8List(_prefixLength + nonce.length + ciphertext.length)
      ..setAll(0, prefix)
      ..setAll(_prefixLength, nonce)
      ..setAll(_prefixLength + nonce.length, ciphertext);
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

/// Decrypts an `index.enc` that belongs to [projectId].
///
/// Throws [VaultFormatError] if it isn't an index file, and [TamperedData] if
/// it was changed or belongs to another project.
ProjectIndex decryptIndex(Uint8List bytes, {required String projectId, required SecureBuffer masterKey}) {
  checkId(projectId);
  final sodium = Sodium.instance;
  final headerLength = _prefixLength + sodium.aeadNonceBytes;
  if (bytes.length < headerLength + sodium.aeadTagBytes) {
    throw const VaultFormatError('Index file is too short');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const VaultFormatError('Not a project index file');
    }
  }
  if (bytes[4] != _formatVersion) {
    throw VaultFormatError('Unsupported index format version ${bytes[4]}');
  }
  final prefix = Uint8List.sublistView(bytes, 0, _prefixLength);
  final plaintext = aeadDecrypt(
    Uint8List.sublistView(bytes, headerLength),
    ad: _associatedData(prefix, projectId),
    nonce: Uint8List.sublistView(bytes, _prefixLength, headerLength),
    key: masterKey,
  );
  if (plaintext == null) {
    throw const TamperedData('Project index failed its integrity check');
  }
  try {
    return ProjectIndex.fromJson(_asMap(jsonDecode(utf8.decode(plaintext))));
  } on FormatException catch (e) {
    throw VaultFormatError('Project index is not valid: ${e.message}');
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

Uint8List _associatedData(Uint8List prefix, String projectId) => Uint8List.fromList([...prefix, ...ascii.encode(projectId)]);

T _field<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! T) {
    throw FormatException('"$key" is missing or has the wrong type');
  }
  return value;
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('"$key" has the wrong type');
  }
  return DateTime.parse(value);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('"$key" has the wrong type');
  }
  return value;
}

String _asString(Object? value) => value is String ? value : throw const FormatException('Expected a string');

Map<String, Object?> _asMap(Object? value) => value is Map<String, Object?> ? value : throw const FormatException('Expected an object');
