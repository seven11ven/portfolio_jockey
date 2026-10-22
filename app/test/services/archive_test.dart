import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as reference;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/archive/archive_entry.dart';
import 'package:portfolio_jockey/services/archive/tar_reader.dart';
import 'package:portfolio_jockey/services/archive/tar_writer.dart';
import 'package:portfolio_jockey/services/archive/zip_writer.dart';

/// An entry whose content arrives in uneven chunks, like a decrypted file.
ArchiveEntry entry(String path, List<int> content, {int? declaredSize}) => ArchiveEntry(
  path: path,
  size: declaredSize ?? content.length,
  modified: DateTime.utc(2026, 10, 22, 14, 5, 30),
  open: () async* {
    for (var i = 0; i < content.length; i += 7000) {
      yield content.sublist(i, i + 7000 > content.length ? content.length : i + 7000);
    }
  },
);

Future<Uint8List> collect(Stream<List<int>> stream) async {
  final out = BytesBuilder();
  await for (final chunk in stream) {
    out.add(chunk);
  }
  return out.takeBytes();
}

final List<int> text = utf8.encode('Counter: 240 cm\n' * 3000);
final List<int> noise = List.generate(50000, (i) => (i * 7919 + i ~/ 3) & 0xFF);
final String longName = 'Kitchen Remodel/files/${'very-long-name-' * 10}.txt';

List<ArchiveEntry> sample() => [
  entry('Kitchen Remodel/project.json', utf8.encode('{"name":"Kitchen Remodel"}')),
  entry('Kitchen Remodel/files/measurements.txt', text),
  entry('Kitchen Remodel/files/countertop-after.jpg', noise),
  entry('Kitchen Remodel/files/Küche – Übersicht.md', utf8.encode('# Plan')),
  entry(longName, utf8.encode('long')),
  entry('Kitchen Remodel/files/empty.txt', const []),
];

