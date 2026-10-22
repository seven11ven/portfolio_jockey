import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/blob_stream.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

import 'test_helpers.dart';

const int _small = 64; // A small chunk size so chunk boundaries are cheap to test.

Uint8List _data(int length) => Uint8List.fromList(List.generate(length, (i) => (i * 7 + 3) & 0xff));

Future<Uint8List> _decryptAll(File file, SecureBuffer key) async {
  final builder = BytesBuilder();
  await for (final chunk in decryptFile(file, key)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Splits [data] into uneven pieces, like a real file stream.
Stream<List<int>> _pieces(Uint8List data) async* {
  var offset = 0;
  var size = 1;
  while (offset < data.length) {
    final end = (offset + size).clamp(0, data.length);
    yield data.sublist(offset, end);
    offset = end;
    size = size * 3 % 97 + 1;
  }
}

void main() {
  late SecureBuffer key;
  late Directory folder;
  final tagBytes = Sodium.instance.streamTagBytes;
  const int headerBytes = 12 + 24;

  setUp(() async {
    key = SecureBuffer.random(32);
    addTearDown(key.dispose);
    folder = await tempFolder();
  });

  for (final length in [0, 1, _small - 1, _small, _small + 1, 3 * _small, 3 * _small + 5]) {
    test('round trip of $length bytes', () async {
      final data = _data(length);
      final file = File('${folder.path}/f.enc');
      await encryptToFile(_pieces(data), file, key, chunkSize: _small);
      expect(await _decryptAll(file, key), data);

      // The last chunk carries the FINAL tag; only an empty file needs an empty chunk.
      final chunks = length == 0 ? 1 : (length / _small).ceil();
      expect(await file.length(), headerBytes + length + chunks * tagBytes);
    });
  }

  test('round trip of a 5 MB file with the default chunk size', () async {
    final data = _data(5 * 1024 * 1024 + 123);
    final file = File('${folder.path}/big.enc');
    await encryptToFile(Stream.value(data), file, key);
    expect(await _decryptAll(file, key), data);
  });

  test('the contents are not stored in plain text', () async {
    final file = File('${folder.path}/f.enc');
    await encryptToFile(Stream.value('PlainTextMarker'.codeUnits), file, key);
    expect(String.fromCharCodes(await file.readAsBytes()).contains('PlainTextMarker'), isFalse);
  });

  Future<File> encrypted(int length) async {
    final file = File('${folder.path}/f.enc');
    await encryptToFile(Stream.value(_data(length)), file, key, chunkSize: _small);
    return file;
  }

  test('a flipped bit in any chunk is detected', () async {
    final file = await encrypted(3 * _small);
    final original = await file.readAsBytes();
    for (final offset in [headerBytes, headerBytes + _small + tagBytes + 5, original.length - 1]) {
      await file.writeAsBytes(Uint8List.fromList(original)..[offset] ^= 1);
      await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()), reason: 'byte $offset');
    }
  });

  test('a file cut at a chunk boundary is detected', () async {
    final file = await encrypted(3 * _small);
    final bytes = await file.readAsBytes();
    await file.writeAsBytes(bytes.sublist(0, headerBytes + 2 * (_small + tagBytes)));
    await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()));
  });

  test('a file cut inside a chunk is detected', () async {
    final file = await encrypted(3 * _small);
    final bytes = await file.readAsBytes();
    await file.writeAsBytes(bytes.sublist(0, bytes.length - 3));
    await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()));
  });

  test('swapped chunks are detected', () async {
    final file = await encrypted(3 * _small);
    final bytes = await file.readAsBytes();
    const full = _small + 17;
    final first = bytes.sublist(headerBytes, headerBytes + full);
    final second = bytes.sublist(headerBytes + full, headerBytes + 2 * full);
    bytes
      ..setAll(headerBytes, second)
      ..setAll(headerBytes + full, first);
    await file.writeAsBytes(bytes);
    await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()));
  });

  test('data after the final chunk is detected', () async {
    final file = await encrypted(_small + 3);
    await file.writeAsBytes(List.filled(40, 0), mode: FileMode.append);
    await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()));
  });

  test('the wrong key is detected', () async {
    final file = await encrypted(10);
    final other = SecureBuffer.random(32);
    addTearDown(other.dispose);
    await expectLater(_decryptAll(file, other), throwsA(isA<TamperedData>()));
  });

  test('a changed chunk size is detected', () async {
    final file = await encrypted(3 * _small);
    final bytes = await file.readAsBytes();
    bytes[8] = _small ~/ 2;
    await file.writeAsBytes(bytes);
    await expectLater(_decryptAll(file, key), throwsA(isA<TamperedData>()));
  });

  test('a foreign or damaged header is reported as a format error', () async {
    final file = await encrypted(10);
    final original = await file.readAsBytes();

    await file.writeAsBytes(Uint8List.fromList(original)..[0] = 0x58);
    await expectLater(_decryptAll(file, key), throwsA(isA<VaultFormatError>()));

    final hugeChunks = Uint8List.fromList(original);
    ByteData.sublistView(hugeChunks).setUint32(8, maxChunkSize + 1, Endian.little);
    await file.writeAsBytes(hugeChunks);
    await expectLater(_decryptAll(file, key), throwsA(isA<VaultFormatError>()));

    await file.writeAsBytes(original.sublist(0, 5));
    await expectLater(_decryptAll(file, key), throwsA(isA<VaultFormatError>()));
  });

  test('a failed source stream leaves no file behind', () async {
    final file = File('${folder.path}/f.enc');
    final failing = Stream<List<int>>.fromFutures([
      Future.value(_data(10)),
      Future.error(const FileSystemException('read failed')),
    ]);
    await expectLater(encryptToFile(failing, file, key), throwsA(isA<FileSystemException>()));
    expect(await folder.list().toList(), isEmpty);
  });
}
