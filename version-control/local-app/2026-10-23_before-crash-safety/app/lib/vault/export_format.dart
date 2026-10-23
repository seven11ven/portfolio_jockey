import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/atomic_write.dart';
import 'package:portfolio_jockey/vault/blob_stream.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

// Locked export layout (`.pjx`):
//    0   4  magic "PJEX"
//    4   1  format version (1)
//    5   3  reserved, zero
//    8   8  Argon2id opslimit (little-endian)
//   16   8  Argon2id memlimit in bytes (little-endian)
//   24  16  salt
//   40   …  the content, encrypted as by encryptTo() in blob_stream.dart, with
//           a key derived from the export's own passphrase.
// The header isn't authenticated separately: the settings and salt only feed
// the key derivation, so changing them gives a different key, and the first
// chunk then fails its integrity check. The magic, version and reserved bytes
// are checked exactly.

const List<int> _magic = [0x50, 0x4a, 0x45, 0x58]; // "PJEX"
const int _formatVersion = 1;
const int headerLength = 40;

/// The export's passphrase is wrong, or the export is damaged. The two look
/// the same: either way the first chunk fails its integrity check.
class WrongExportPassphrase extends VaultException {
  const WrongExportPassphrase() : super('Wrong passphrase for this export, or the export is damaged');
}

/// The key that opens one locked export, in guarded memory. Dispose it after
/// use.
final class ExportKey {
  ExportKey._(this._key);

  final SecureBuffer _key;

  void dispose() => _key.dispose();
}

/// Writes [content] to [target] as a locked export, protected by [passphrase]
/// (Argon2id with [kdf], default MODERATE). [target] is written atomically.
Future<void> writeLockedExport(File target, String passphrase, Stream<List<int>> content, {KdfParams? kdf}) async {
  final params = kdf ?? KdfParams.moderate();
  final sodium = Sodium.instance;
  final salt = sodium.randomBytes(sodium.pwhashSaltBytes);
  final key = await _deriveKey(passphrase, salt, params);
  try {
    await writeAtomically(target, (out) async {
      await out.writeFrom(_header(params, salt));
      await encryptTo(out, content, key._key);
    });
  } finally {
    key.dispose();
  }
}

/// Derives the key for [source] from [passphrase], and checks it against the
/// first chunk. Throws [WrongExportPassphrase] if it doesn't open the export,
/// and [VaultFormatError] if [source] isn't a locked export.
Future<ExportKey> openLockedExport(File source, String passphrase) async {
  final file = await source.open();
  try {
    final (params, salt) = _readHeader(await file.read(headerLength));
    final key = await _deriveKey(passphrase, salt, params);
    try {
      // Reading one chunk proves the key without decrypting the whole export.
      await decryptFrom(file, key._key).first;
      return key;
    } on TamperedData {
      key.dispose();
      throw const WrongExportPassphrase();
    } on Object {
      key.dispose();
      rethrow;
    }
  } finally {
    await file.close();
  }
}

/// Decrypts the content of [source] with [key] from [openLockedExport]. As
/// with every decryption stream, if it ends in an error, everything already
/// received must be thrown away.
Stream<Uint8List> readLockedExport(File source, ExportKey key) async* {
  final file = await source.open();
  try {
    _readHeader(await file.read(headerLength));
    yield* decryptFrom(file, key._key);
  } finally {
    await file.close();
  }
}

Future<ExportKey> _deriveKey(String passphrase, Uint8List salt, KdfParams params) async {
  if (passphrase.isEmpty) {
    throw ArgumentError.value('', 'passphrase', 'must not be empty');
  }
  // As for the vault passphrase: the UTF-8 copy is wiped once it's in
  // guarded memory, and the guarded copy as soon as the key is derived.
  final buffer = SecureBuffer.takeBytes(utf8.encode(passphrase));
  try {
    return ExportKey._(await deriveKey(buffer, salt, params, length: Sodium.instance.streamKeyBytes));
  } finally {
    buffer.dispose();
  }
}

Uint8List _header(KdfParams params, Uint8List salt) {
  final bytes = Uint8List(headerLength)
    ..setAll(0, _magic)
    ..[4] = _formatVersion
    ..setAll(24, salt);
  ByteData.sublistView(bytes)
    ..setUint64(8, params.opsLimit, Endian.little)
    ..setUint64(16, params.memLimit, Endian.little);
  return bytes;
}

(KdfParams, Uint8List) _readHeader(Uint8List bytes) {
  if (bytes.length < headerLength) {
    throw const VaultFormatError('Not a Portfolio Jockey export: the file is too short');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const VaultFormatError('Not a Portfolio Jockey export');
    }
  }
  if (bytes[4] != _formatVersion) {
    throw VaultFormatError('This export was made by a newer version of Portfolio Jockey (format ${bytes[4]})');
  }
  if (bytes[5] != 0 || bytes[6] != 0 || bytes[7] != 0) {
    throw const VaultFormatError('The export header is damaged');
  }
  final data = ByteData.sublistView(bytes);
  final params = KdfParams(opsLimit: data.getUint64(8, Endian.little), memLimit: data.getUint64(16, Endian.little))..checkBounds();
  return (params, Uint8List.fromList(bytes.sublist(24, 24 + Sodium.instance.pwhashSaltBytes)));
}