void main() {
  group('zip', () {
    test('a standard ZIP reader reads every file back exactly', () async {
      final bytes = await collect(zipStream(Stream.fromIterable(sample())));
      final archive = reference.ZipDecoder().decodeBytes(bytes, verify: true);
      final byName = {for (final f in archive.files) f.name: f};
      for (final e in sample()) {
        expect(byName.keys, contains(e.path));
        expect(byName[e.path]!.content, await collect(e.open()), reason: e.path);
      }
      expect(byName['Kitchen Remodel/files/measurements.txt']!.compression, reference.CompressionType.deflate, reason: 'text is deflated');
      expect(byName['Kitchen Remodel/files/countertop-after.jpg']!.compression, reference.CompressionType.none, reason: 'JPEG is stored');
      final textOnly = await collect(zipStream(Stream.value(entry('measurements.txt', text))));
      expect(textOnly.length, lessThan(text.length ~/ 10), reason: 'deflate actually compresses');
    });

    test('python zipfile and unzip agree', () async {
      final folder = await Directory.systemTemp.createTemp('pj_zip_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/export.zip');
      await file.writeAsBytes(await collect(zipStream(Stream.fromIterable(sample()))));
      final python = await Process.run('python3', ['-I', '-c', 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print(len(z.namelist()))', file.path]);
      expect(python.exitCode, 0, reason: '${python.stderr}');
      expect('${python.stdout}'.trim(), '${sample().length}');
    }, skip: Process.runSync('which', ['python3']).exitCode != 0);

    test('a size mismatch fails instead of writing a broken archive', () async {
      final bad = entry('a.txt', utf8.encode('12345'), declaredSize: 4);
      await expectLater(collect(zipStream(Stream.value(bad))), throwsA(isA<EntrySizeMismatch>()));
    });
  });

  group('tar', () {
    test('a standard tar reader reads every file back exactly, including PAX names', () async {
      final bytes = await collect(tarStream(Stream.fromIterable(sample())));
      expect(bytes.length % 512, 0);
      final archive = reference.TarDecoder().decodeBytes(bytes);
      final byName = {for (final f in archive.files) f.name: f};
      for (final e in sample()) {
        expect(byName.keys, contains(e.path));
        expect(byName[e.path]!.content, await collect(e.open()), reason: e.path);
      }
    });

    test('system tar lists the same names', () async {
      final folder = await Directory.systemTemp.createTemp('pj_tar_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/export.tar');
      await file.writeAsBytes(await collect(tarStream(Stream.fromIterable(sample()))));
      final listing = await Process.run('tar', ['-tf', file.path], stdoutEncoding: utf8);
      expect(listing.exitCode, 0, reason: '${listing.stderr}');
      expect(const LineSplitter().convert('${listing.stdout}'), [for (final e in sample()) e.path]);
    });

    test('our reader reads our archive, with the same content', () async {
      final entries = [entry('manifest.json', utf8.encode('{}')), entry('files/0/0', noise), entry('files/0/1', const [])];
      final reader = TarReader(tarStream(Stream.fromIterable(entries)));
      for (final e in entries) {
        final found = (await reader.next())!;
        expect((found.path, found.size), (e.path, e.size));
        expect(await reader.readAll(found, maxBytes: 1 << 20), await collect(e.open()));
      }
      expect(await reader.next(), isNull);
    });

    test('our reader refuses unsafe paths, links and damaged headers', () async {
      Future<void> refuses(List<int> archive) =>
          expectLater(() async => TarReader(Stream.value(archive)).next(), throwsA(isA<BadArchive>()));

      await refuses(await collect(tarStream(Stream.value(entry('../escape', [1])))));
      await refuses(await collect(tarStream(Stream.value(entry('/etc/passwd', [1])))));
      await refuses(await collect(tarStream(Stream.value(entry('files/ü', [1])))));
      final link = await collect(tarStream(Stream.value(entry('files/0/0', [1]))));
      link[156] = 0x32; // '2': symbolic link (checksum now wrong too)
      await refuses(link);
      final damaged = await collect(tarStream(Stream.value(entry('files/0/0', [1]))));
      damaged[10] ^= 1;
      await refuses(damaged);
      await refuses(Uint8List(100)); // cut short
    });

    test('a size mismatch fails', () async {
      await expectLater(collect(tarStream(Stream.value(entry('a', [1, 2], declaredSize: 3)))), throwsA(isA<EntrySizeMismatch>()));
    });
  });

  // Over 4 GB, so it takes a minute: run with RUN_SLOW_TESTS=1.
  test('ZIP64 and PAX: a file over 4 GiB is read back by python and tar', () async {
    const big = 0x100000000 + 12345; // 4 GiB + a bit
    final zero = Uint8List(1 << 20);
    ArchiveEntry huge(String path) => ArchiveEntry(
      path: path,
      size: big,
      modified: DateTime.utc(2026),
      open: () async* {
        for (var left = big; left > 0; left -= zero.length) {
          yield left < zero.length ? Uint8List(left) : zero;
        }
      },
    );
    final folder = await Directory.systemTemp.createTemp('pj_zip64_');
    addTearDown(() => folder.delete(recursive: true));
    Future<File> write(String name, Stream<List<int>> stream) async {
      final file = File('${folder.path}/$name');
      final out = await file.open(mode: FileMode.writeOnly);
      await for (final chunk in stream) {
        await out.writeFrom(chunk);
      }
      await out.close();
      return file;
    }

    final zip = await write('big.zip', zipStream(Stream.fromIterable([entry('small.txt', utf8.encode('hi')), huge('video.mp4'), entry('after.txt', utf8.encode('after'))])));
    final check = await Process.run('python3', [
      '-I',
      '-c',
      'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); i=z.getinfo("video.mp4"); assert i.file_size==$big, i.file_size; assert z.read("after.txt")==b"after"; print("ok")',
      zip.path,
    ]);
    expect('${check.stdout}'.trim(), 'ok', reason: '${check.stderr}');
    await zip.delete();

    final tar = await write('big.tar', tarStream(Stream.fromIterable([huge('video.mp4'), entry('after.txt', utf8.encode('after'))])));
    final listing = await Process.run('tar', ['-tvf', tar.path]);
    expect('${listing.stdout}', contains('$big'), reason: '${listing.stderr}');
    expect('${listing.stdout}', contains('after.txt'));
  }, skip: Platform.environment['RUN_SLOW_TESTS'] != '1', timeout: const Timeout(Duration(minutes: 10)));

  test('CRC-32 matches the standard check value', () {
    expect((Crc32()..add(ascii.encode('123456789'))).value, 0xCBF43926);
  });
}
