import 'dart:convert';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/aead.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

/// One piece of work that touches the disk in several steps and must be
/// tidied up if the app stops halfway (a crash or a power cut). It holds
/// paths and IDs only, never file contents; the journal is encrypted because
/// those can be private.
sealed class JournalEntry {
  const JournalEntry(this.id);

  /// Which entry this is, so it can be removed when the work finishes.
  final String id;

  Map<String, Object?> toJson();

  static JournalEntry fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    return switch (json['kind']) {
      'export' => ExportStarted(id, tempPath: json['temp']! as String),
      'import' => ImportStarted(id, projectIds: [for (final p in json['projects']! as List<Object?>) p! as String]),
      'move' => MoveStarted(id, source: json['source']! as String, target: json['target']! as String),
      'edit' => EditStarted(id, projectName: json['project']! as String, fileName: json['file']! as String),
      final kind => throw VaultFormatError('Unknown journal entry "$kind"'),
    };
  }
}

/// An export is being written to [tempPath], next to where the user saved it.
/// If it's still listed, the file there is unfinished (and for an unlocked
/// export, readable), so it's overwritten with zeros and deleted.
final class ExportStarted extends JournalEntry {
  const ExportStarted(super.id, {required this.tempPath});

  final String tempPath;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'export', 'temp': tempPath};
}

/// An import is creating [projectIds]. If it's still listed, the import
/// didn't finish, so those projects are deleted: imports are all or nothing.
final class ImportStarted extends JournalEntry {
  const ImportStarted(super.id, {required this.projectIds});

  final List<String> projectIds;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'import', 'projects': projectIds};
}

/// The vault is being moved from [source] to [target]. If it's still listed,
/// whichever of the two isn't in use is a leftover copy.
final class MoveStarted extends JournalEntry {
  const MoveStarted(super.id, {required this.source, required this.target});

  final String source;
  final String target;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'move', 'source': source, 'target': target};
}

/// A file is open in another app. If it's still listed and its readable copy
/// is gone (inside a Flatpak, the sandbox's memory folder doesn't outlive the
/// app), the user is told that the edit's changes weren't saved.
final class EditStarted extends JournalEntry {
  const EditStarted(super.id, {required this.projectName, required this.fileName});

  final String projectName;
  final String fileName;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'edit', 'project': projectName, 'file': fileName};
}

// journal.enc layout (in the vault's .pj folder):
//    0   4  magic "PJJN"
//    4   1  format version (1)
//    5   3  reserved, zero
//    8  24  nonce
//   32   …  the entries as UTF-8 JSON, XChaCha20-Poly1305 encrypted (+ 16-byte tag)
// The associated data is bytes 0–7 plus "journal", so the journal can't be
// swapped with an index (whose associated data ends in a project ID).
const List<int> _magic = [0x50, 0x4a, 0x4a, 0x4e]; // "PJJN"
const int _formatVersion = 1;
const int _prefixLength = 8;

Uint8List encryptJournal(List<JournalEntry> entries, {required SecureBuffer masterKey}) {
  final sodium = Sodium.instance;
  final prefix = Uint8List(_prefixLength)
    ..setAll(0, _magic)
    ..[4] = _formatVersion;
  final nonce = sodium.randomBytes(sodium.aeadNonceBytes);
  final plaintext = utf8.encode(jsonEncode([for (final e in entries) e.toJson()]));
  try {
    final ciphertext = aeadEncrypt(plaintext, ad: _associatedData(prefix), nonce: nonce, key: masterKey);
    return Uint8List(_prefixLength + nonce.length + ciphertext.length)
      ..setAll(0, prefix)
      ..setAll(_prefixLength, nonce)
      ..setAll(_prefixLength + nonce.length, ciphertext);
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

/// Throws [VaultFormatError] if it isn't a journal, and [TamperedData] if it
/// was changed.
List<JournalEntry> decryptJournal(Uint8List bytes, {required SecureBuffer masterKey}) {
  final sodium = Sodium.instance;
  final headerLength = _prefixLength + sodium.aeadNonceBytes;
  if (bytes.length < headerLength + sodium.aeadTagBytes) {
    throw const VaultFormatError('Journal file is too short');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const VaultFormatError('Not a journal file');
    }
  }
  if (bytes[4] != _formatVersion) {
    throw VaultFormatError('Unsupported journal format version ${bytes[4]}');
  }
  final prefix = Uint8List.sublistView(bytes, 0, _prefixLength);
  final plaintext = aeadDecrypt(
    Uint8List.sublistView(bytes, headerLength),
    ad: _associatedData(prefix),
    nonce: Uint8List.sublistView(bytes, _prefixLength, headerLength),
    key: masterKey,
  );
  if (plaintext == null) {
    throw const TamperedData('Journal failed its integrity check');
  }
  try {
    final list = jsonDecode(utf8.decode(plaintext)) as List<Object?>;
    return [for (final e in list) JournalEntry.fromJson((e! as Map).cast<String, Object?>())];
  } on Object catch (e) {
    if (e is VaultFormatError) {
      rethrow;
    }
    throw VaultFormatError('Journal is not valid: $e');
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

Uint8List _associatedData(Uint8List prefix) => Uint8List.fromList([...prefix, ...ascii.encode('journal')]);
