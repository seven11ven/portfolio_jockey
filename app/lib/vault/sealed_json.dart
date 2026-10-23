import 'dart:convert';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/aead.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

// A small JSON file in the vault's .pj folder, sealed under the master key
// (the journal, the inbox):
//    0   4  magic (four ASCII letters, one per kind of file)
//    4   1  format version (1)
//    5   3  reserved, zero
//    8  24  nonce
//   32   …  the JSON as UTF-8, XChaCha20-Poly1305 encrypted (+ 16-byte tag)
// The associated data is bytes 0–7 plus the file's label, so one kind of
// file can't be swapped for another, or for a project index.
const int _formatVersion = 1;
const int _prefixLength = 8;

Uint8List sealJson(Object? json, {required String magic, required String label, required SecureBuffer masterKey}) {
  final sodium = Sodium.instance;
  final prefix = Uint8List(_prefixLength)
    ..setAll(0, ascii.encode(magic))
    ..[4] = _formatVersion;
  final nonce = sodium.randomBytes(sodium.aeadNonceBytes);
  final plaintext = utf8.encode(jsonEncode(json));
  try {
    final ciphertext = aeadEncrypt(plaintext, ad: _associatedData(prefix, label), nonce: nonce, key: masterKey);
    return Uint8List(_prefixLength + nonce.length + ciphertext.length)
      ..setAll(0, prefix)
      ..setAll(_prefixLength, nonce)
      ..setAll(_prefixLength + nonce.length, ciphertext);
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

/// Throws [VaultFormatError] if it isn't this kind of file, and
/// [TamperedData] if it was changed.
Object? openSealedJson(Uint8List bytes, {required String magic, required String label, required SecureBuffer masterKey}) {
  final sodium = Sodium.instance;
  final headerLength = _prefixLength + sodium.aeadNonceBytes;
  if (bytes.length < headerLength + sodium.aeadTagBytes) {
    throw VaultFormatError('The $label file is too short');
  }
  final expected = ascii.encode(magic);
  for (var i = 0; i < expected.length; i++) {
    if (bytes[i] != expected[i]) {
      throw VaultFormatError('Not a $label file');
    }
  }
  if (bytes[4] != _formatVersion) {
    throw VaultFormatError('Unsupported $label format version ${bytes[4]}');
  }
  final prefix = Uint8List.sublistView(bytes, 0, _prefixLength);
  final plaintext = aeadDecrypt(
    Uint8List.sublistView(bytes, headerLength),
    ad: _associatedData(prefix, label),
    nonce: Uint8List.sublistView(bytes, _prefixLength, headerLength),
    key: masterKey,
  );
  if (plaintext == null) {
    throw TamperedData('The $label failed its integrity check');
  }
  try {
    return jsonDecode(utf8.decode(plaintext));
  } on FormatException catch (e) {
    throw VaultFormatError('The $label is not valid: ${e.message}');
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

Uint8List _associatedData(Uint8List prefix, String label) => Uint8List.fromList([...prefix, ...ascii.encode(label)]);
