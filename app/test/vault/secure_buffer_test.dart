import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

void main() {
  test('random buffers differ', () {
    final a = SecureBuffer.random(32);
    final b = SecureBuffer.random(32);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final bytesA = a.use((p) => Uint8List.fromList(p.asTypedList(32)));
    final bytesB = b.use((p) => Uint8List.fromList(p.asTypedList(32)));
    expect(bytesA, isNot(equals(bytesB)));
  });

  test('takeBytes copies the bytes and wipes the original', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final buffer = SecureBuffer.takeBytes(source);
    addTearDown(buffer.dispose);
    expect(source, [0, 0, 0, 0]);
    expect(buffer.use((p) => p.asTypedList(4).toList()), [1, 2, 3, 4]);
  });

  test('a disposed buffer cannot be used again', () {
    final buffer = SecureBuffer.random(16)..dispose();
    expect(buffer.isDisposed, isTrue);
    expect(() => buffer.use((p) => p.value), throwsStateError);
    buffer.dispose(); // A second dispose is harmless.
  });

  test('a buffer cannot be disposed while in use', () {
    final buffer = SecureBuffer.random(16);
    addTearDown(buffer.dispose);
    expect(() => buffer.use((_) => buffer.dispose()), throwsStateError);
    expect(buffer.isDisposed, isFalse);
  });

  test('nested use keeps the memory open until the outer use ends', () {
    final buffer = SecureBuffer.random(4);
    addTearDown(buffer.dispose);
    final value = buffer.use((outer) {
      buffer.use((inner) => inner.value);
      return outer.asTypedList(4).toList(); // Still readable after the inner use.
    });
    expect(value, hasLength(4));
  });
}
