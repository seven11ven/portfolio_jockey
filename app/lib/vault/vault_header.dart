import 'dart:typed_data';

import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/kdf.dart';

/// The `.pj/vault` file: the Argon2id settings and the master key, encrypted
/// with the key derived from the passphrase. 112 bytes, little-endian:
///
///      0   4  magic "PJVT"
///      4   1  format version (1)
///      5   1  key derivation (1 = Argon2id v1.3)
///      6   2  reserved, zero
///      8   8  Argon2id opslimit
///     16   8  Argon2id memlimit
///     24  16  salt
///     40  24  nonce
///     64  48  master key, XChaCha20-Poly1305 encrypted (32 bytes + 16-byte tag)
///
/// Bytes 0–63 are the associated data for the master key, so changing any of
/// them (the settings, salt or nonce) makes unlocking fail.
final class VaultHeader {
  VaultHeader({required this.kdf, required this.salt, required this.nonce, required this.wrappedKey});

  factory VaultHeader.parse(Uint8List bytes) {
    if (bytes.length != length) {
      throw VaultFormatError('Vault file is ${bytes.length} bytes, expected $length');
    }
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const VaultFormatError('Not a Portfolio Jockey vault file');
      }
    }
    if (bytes[4] != formatVersion) {
      throw VaultFormatError('Unsupported vault format version ${bytes[4]}');
    }
    if (bytes[5] != _argon2id13 || data.getUint16(6, Endian.little) != 0) {
      throw const VaultFormatError('Unsupported key derivation settings');
    }
    final kdf = KdfParams(opsLimit: data.getUint64(8, Endian.little), memLimit: data.getUint64(16, Endian.little))..checkBounds();
    return VaultHeader(
      kdf: kdf,
      salt: Uint8List.fromList(bytes.sublist(24, 40)),
      nonce: Uint8List.fromList(bytes.sublist(40, 64)),
      wrappedKey: Uint8List.fromList(bytes.sublist(64, length)),
    );
  }

  static const int length = 112;
  static const int formatVersion = 1;
  static const List<int> _magic = [0x50, 0x4a, 0x56, 0x54]; // "PJVT"
  static const int _argon2id13 = 1;

  final KdfParams kdf;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List wrappedKey;

  /// Bytes 0–63, which the master key's encryption authenticates.
  Uint8List get associatedData {
    final bytes = Uint8List(64);
    final data = ByteData.sublistView(bytes);
    bytes.setAll(0, _magic);
    bytes[4] = formatVersion;
    bytes[5] = _argon2id13;
    data.setUint64(8, kdf.opsLimit, Endian.little);
    data.setUint64(16, kdf.memLimit, Endian.little);
    bytes.setAll(24, salt);
    bytes.setAll(40, nonce);
    return bytes;
  }

  Uint8List toBytes() => Uint8List(length)
    ..setAll(0, associatedData)
    ..setAll(64, wrappedKey);
}
