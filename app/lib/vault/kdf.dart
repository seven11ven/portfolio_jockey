import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/scratch_buffer.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

/// Argon2id settings for turning the passphrase into a key. They're stored in
/// the vault header, so a vault keeps working if the defaults change later.
final class KdfParams {
  const KdfParams({required this.opsLimit, required this.memLimit});

  /// libsodium's MODERATE preset (3 passes over 256 MiB in 1.0.18).
  factory KdfParams.moderate() {
    final sodium = Sodium.instance;
    return KdfParams(opsLimit: sodium.pwhashOpsLimitModerate, memLimit: sodium.pwhashMemLimitModerate);
  }

  /// The largest settings accepted from a vault header. The header is only
  /// authenticated after the key is derived, so without a limit a damaged or
  /// hostile header could make unlocking run for hours or exhaust memory.
  static const int maxOpsLimit = 10;
  static const int maxMemLimit = 2 * 1024 * 1024 * 1024;

  final int opsLimit;
  final int memLimit;

  /// Throws [VaultFormatError] unless the settings are within libsodium's
  /// minimums and the limits above.
  void checkBounds() {
    final sodium = Sodium.instance;
    if (opsLimit < sodium.pwhashOpsLimitMin || opsLimit > maxOpsLimit) {
      throw VaultFormatError('Argon2id opslimit $opsLimit is out of range');
    }
    if (memLimit < sodium.pwhashMemLimitMin || memLimit > maxMemLimit) {
      throw VaultFormatError('Argon2id memlimit $memLimit is out of range');
    }
  }
}

/// Derives [length] bytes from [passphrase] with Argon2id, on a background
/// isolate so the interface stays responsive. The result is in guarded memory.
///
/// Throws [VaultException] if libsodium refuses the settings or runs out of memory.
Future<SecureBuffer> deriveKey(SecureBuffer passphrase, Uint8List salt, KdfParams params, {int length = 32}) async {
  final sodium = Sodium.instance;
  if (salt.length != sodium.pwhashSaltBytes) {
    throw ArgumentError.value(salt.length, 'salt', 'must be ${sodium.pwhashSaltBytes} bytes');
  }
  final key = SecureBuffer.allocate(length);
  var ok = false;
  try {
    final result = await passphrase.useAsync(
      (pw) => key.useAsync(
        (out) => _pwhashInBackground(out.address, length, pw.address, passphrase.length, salt, params.opsLimit, params.memLimit),
      ),
    );
    if (result != 0) {
      throw const VaultException('Argon2id failed: the settings were refused or memory ran out');
    }
    ok = true;
    return key;
  } finally {
    if (!ok) {
      key.dispose();
    }
  }
}

// Only plain values cross to the other isolate: memory addresses, not
// pointers or buffers. Both isolates share the process's memory.
Future<int> _pwhashInBackground(int outAddress, int outLength, int passphraseAddress, int passphraseLength, Uint8List salt, int opsLimit, int memLimit) =>
    Isolate.run(() {
      final saltBuffer = ScratchBuffer.from(salt);
      try {
        return Sodium.instance.pwhash(
          Pointer<Uint8>.fromAddress(outAddress),
          outLength,
          Pointer<Uint8>.fromAddress(passphraseAddress),
          passphraseLength,
          saltBuffer.pointer,
          opsLimit,
          memLimit,
        );
      } finally {
        saltBuffer.free();
      }
    });
