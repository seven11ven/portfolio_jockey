// Checks a file's minisign signature with the system libsodium, so release
// downloads (libsodium's own tarball, for the Flatpak) can be verified without
// installing minisign.
//
//   dart run tool/verify_minisign.dart <file> <file.minisig> <public key>
//
// Exits 0 only if the key ID matches, the file signature is valid and the
// trusted comment is signed too. Only prehashed ("ED") signatures are
// accepted, as minisign has made by default since 0.8.
//
// Only the symbols listed in tool/allowed-native-libs.txt may be looked up
// here; tool/check-privacy.sh enforces that.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run tool/verify_minisign.dart <file> <file.minisig> <public key>');
    exit(2);
  }
  final file = await File(args[0]).readAsBytes();
  final signature = await File(args[1]).readAsString();
  try {
    final comment = Minisign.open().verify(file, signature, args[2]);
    stdout.writeln('Signature OK. Trusted comment: $comment');
  } on FormatException catch (e) {
    stderr.writeln('Signature check FAILED: ${e.message}');
    exit(1);
  }
}

final class Minisign {
  Minisign._(DynamicLibrary lib)
    : _malloc = lib.lookupFunction<Pointer<Uint8> Function(Size), Pointer<Uint8> Function(int)>('sodium_malloc'),
      _free = lib.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>('sodium_free'),
      _hash = lib.lookupFunction<Int Function(Pointer<Uint8>, Size, Pointer<Uint8>, Uint64, Pointer<Uint8>, Size), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int)>('crypto_generichash'),
      _verify = lib.lookupFunction<Int Function(Pointer<Uint8>, Pointer<Uint8>, Uint64, Pointer<Uint8>), int Function(Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>)>('crypto_sign_verify_detached'),
      _seedKeypair = lib.lookupFunction<Int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>), int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>('crypto_sign_seed_keypair'),
      _sign = lib.lookupFunction<Int Function(Pointer<Uint8>, Pointer<Uint64>, Pointer<Uint8>, Uint64, Pointer<Uint8>), int Function(Pointer<Uint8>, Pointer<Uint64>, Pointer<Uint8>, int, Pointer<Uint8>)>('crypto_sign_detached') {
    if (lib.lookupFunction<Int Function(), int Function()>('sodium_init')() < 0) {
      throw StateError('libsodium could not start');
    }
  }

  /// Loads the system libsodium.
  factory Minisign.open() => Minisign._(DynamicLibrary.open('libsodium.so.23'));

  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _free;
  final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int) _hash;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>) _verify;
  final int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>) _seedKeypair;
  final int Function(Pointer<Uint8>, Pointer<Uint64>, Pointer<Uint8>, int, Pointer<Uint8>) _sign;

  static const String _trustedPrefix = 'trusted comment: ';

  /// Checks [signature] (the .minisig text) over [file] against [publicKey]
  /// (the base64 key). Returns the trusted comment, or throws a
  /// [FormatException] saying what failed.
  String verify(Uint8List file, String signature, String publicKey) {
    final key = _decode(publicKey.trim(), 42, 'public key');
    if (key[0] != 0x45 || key[1] != 0x64) {
      throw const FormatException('the public key is not an Ed25519 minisign key');
    }
    final lines = const LineSplitter().convert(signature).where((line) => line.isNotEmpty).toList();
    if (lines.length < 4 || !lines[2].startsWith(_trustedPrefix)) {
      throw const FormatException('the .minisig file is not in minisign format');
    }
    final sig = _decode(lines[1], 74, 'signature');
    if (sig[0] != 0x45 || sig[1] != 0x44) {
      throw const FormatException('only prehashed (ED) signatures are accepted');
    }
    if (!_same(sig.sublist(2, 10), key.sublist(2, 10))) {
      throw const FormatException('the signature was made with a different key');
    }
    final comment = utf8.encode(lines[2].substring(_trustedPrefix.length));
    final global = _decode(lines[3], 64, 'trusted comment signature');
    final pk = key.sublist(10);
    if (!_verifies(sig.sublist(10), _blake2b512(file), pk)) {
      throw const FormatException('the file does not match its signature');
    }
    if (!_verifies(global, Uint8List.fromList([...sig.sublist(10), ...comment]), pk)) {
      throw const FormatException('the trusted comment does not match its signature');
    }
    return utf8.decode(comment);
  }

  /// Signs [file] like `minisign -S` with a key made from [seed] (32 bytes),
  /// returning the .minisig text and the public key. For tests only.
  ({String signature, String publicKey}) signForTest(Uint8List file, Uint8List seed, String trustedComment, {List<int> keyId = const [1, 2, 3, 4, 5, 6, 7, 8]}) {
    final pk = _malloc(32), sk = _malloc(64), seedBuf = _copy(seed);
    try {
      _seedKeypair(pk, sk, seedBuf);
      final sig = _signWith(sk, _blake2b512(file));
      final comment = utf8.encode(trustedComment);
      final global = _signWith(sk, Uint8List.fromList([...sig, ...comment]));
      final publicKey = base64.encode([0x45, 0x64, ...keyId, ...pk.asTypedList(32)]);
      final text = [
        'untrusted comment: signature from a test key',
        base64.encode([0x45, 0x44, ...keyId, ...sig]),
        '$_trustedPrefix$trustedComment',
        base64.encode(global),
        '',
      ].join('\n');
      return (signature: text, publicKey: publicKey);
    } finally {
      _free(pk);
      _free(sk);
      _free(seedBuf);
    }
  }

  Uint8List _signWith(Pointer<Uint8> sk, Uint8List message) {
    final out = _malloc(64), msg = _copy(message);
    try {
      _sign(out, nullptr, msg, message.length, sk);
      return Uint8List.fromList(out.asTypedList(64));
    } finally {
      _free(out);
      _free(msg);
    }
  }

  bool _verifies(Uint8List signature, Uint8List message, Uint8List publicKey) {
    final sig = _copy(signature), msg = _copy(message), pk = _copy(publicKey);
    try {
      return _verify(sig, msg, message.length, pk) == 0;
    } finally {
      _free(sig);
      _free(msg);
      _free(pk);
    }
  }

  Uint8List _blake2b512(Uint8List data) {
    final out = _malloc(64), input = _copy(data);
    try {
      if (_hash(out, 64, input, data.length, nullptr, 0) != 0) {
        throw StateError('BLAKE2b failed');
      }
      return Uint8List.fromList(out.asTypedList(64));
    } finally {
      _free(out);
      _free(input);
    }
  }

  Pointer<Uint8> _copy(Uint8List bytes) {
    final pointer = _malloc(bytes.isEmpty ? 1 : bytes.length);
    if (pointer == nullptr) {
      throw StateError('Out of memory');
    }
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static Uint8List _decode(String text, int length, String what) {
    final Uint8List bytes;
    try {
      bytes = base64.decode(text.trim());
    } on FormatException {
      throw FormatException('the $what is not valid base64');
    }
    if (bytes.length != length) {
      throw FormatException('the $what has the wrong length');
    }
    return bytes;
  }

  static bool _same(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
