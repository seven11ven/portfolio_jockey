import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as reference;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/archive/tar_reader.dart';
import 'package:portfolio_jockey/services/export_service.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/export_format.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import '../vault/test_helpers.dart';

final List<int> png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII=');

void main() {
  late ProjectService service;
  late ExportService exports;
  late Directory out;
  late String kitchen;
  late String garden;

  setUp(() async {
    final vault = await Vault.create(await tempFolder(), 'vault passphrase', kdf: fastKdf);
    addTearDown(vault.lock);
    service = ProjectService(vault, trasher: FakeTrash(await tempFolder()));
    exports = ExportService(service, kdf: fastKdf);
    out = await tempFolder();
    final originals = await tempFolder();
    Future<String> make(String folder, String name, List<int> bytes) async {
      final file = File('${originals.path}/$folder/$name');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    }

    kitchen = await service.createProject(name: 'Kitchen Remodel', description: 'Quotes and photos.', cover: Uint8List.fromList(png));
    await service.applyTagChanges(kitchen, TagChanges(added: ['Plans', 'Photos']));
    await service.addFiles(kitchen, [
      await make('a', 'measurements.txt', utf8.encode('Counter: 240 cm\n' * 5000)),
      await make('b', 'measurements.txt', utf8.encode('the second one')),
      await make('a', 'empty.txt', const []),
    ], tags: ['Plans']);
    garden = await service.createProject(name: 'Garden Planner');
    await service.addFiles(garden, [await make('c', 'seeds.csv', utf8.encode('tomato,3'))]);
  });

  Future<List<String>> projectNames() async => [for (final p in (await service.listProjects()).projects) p.index.name]..sort();
  Future<String> content(String id, FileEntry file) async => utf8.decode(await service.readFile(id, file, maxBytes: 1 << 20));

  group('unlocked', () {
    for (final format in ArchiveFormat.values) {
      test('${format.name}: one folder per project, each file once with its real name, plus project.json', () async {
        final target = File('${out.path}/export.${format.extension}');
        await exports.export(projectIds: [kitchen, garden], target: target, lock: Unlocked(format));
        final bytes = await target.readAsBytes();
        final archive = format == ArchiveFormat.zip ? reference.ZipDecoder().decodeBytes(bytes, verify: true) : reference.TarDecoder().decodeBytes(bytes);
        final files = {for (final f in archive.files) f.name: f.content};
        expect(files.keys, unorderedEquals([
          'Kitchen Remodel/project.json',
          'Kitchen Remodel/cover.png',
          'Kitchen Remodel/files/measurements.txt',
          'Kitchen Remodel/files/measurements (2).txt',
          'Kitchen Remodel/files/empty.txt',
          'Garden Planner/project.json',
          'Garden Planner/files/seeds.csv',
        ]));
        expect(utf8.decode(files['Kitchen Remodel/files/measurements (2).txt']!), 'the second one');
        expect(files['Kitchen Remodel/cover.png'], png);
        final json = jsonDecode(utf8.decode(files['Kitchen Remodel/project.json']!)) as Map<String, Object?>;
        expect(json['description'], 'Quotes and photos.');
        expect(json['tags'], ['Plans', 'Photos']);
        expect((json['files']! as List<Object?>).map((f) => (f! as Map<String, Object?>)['file']), contains('files/measurements (2).txt'));
        expect(await out.list().map((e) => e.uri.pathSegments.last).toList(), ['export.${format.extension}'], reason: 'no temporary file left');
      });
    }

    test('cancelling leaves nothing behind', () async {
      final cancel = CancelToken();
      final target = File('${out.path}/export.zip');
      await expectLater(
        exports.export(projectIds: [kitchen], target: target, lock: const Unlocked(ArchiveFormat.zip), cancel: cancel, onProgress: (_) => cancel.cancel()),
        throwsA(isA<Cancelled>()),
      );
      expect(await out.list().toList(), isEmpty);
    });

    test('a damaged file stops the export and leaves nothing behind', () async {
      final file = (await service.readProject(kitchen)).files.first;
      final blob = service.vault.layout.blobFile(kitchen, file.id);
      final bytes = await blob.readAsBytes();
      bytes[bytes.length - 5] ^= 1;
      await blob.writeAsBytes(bytes);
      await expectLater(
        exports.export(projectIds: [kitchen], target: File('${out.path}/export.tar'), lock: const Unlocked(ArchiveFormat.tar)),
        throwsA(isA<TamperedData>()),
      );
      expect(await out.list().toList(), isEmpty);
    });
  });

  group('readable copy', () {
    test('saves exactly the decrypted file', () async {
      final file = (await service.readProject(kitchen)).files.first;
      final target = File('${out.path}/copy.txt');
      await exports.exportReadableCopy(kitchen, file, target);
      expect(await target.readAsString(), await content(kitchen, file));
    });

    test('a damaged file leaves nothing behind', () async {
      final file = (await service.readProject(kitchen)).files.first;
      final blob = service.vault.layout.blobFile(kitchen, file.id);
      final bytes = await blob.readAsBytes();
      bytes[bytes.length - 5] ^= 1;
      await blob.writeAsBytes(bytes);
      await expectLater(exports.exportReadableCopy(kitchen, file, File('${out.path}/copy.txt')), throwsA(isA<TamperedData>()));
      expect(await out.list().toList(), isEmpty);
    });
  });

  group('locked', () {
    late File pjx;

    setUp(() async {
      pjx = File('${out.path}/backup.pjx');
      await exports.export(projectIds: [kitchen, garden], target: pjx, lock: const LockedWith('garage-sale-2026'));
    });

    test('names, contents and the vault passphrase are nowhere in the file', () async {
      final raw = latin1.decode(await pjx.readAsBytes());
      for (final secret in ['Kitchen', 'measurements', 'Counter', 'manifest', 'garage-sale', 'vault passphrase']) {
        expect(raw, isNot(contains(secret)), reason: secret);
      }
      expect(raw.substring(0, 4), 'PJEX');
    });

    test('import round trip: new projects, new keys, same contents, tags, dates and cover', () async {
      final before = (await service.readProject(kitchen)).files;
      final opened = await exports.openLocked(pjx, 'garage-sale-2026');
      addTearDown(opened.dispose);
      expect(opened.projects.map((p) => p.name), ['Kitchen Remodel', 'Garden Planner']);
      expect(opened.importNames, ['Kitchen Remodel (2)', 'Garden Planner (2)']);
      expect(opened.fileCount, 4);

      final ids = await exports.import(opened);
      expect(await projectNames(), ['Garden Planner', 'Garden Planner (2)', 'Kitchen Remodel', 'Kitchen Remodel (2)']);
      final imported = await service.readProject(ids.first);
      expect(imported.description, 'Quotes and photos.');
      expect(imported.tags, containsAll(['Plans', 'Photos']));
      expect(await service.readCover(ids.first, imported), png);
      for (var i = 0; i < before.length; i++) {
        final a = before[i];
        final b = imported.files[i];
        expect((b.name, b.size, b.addedAt), (a.name, a.size, a.addedAt));
        expect(b.tags, a.tags);
        expect(b.key, isNot(a.key), reason: 'imported files get new keys');
        expect(b.originalPath, isNull, reason: 'device paths are not exported');
        expect(await content(ids.first, b), await content(kitchen, a));
      }
    });

    test('a wrong passphrase is refused', () async {
      await expectLater(exports.openLocked(pjx, 'garage-sale-2025'), throwsA(isA<WrongExportPassphrase>()));
      await expectLater(exports.openLocked(pjx, 'vault passphrase'), throwsA(isA<WrongExportPassphrase>()));
    });

    test('a changed byte anywhere fails, and the import creates nothing', () async {
      final bytes = await pjx.readAsBytes();
      final names = await projectNames();
      for (final at in [30, bytes.length ~/ 2, bytes.length - 3]) {
        final copy = File('${out.path}/tampered-$at.pjx');
        await copy.writeAsBytes(Uint8List.fromList(bytes)..[at] ^= 1);
        try {
          final opened = await exports.openLocked(copy, 'garage-sale-2026');
          addTearDown(opened.dispose);
          await expectLater(exports.import(opened), throwsA(isA<VaultException>()), reason: 'byte $at');
        } on WrongExportPassphrase {
          // A change in the salt or the first chunk looks like a wrong passphrase.
        }
        expect(await projectNames(), names, reason: 'byte $at');
      }
    });

    test('a cut-off export fails, and the import creates nothing', () async {
      final bytes = await pjx.readAsBytes();
      final cut = File('${out.path}/cut.pjx');
      await cut.writeAsBytes(bytes.sublist(0, bytes.length - 100));
      final opened = await exports.openLocked(cut, 'garage-sale-2026');
      addTearDown(opened.dispose);
      await expectLater(exports.import(opened), throwsA(anyOf(isA<VaultException>(), isA<BadArchive>())));
      expect(await projectNames(), ['Garden Planner', 'Kitchen Remodel']);
    });

    test('cancelling an import removes what it created', () async {
      final opened = await exports.openLocked(pjx, 'garage-sale-2026');
      addTearDown(opened.dispose);
      final cancel = CancelToken();
      await expectLater(exports.import(opened, cancel: cancel, onProgress: (_) => cancel.cancel()), throwsA(isA<Cancelled>()));
      expect(await projectNames(), ['Garden Planner', 'Kitchen Remodel']);
    });

    test('oversized Argon2id settings are refused before any work', () async {
      final bytes = await pjx.readAsBytes();
      ByteData.sublistView(bytes).setUint64(16, 64 * 1024 * 1024 * 1024, Endian.little);
      final hostile = File('${out.path}/hostile.pjx');
      await hostile.writeAsBytes(bytes);
      await expectLater(exports.openLocked(hostile, 'garage-sale-2026'), throwsA(isA<VaultFormatError>()));
    });

    test('a file that is not a locked export is refused', () async {
      final zip = File('${out.path}/not.pjx');
      await exports.export(projectIds: [garden], target: zip, lock: const Unlocked(ArchiveFormat.zip));
      await expectLater(exports.openLocked(zip, 'anything'), throwsA(isA<VaultFormatError>()));
    });
  });
}
