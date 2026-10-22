import 'dart:ffi';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// The oldest libsodium the vault accepts. Debian 12 ships 1.0.18.
const List<int> minimumSodiumVersion = [1, 0, 18];

typedef _SizeC = Size Function();
typedef _Size = int Function();
typedef _PtrIntC = Int Function(Pointer<Void>);
typedef _PtrInt = int Function(Pointer<Void>);

/// Bindings to the libsodium functions the vault uses, and nothing more.
///
/// libsodium comes from the system (the dev container's `libsodium23`) or, in
/// a release, from the Flatpak. Every size is read from libsodium itself
/// instead of being hard-coded. Each isolate loads its own instance.
final class Sodium {
  Sodium._(DynamicLibrary lib)
    : _init = lib.lookupFunction<Int Function(), int Function()>('sodium_init'),
      _versionString = lib.lookupFunction<Pointer<Char> Function(), Pointer<Char> Function()>('sodium_version_string'),
      _malloc = lib.lookupFunction<Pointer<Void> Function(Size), Pointer<Void> Function(int)>('sodium_malloc'),
      _free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('sodium_free'),
      _memzero = lib.lookupFunction<Void Function(Pointer<Void>, Size), void Function(Pointer<Void>, int)>('sodium_memzero'),
      _mprotectNoAccess = lib.lookupFunction<_PtrIntC, _PtrInt>('sodium_mprotect_noaccess'),
      _mprotectReadWrite = lib.lookupFunction<_PtrIntC, _PtrInt>('sodium_mprotect_readwrite'),
      _randomBytes = lib.lookupFunction<Void Function(Pointer<Void>, Size), void Function(Pointer<Void>, int)>('randombytes_buf'),
      pwhashSaltBytes = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_saltbytes')(),
      pwhashBytesMin = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_bytes_min')(),
      pwhashOpsLimitMin = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_opslimit_min')(),
      pwhashOpsLimitModerate = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_opslimit_moderate')(),
      pwhashMemLimitMin = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_memlimit_min')(),
      pwhashMemLimitModerate = lib.lookupFunction<_SizeC, _Size>('crypto_pwhash_memlimit_moderate')(),
      _argon2id13 = lib.lookupFunction<Int Function(), int Function()>('crypto_pwhash_alg_argon2id13')(),
      _pwhash = lib.lookupFunction<
        Int Function(Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong, Size, Int),
        int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int)
      >('crypto_pwhash'),
      aeadKeyBytes = lib.lookupFunction<_SizeC, _Size>('crypto_aead_xchacha20poly1305_ietf_keybytes')(),
      aeadNonceBytes = lib.lookupFunction<_SizeC, _Size>('crypto_aead_xchacha20poly1305_ietf_npubbytes')(),
      aeadTagBytes = lib.lookupFunction<_SizeC, _Size>('crypto_aead_xchacha20poly1305_ietf_abytes')(),
      _aeadEncrypt = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)
      >('crypto_aead_xchacha20poly1305_ietf_encrypt'),
      _aeadDecrypt = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>)
      >('crypto_aead_xchacha20poly1305_ietf_decrypt'),
      streamKeyBytes = lib.lookupFunction<_SizeC, _Size>('crypto_secretstream_xchacha20poly1305_keybytes')(),
      streamHeaderBytes = lib.lookupFunction<_SizeC, _Size>('crypto_secretstream_xchacha20poly1305_headerbytes')(),
      streamTagBytes = lib.lookupFunction<_SizeC, _Size>('crypto_secretstream_xchacha20poly1305_abytes')(),
      streamStateBytes = lib.lookupFunction<_SizeC, _Size>('crypto_secretstream_xchacha20poly1305_statebytes')(),
      streamTagMessage = lib.lookupFunction<UnsignedChar Function(), int Function()>('crypto_secretstream_xchacha20poly1305_tag_message')(),
      streamTagFinal = lib.lookupFunction<UnsignedChar Function(), int Function()>('crypto_secretstream_xchacha20poly1305_tag_final')(),
      _streamInitPush = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)
      >('crypto_secretstream_xchacha20poly1305_init_push'),
      _streamPush = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong, UnsignedChar),
        int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, int, Pointer<Uint8>, int, int)
      >('crypto_secretstream_xchacha20poly1305_push'),
      _streamInitPull = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)
      >('crypto_secretstream_xchacha20poly1305_init_pull'),
      _streamPull = lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, UnsignedLongLong, Pointer<Uint8>, UnsignedLongLong),
        int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, int)
      >('crypto_secretstream_xchacha20poly1305_pull');

  static Sodium? _instance;

  /// libsodium, loaded and initialised once per isolate.
  ///
  /// Throws [SodiumUnavailable] if it's missing or older than 1.0.18.
  static Sodium get instance => _instance ??= _load();

  static Sodium _load() {
    final sodium = Sodium._(_open());
    if (sodium._init() < 0) {
      throw const SodiumUnavailable('sodium_init() failed');
    }
    final version = sodium.version;
    if (!_isAtLeast(version, minimumSodiumVersion)) {
      throw SodiumUnavailable('libsodium $version is older than ${minimumSodiumVersion.join('.')}');
    }
    return sodium;
  }

  // libsodium 1.0.19 and newer is libsodium.so.26; 1.0.18 is libsodium.so.23.
  // The names stay literal so tool/check-privacy.sh can check them.
  static DynamicLibrary _open() {
    final candidates = <DynamicLibrary Function()>[
      () => DynamicLibrary.open('libsodium.so.26'),
      () => DynamicLibrary.open('libsodium.so.23'),
    ];
    for (final open in candidates) {
      try {
        return open();
        // DynamicLibrary.open reports a missing library as an ArgumentError.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        continue;
      }
    }
    throw const SodiumUnavailable('libsodium not found. Install it with: sudo apt-get install libsodium23');
  }

  static bool _isAtLeast(String version, List<int> minimum) {
    final parts = version.split('.').map(int.tryParse).toList();
    for (var i = 0; i < minimum.length; i++) {
      final part = i < parts.length ? parts[i] ?? 0 : 0;
      if (part != minimum[i]) {
        return part > minimum[i];
      }
    }
    return true;
  }

  final int Function() _init;
  final Pointer<Char> Function() _versionString;
  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final void Function(Pointer<Void>, int) _memzero;
  final int Function(Pointer<Void>) _mprotectNoAccess;
  final int Function(Pointer<Void>) _mprotectReadWrite;
  final void Function(Pointer<Void>, int) _randomBytes;
  final int _argon2id13;
  final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int) _pwhash;
  final int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>) _aeadEncrypt;
  final int Function(Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Uint8>) _aeadDecrypt;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>) _streamInitPush;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, int, Pointer<Uint8>, int, int) _streamPush;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>) _streamInitPull;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLongLong>, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>, int) _streamPull;

  final int pwhashSaltBytes;
  final int pwhashBytesMin;
  final int pwhashOpsLimitMin;
  final int pwhashOpsLimitModerate;
  final int pwhashMemLimitMin;
  final int pwhashMemLimitModerate;
  final int aeadKeyBytes;
  final int aeadNonceBytes;
  final int aeadTagBytes;
  final int streamKeyBytes;
  final int streamHeaderBytes;
  final int streamTagBytes;
  final int streamStateBytes;
  final int streamTagMessage;
  final int streamTagFinal;

  /// libsodium's version, e.g. "1.0.18".
  String get version {
    final chars = _versionString().cast<Uint8>();
    var length = 0;
    while (chars[length] != 0) {
      length++;
    }
    return String.fromCharCodes(chars.asTypedList(length));
  }

  // Guarded memory for secrets: surrounded by guard pages, locked so it can't
  // be swapped to disk, and wiped when freed.
  Pointer<Uint8> secureAlloc(int size) {
    final pointer = _malloc(size);
    if (pointer == nullptr) {
      throw const OutOfMemoryError();
    }
    return pointer.cast();
  }

  void secureFree(Pointer<Uint8> pointer) => _free(pointer.cast());
  void wipe(Pointer<Uint8> pointer, int size) => _memzero(pointer.cast(), size);
  void lockMemory(Pointer<Uint8> pointer) => _mprotectNoAccess(pointer.cast());
  void unlockMemory(Pointer<Uint8> pointer) => _mprotectReadWrite(pointer.cast());

  void fillRandom(Pointer<Uint8> pointer, int size) => _randomBytes(pointer.cast(), size);

  /// Random bytes for values that aren't secret (salts, nonces, IDs).
  Uint8List randomBytes(int size) {
    final buffer = Libc.instance.malloc(size);
    try {
      fillRandom(buffer, size);
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      Libc.instance.free(buffer);
    }
  }

  /// Argon2id (v1.3). Returns 0 on success, -1 if libsodium refuses the
  /// settings or runs out of memory.
  int pwhash(Pointer<Uint8> out, int outLength, Pointer<Uint8> passphrase, int passphraseLength, Pointer<Uint8> salt, int opsLimit, int memLimit) =>
      _pwhash(out, outLength, passphrase, passphraseLength, salt, opsLimit, memLimit, _argon2id13);

  /// XChaCha20-Poly1305 (IETF). Writes `messageLength + aeadTagBytes` bytes to [out].
  void aeadEncrypt(Pointer<Uint8> out, Pointer<Uint8> message, int messageLength, Pointer<Uint8> ad, int adLength, Pointer<Uint8> nonce, Pointer<Uint8> key) {
    _aeadEncrypt(out, nullptr, message, messageLength, ad, adLength, nullptr, nonce, key);
  }

  /// Returns false if the ciphertext, [ad], nonce or key don't match.
  bool aeadDecrypt(Pointer<Uint8> out, Pointer<Uint8> ciphertext, int ciphertextLength, Pointer<Uint8> ad, int adLength, Pointer<Uint8> nonce, Pointer<Uint8> key) =>
      ciphertextLength >= aeadTagBytes && _aeadDecrypt(out, nullptr, nullptr, ciphertext, ciphertextLength, ad, adLength, nonce, key) == 0;

  void streamInitPush(Pointer<Uint8> state, Pointer<Uint8> header, Pointer<Uint8> key) {
    _streamInitPush(state, header, key);
  }

  /// Writes `messageLength + streamTagBytes` bytes to [out].
  void streamPush(Pointer<Uint8> state, Pointer<Uint8> out, Pointer<Uint8> message, int messageLength, Pointer<Uint8> ad, int adLength, int tag) {
    _streamPush(state, out, nullptr, message, messageLength, ad, adLength, tag);
  }

  /// Returns false if the header doesn't belong to this key format.
  bool streamInitPull(Pointer<Uint8> state, Pointer<Uint8> header, Pointer<Uint8> key) => _streamInitPull(state, header, key) == 0;

  /// Returns the chunk's tag, or null if the chunk failed its integrity check.
  int? streamPull(Pointer<Uint8> state, Pointer<Uint8> out, Pointer<Uint8> tag, Pointer<Uint8> chunk, int chunkLength, Pointer<Uint8> ad, int adLength) {
    if (chunkLength < streamTagBytes) {
      return null;
    }
    return _streamPull(state, out, nullptr, tag, chunk, chunkLength, ad, adLength) == 0 ? tag.value : null;
  }
}
