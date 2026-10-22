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
  ProjectIndex({required this.name, this.description = '', List<String>? tags, List<FileEntry>? files, this.coverKey, DateTime? changedAt})
    : tags = tags ?? [],
      files = files ?? [],
      changedAt = (changedAt ?? DateTime.now()).toUtc();

  factory ProjectIndex.fromJson(Map<String, Object?> json) => ProjectIndex(
    name: _field<String>(json, 'name'),
    description: _field<String>(json, 'description'),
    tags: _field<List<Object?>>(json, 'tags').map(_asString).toList(),
    files: _field<List<Object?>>(json, 'files').map((f) => FileEntry.fromJson(_asMap(f))).toList(),
    coverKey: json['coverKey'] as String?,
    changedAt: _optionalDate(json, 'changedAt'),
  );

  String name;
  String description;
  final List<String> tags;
  final List<FileEntry> files;

  /// The cover art's key (base64), or null if the project has no cover.
  String? coverKey;

  /// When the project was last changed. Updated only by confirmed changes;
  /// opening a project never writes to disk.
  DateTime changedAt;

  /// Every file's size added up, in bytes.
  int get totalSize => files.fold(0, (sum, f) => sum + f.size);

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'tags': tags,
    'files': [for (final f in files) f.toJson()],
    'coverKey': coverKey,
    'changedAt': changedAt.toIso8601String(),
  };
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
  }) : tags = tags ?? [] {
    checkId(id);
  }

  /// A new entry with a fresh ID and a fresh random key.
  factory FileEntry.create({required String name, required int size, List<String>? tags, String? originalPath}) => FileEntry(
    id: newId(),
    name: name,
    size: size,
    addedAt: DateTime.now().toUtc(),
    key: base64.encode(Sodium.instance.randomBytes(Sodium.instance.streamKeyBytes)),
    tags: tags,
    originalPath: originalPath,
  );

  factory FileEntry.fromJson(Map<String, Object?> json) => FileEntry(
    id: _field<String>(json, 'id'),
    name: _field<String>(json, 'name'),
    size: _field<int>(json, 'size'),
    addedAt: DateTime.parse(_field<String>(json, 'addedAt')),
    key: _field<String>(json, 'key'),
    tags: _field<List<Object?>>(json, 'tags').map(_asString).toList(),
    originalPath: json['originalPath'] as String?,
  );

  final String id;
  String name;
  final int size;
  final DateTime addedAt;
  final String key;
  final List<String> tags;

  /// Where the file was added from, for "Delete from device". Like everything
  /// in the index, it's stored encrypted. Null if unknown.
  final String? originalPath;

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

String _asString(Object? value) => value is String ? value : throw const FormatException('Expected a string');

Map<String, Object?> _asMap(Object? value) => value is Map<String, Object?> ? value : throw const FormatException('Expected an object');
