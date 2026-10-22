import 'dart:ffi';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/libc.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';

/// Ordinary native memory for data passed to and from libsodium: never keys
/// (see SecureBuffer), but possibly decrypted contents, so it's wiped before
/// it's freed.
final class ScratchBuffer {
  ScratchBuffer(this.length) : pointer = Libc.instance.malloc(length);

  factory ScratchBuffer.from(List<int> bytes) {
    final buffer = ScratchBuffer(bytes.length);
    buffer.view.setAll(0, bytes);
    return buffer;
  }

  final int length;
  final Pointer<Uint8> pointer;

  /// A live view of the memory. Don't keep it after [free].
  Uint8List get view => pointer.asTypedList(length);

  /// A Dart copy of the first [count] bytes (all of them by default).
  Uint8List copy([int? count]) => Uint8List.fromList(pointer.asTypedList(count ?? length));

  void free() {
    Sodium.instance.wipe(pointer, length);
    Libc.instance.free(pointer);
  }
}
