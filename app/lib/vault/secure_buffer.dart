import 'dart:ffi';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/sodium.dart';

/// Secret bytes (keys, the passphrase) held in libsodium's guarded memory,
/// never in Dart's heap.
///
/// The memory can't be read or written except inside [use] or [useAsync], so
/// a stray pointer can't leak it. [dispose] wipes and frees it.
final class SecureBuffer {
  SecureBuffer._(this._pointer, this.length);

  /// [length] zero bytes.
  factory SecureBuffer.allocate(int length) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'must be positive');
    }
    final sodium = Sodium.instance;
    final pointer = sodium.secureAlloc(length);
    sodium.wipe(pointer, length);
    sodium.lockMemory(pointer);
    return SecureBuffer._(pointer, length);
  }

  /// [length] random bytes, e.g. a new key.
  factory SecureBuffer.random(int length) {
    final buffer = SecureBuffer.allocate(length);
    buffer.use((pointer) => Sodium.instance.fillRandom(pointer, length));
    return buffer;
  }

  /// Copies [bytes] into guarded memory, then wipes [bytes].
  factory SecureBuffer.takeBytes(Uint8List bytes) {
    final buffer = SecureBuffer.allocate(bytes.length);
    buffer.use((pointer) => pointer.asTypedList(bytes.length).setAll(0, bytes));
    bytes.fillRange(0, bytes.length, 0);
    return buffer;
  }

  final Pointer<Uint8> _pointer;
  final int length;
  int _users = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Runs [action] with the memory readable and writable, then locks it again.
  T use<T>(T Function(Pointer<Uint8> pointer) action) {
    _open();
    try {
      return action(_pointer);
    } finally {
      _close();
    }
  }

  /// Like [use], for work that finishes later (e.g. on another isolate).
  Future<T> useAsync<T>(Future<T> Function(Pointer<Uint8> pointer) action) async {
    _open();
    try {
      return await action(_pointer);
    } finally {
      _close();
    }
  }

  /// Wipes and frees the memory. Safe to call more than once.
  void dispose() {
    if (_disposed) {
      return;
    }
    if (_users > 0) {
      throw StateError('SecureBuffer disposed while in use');
    }
    _disposed = true;
    final sodium = Sodium.instance;
    sodium.unlockMemory(_pointer);
    sodium.secureFree(_pointer);
  }

  void _open() {
    if (_disposed) {
      throw StateError('SecureBuffer used after dispose');
    }
    if (_users++ == 0) {
      Sodium.instance.unlockMemory(_pointer);
    }
  }

  void _close() {
    if (--_users == 0) {
      Sodium.instance.lockMemory(_pointer);
    }
  }
}
