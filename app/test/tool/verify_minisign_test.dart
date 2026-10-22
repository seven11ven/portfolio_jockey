import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_minisign.dart';

void main() {
  final minisign = Minisign.open();
  final file = Uint8List.fromList(utf8.encode('libsodium-1.0.22.tar.gz stand-in'));
  final seed = Uint8List.fromList(List.generate(32, (i) => i));
  final signed = minisign.signForTest(file, seed, 'timestamp:1712345678\tfile:libsodium-1.0.22.tar.gz');

  String replaceLine(String text, int line, String value) => (const LineSplitter().convert(text)..[line] = value).join('\n');

  test('a good signature passes and returns the trusted comment', () {
    expect(minisign.verify(file, signed.signature, signed.publicKey), 'timestamp:1712345678\tfile:libsodium-1.0.22.tar.gz');
  });

  test('a changed file fails', () {
    final changed = Uint8List.fromList([...file]..[0] ^= 1);
    expect(() => minisign.verify(changed, signed.signature, signed.publicKey), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('file does not match'))));
  });

  test('a changed trusted comment fails', () {
    final forged = replaceLine(signed.signature, 2, 'trusted comment: timestamp:1712345678\tfile:other.tar.gz');
    expect(() => minisign.verify(file, forged, signed.publicKey), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('trusted comment'))));
  });

  test('another key fails, with the same key ID or a different one', () {
    final other = minisign.signForTest(file, Uint8List(32), 'x');
    expect(() => minisign.verify(file, signed.signature, other.publicKey), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('file does not match'))));
    final otherId = minisign.signForTest(file, Uint8List(32), 'x', keyId: const [9, 9, 9, 9, 9, 9, 9, 9]);
    expect(() => minisign.verify(file, signed.signature, otherId.publicKey), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('different key'))));
  });

  test('legacy (not prehashed) signatures and malformed input are refused', () {
    final sig = base64.decode(const LineSplitter().convert(signed.signature)[1])..[1] = 0x64; // "Ed"
    expect(() => minisign.verify(file, replaceLine(signed.signature, 1, base64.encode(sig)), signed.publicKey), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('prehashed'))));
    expect(() => minisign.verify(file, 'not a signature', signed.publicKey), throwsFormatException);
    expect(() => minisign.verify(file, signed.signature, 'not base64!'), throwsFormatException);
  });
}
