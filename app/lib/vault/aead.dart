import 'dart:ffi';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/scratch_buffer.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

// XChaCha20-Poly1305 (IETF) for small records: the wrapped master key and
// project indexes. [ad] is authenticated but not encrypted, so changing it
// makes decryption fail.

/// Encrypts [message]. The result is the ciphertext followed by the tag.
Uint8List aeadEncrypt(Uint8List message, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final input = ScratchBuffer.from(message);
  try {
    return _encrypt(input, ad: ad, nonce: nonce, key: key);
  } finally {
    input.free();
  }
}

/// Encrypts the contents of [secret] (e.g. the master key) without copying
/// them into Dart's heap.
Uint8List aeadEncryptSecret(SecureBuffer secret, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final input = ScratchBuffer(secret.length);
  try {
    secret.use((pointer) => input.view.setAll(0, pointer.asTypedList(secret.length)));
    return _encrypt(input, ad: ad, nonce: nonce, key: key);
  } finally {
    input.free();
  }
}

/// Decrypts [ciphertext], or returns null if it, [ad], [nonce] or [key] don't match.
Uint8List? aeadDecrypt(Uint8List ciphertext, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final sodium = Sodium.instance;
  if (ciphertext.length < sodium.aeadTagBytes) {
    return null;
  }
  final output = ScratchBuffer(ciphertext.length - sodium.aeadTagBytes);
  try {
    return _decryptInto(output, ciphertext, ad: ad, nonce: nonce, key: key) ? output.copy() : null;
  } finally {
    output.free();
  }
}

/// Decrypts [ciphertext] straight into [secret] (e.g. the master key), never
/// into Dart's heap. Returns false if anything doesn't match.
bool aeadDecryptSecret(SecureBuffer secret, Uint8List ciphertext, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final sodium = Sodium.instance;
  if (ciphertext.length != secret.length + sodium.aeadTagBytes) {
    return false;
  }
  final output = ScratchBuffer(secret.length);
  try {
    if (!_decryptInto(output, ciphertext, ad: ad, nonce: nonce, key: key)) {
      return false;
    }
    secret.use((pointer) => pointer.asTypedList(secret.length).setAll(0, output.view));
    return true;
  } finally {
    output.free();
  }
}

Uint8List _encrypt(ScratchBuffer input, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final sodium = Sodium.instance;
  _checkSizes(sodium, nonce, key);
  final output = ScratchBuffer(input.length + sodium.aeadTagBytes);
  final adBuffer = ScratchBuffer.from(ad);
  final nonceBuffer = ScratchBuffer.from(nonce);
  try {
    key.use((k) => sodium.aeadEncrypt(output.pointer, input.pointer, input.length, adBuffer.pointer, ad.length, nonceBuffer.pointer, k));
    return output.copy();
  } finally {
    output.free();
    adBuffer.free();
    nonceBuffer.free();
  }
}

bool _decryptInto(ScratchBuffer output, Uint8List ciphertext, {required Uint8List ad, required Uint8List nonce, required SecureBuffer key}) {
  final sodium = Sodium.instance;
  _checkSizes(sodium, nonce, key);
  final input = ScratchBuffer.from(ciphertext);
  final adBuffer = ScratchBuffer.from(ad);
  final nonceBuffer = ScratchBuffer.from(nonce);
  try {
    return key.use((k) => sodium.aeadDecrypt(output.pointer, input.pointer, ciphertext.length, adBuffer.pointer, ad.length, nonceBuffer.pointer, k));
  } finally {
    input.free();
    adBuffer.free();
    nonceBuffer.free();
  }
}

void _checkSizes(Sodium sodium, Uint8List nonce, SecureBuffer key) {
  if (nonce.length != sodium.aeadNonceBytes) {
    throw ArgumentError.value(nonce.length, 'nonce', 'must be ${sodium.aeadNonceBytes} bytes');
  }
  if (key.length != sodium.aeadKeyBytes) {
    throw ArgumentError.value(key.length, 'key', 'must be ${sodium.aeadKeyBytes} bytes');
  }
}
