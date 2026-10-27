import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import '../vault/test_helpers.dart';

void main() {
  late Directory root;
  late Directory originals;
  late ProjectService service;

  setUp(() async {
    root = await tempFolder();
    originals = await tempFolder();
    final vault = await Vault.create(root, 'test passphrase', kdf: fastKdf);
    addTearDown(vault.lock);
    service = ProjectService(vault);
  });

  Future<String> original(String name, String contents) async {
    final file = File('${originals.path}/$name');
    await file.writeAsString(contents);
    return file.path;
  }

  Future<Uint8List> decrypted(String projectId, FileEntry file) async {
    final key = file.openKey();
    try {
      final builder = BytesBuilder();
      await for (final chunk in service.vault.readBlob(projectId, file.id, key)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      key.dispose();
    }
  }

  group('projects', () {
    test('create, list newest change first, rename', () async {
      final a = await service.createProject(name: '  Kitchen  ', description: 'Quotes');
      final b = await service.createProject(name: 'Album');
      var listing = await service.listProjects();
      expect(listing.projects.map((p) => p.id), [b, a]);
      expect(listing.projects.last.index.name, 'Kitchen');

      await service.renameProject(a, 'Kitchen & Dining');
      listing = await service.listProjects();
      expect(listing.projects.map((p) => p.id), [a, b]);
      expect(listing.projects.first.index.name, 'Kitchen & Dining');
    });

    test('cover art is encrypted, replaced and removed', () async {
      final cover = Uint8List.fromList(List.generate(500, (i) => i & 0xff));
      final id = await service.createProject(name: 'P', cover: cover);
      var index = await service.readProject(id);
      expect(await service.readCover(id, index), cover);
      expect(await File('${root.path}/$id/cover.enc').exists(), isTrue);

      final other = Uint8List.fromList([9, 8, 7]);
      await service.updateDetails(id, description: 'New', cover: ReplaceCover(other));
      index = await service.readProject(id);
      expect(index.description, 'New');
      expect(await service.readCover(id, index), other);

      await service.updateDetails(id, description: 'New', cover: const RemoveCover());
      index = await service.readProject(id);
      expect(index.coverKey, isNull);
      expect(await File('${root.path}/$id/cover.enc').exists(), isFalse);
    });

    test('deleting a project removes its folder and nothing else', () async {
      final keep = await service.createProject(name: 'Keep');
      final gone = await service.createProject(name: 'Gone');
      final source = await original('a.txt', 'hello');
      await service.addFiles(gone, [source]);

      await service.deleteProject(gone);

      expect(await Directory('${root.path}/$gone').exists(), isFalse);
      expect((await service.listProjects()).projects.map((p) => p.id), [keep]);
      expect(await File(source).exists(), isTrue);
    });
  });

  group('files', () {
    test('adding encrypts each file, keeps originals and reports progress', () async {
      final id = await service.createProject(name: 'P');
      final a = await original('a.txt', 'first file');
      final b = await original('photo.jpg', 'second file');
      final progress = <AddProgress>[];

      final result = await service.addFiles(id, [a, b], tags: ['Photos'], newTags: ['Photos'], onProgress: progress.add);

      expect(result.failed, isEmpty);
      final index = await service.readProject(id);
      expect(index.tags, ['Photos']);
      expect(index.files.map((f) => f.name), ['a.txt', 'photo.jpg']);
      expect(index.files.first.originalPath, a);
      expect(index.files.first.tags, ['Photos']);
      expect(index.totalSize, 'first file'.length + 'second file'.length);
      expect(String.fromCharCodes(await decrypted(id, index.files.last)), 'second file');
      expect(await File(a).readAsString(), 'first file');
      expect(progress.last.fileNumber, 2);
      expect(progress.last.bytesDone, progress.last.bytesTotal);
    });

    test('a file that cannot be read is reported and the others are added', () async {
      final id = await service.createProject(name: 'P');
      final a = await original('a.txt', 'A');
      final c = await original('c.txt', 'C');

      final result = await service.addFiles(id, [a, '${originals.path}/missing.txt', c]);

      expect(result.added.map((f) => f.name), ['a.txt', 'c.txt']);
      expect(result.failed.keys, ['${originals.path}/missing.txt']);
      expect((await service.readProject(id)).files, hasLength(2));
    });

    test('rename changes only the name in the project', () async {
      final id = await service.createProject(name: 'P');
      final source = await original('a.txt', 'A');
      final file = (await service.addFiles(id, [source])).added.single;
      await service.renameFile(id, file.id, 'renamed.txt');
      expect((await service.readProject(id)).files.single.name, 'renamed.txt');
      expect(await File(source).exists(), isTrue);
    });

    test('delete from project removes the encrypted copy only', () async {
      final id = await service.createProject(name: 'P');
      final source = await original('a.txt', 'A');
      final file = (await service.addFiles(id, [source])).added.single;

      await service.deleteFromProject(id, file.id);

      expect((await service.readProject(id)).files, isEmpty);
      expect(await service.vault.layout.blobFile(id, file.id).exists(), isFalse);
      expect(await File(source).exists(), isTrue);
    });

    test('delete from device removes the original only', () async {
      final id = await service.createProject(name: 'P');
      final source = await original('a.txt', 'A');
      final file = (await service.addFiles(id, [source])).added.single;
      expect(await service.originalExists(file), isTrue);

      await service.deleteOriginal(id, file.id);

      expect(await File(source).exists(), isFalse);
      expect(await service.originalExists(file), isFalse);
      final kept = (await service.readProject(id)).files.single;
      expect(String.fromCharCodes(await decrypted(id, kept)), 'A');
    });

    test('delete from both removes both, and keeps the copy if the original is gone', () async {
      final id = await service.createProject(name: 'P');
      final a = (await service.addFiles(id, [await original('a.txt', 'A')])).added.single;
      final b = (await service.addFiles(id, [await original('b.txt', 'B')])).added.single;

      await service.deleteFromBoth(id, a.id);
      expect(await File(a.originalPath!).exists(), isFalse);
      expect((await service.readProject(id)).files.map((f) => f.id), [b.id]);

      await File(b.originalPath!).delete();
      await expectLater(service.deleteFromBoth(id, b.id), throwsA(isA<FileSystemException>()));
      expect((await service.readProject(id)).files.map((f) => f.id), [b.id]);
    });
  });

  group('tags', () {
    late String id;
    late List<FileEntry> files;

    setUp(() async {
      id = await service.createProject(name: 'P');
      await service.applyTagChanges(id, TagChanges(added: ['Photos', 'Receipts', 'Plans']));
      files = (await service.addFiles(id, [
        await original('a.jpg', 'A'),
        await original('b.pdf', 'B'),
        await original('c.txt', 'C'),
      ])).added;
      await service.setFileTags(id, {
        files[0].id: ['Photos'],
        files[1].id: ['receipts', 'Plans'], // Matched to the project's spelling.
      });
    });

    test('file tags use the project spelling and ignore unknown tags', () async {
      await service.setFileTags(id, {files[2].id: ['Plans', 'Nonexistent']});
      final index = await service.readProject(id);
      expect(index.files[1].tags, ['Receipts', 'Plans']);
      expect(index.files[2].tags, ['Plans']);
    });

    test('new tags from the tag editor are added to the project', () async {
      await service.setFileTags(id, {files[2].id: ['Permits']}, newTags: ['Permits']);
      final index = await service.readProject(id);
      expect(index.tags, contains('Permits'));
      expect(index.files[2].tags, ['Permits']);
    });

    test('a batch renames, adds and removes, and never deletes files', () async {
      await service.applyTagChanges(id, TagChanges(renames: {'Receipts': 'Receipts & Invoices'}, added: ['Permits'], removed: {'Plans'}));
      final index = await service.readProject(id);
      expect(index.tags, ['Photos', 'Receipts & Invoices', 'Permits']);
      expect(index.files, hasLength(3));
      expect(index.files[0].tags, ['Photos']);
      expect(index.files[1].tags, ['Receipts & Invoices']);
      expect(index.files.where((f) => f.tags.isEmpty).map((f) => f.name), ['c.txt']);
    });

    test('a duplicate added tag is ignored', () async {
      await service.applyTagChanges(id, TagChanges(added: ['photos']));
      expect((await service.readProject(id)).tags, ['Photos', 'Receipts', 'Plans']);
    });
  });
}
