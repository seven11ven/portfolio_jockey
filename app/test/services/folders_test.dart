import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import '../vault/test_helpers.dart';

class _Crash implements Exception {}

void main() {
  late Directory root;
  late ProjectService service;
  late String project;

  setUp(() async {
    root = await tempFolder();
    final vault = await Vault.create(root, 'test passphrase', kdf: fastKdf);
    addTearDown(vault.lock);
    service = ProjectService(vault, trasher: FakeTrash(await tempFolder()));
    project = await service.createProject(name: 'P');
  });

  Future<String> addFile(String name, String text, {String? folderId}) async {
    final source = File('${(await tempFolder()).path}/$name')..writeAsStringSync(text);
    final result = await service.addFiles(project, [source.path], folderId: folderId);
    return result.added.single.id;
  }

  Future<List<String>> blobs() async => [for (final f in await service.vault.layout.blobDir(project).list().toList()) if (f.path.endsWith('.enc')) f.path];

  group('creating and renaming', () {
    test('folders can be nested at any level, and the same name can sit in different parents', () async {
      final a = await service.createFolder(project, name: 'Invoices');
      final b = await service.createFolder(project, name: '2026', parentId: a.id);
      final c = await service.createFolder(project, name: '2026');
      final index = await service.readProject(project);
      expect(index.foldersIn(null).map((f) => f.name), ['Invoices', '2026']);
      expect(index.foldersIn(a.id).single.id, b.id);
      expect(index.pathTo(b.id).map((f) => f.name), ['Invoices', '2026']);
      expect(c.parentId, isNull);
    });

    test('a name is trimmed, and a clash in the same folder is refused ignoring case', () async {
      final f = await service.createFolder(project, name: '  Plans  ');
      expect(f.name, 'Plans');
      await expectLater(service.createFolder(project, name: 'plans'), throwsA(isA<FolderNameError>().having((e) => e.message, 'message', contains('already exists'))));
      expect((await service.readProject(project)).folders, hasLength(1));
    });

    test('unsafe or empty names are refused with a reason, and nothing is written', () async {
      for (final name in ['', '   ', '.', '..', 'a/b', 'a\nb']) {
        await expectLater(service.createFolder(project, name: name), throwsA(isA<FolderNameError>()), reason: 'name: ${jsonEncode(name)}');
      }
      expect((await service.readProject(project)).folders, isEmpty);
    });

    test('a folder in a parent that does not exist is refused', () async {
      await expectLater(service.createFolder(project, name: 'X', parentId: '0' * 32), throwsStateError);
    });

    test('renaming works, refuses a sibling clash, and allows changing only the case', () async {
      final a = await service.createFolder(project, name: 'Plans');
      await service.createFolder(project, name: 'Photos');
      await expectLater(service.renameFolder(project, a.id, 'PHOTOS'), throwsA(isA<FolderNameError>()));
      await service.renameFolder(project, a.id, 'PLANS');
      await service.renameFolder(project, a.id, ' Blueprints ');
      expect((await service.readProject(project)).folderById(a.id)!.name, 'Blueprints');
    });
  });

  group('adding files', () {
    test('files go into the chosen folder, and the encrypted copies stay in one flat place', () async {
      final folder = await service.createFolder(project, name: 'Docs');
      final inside = await addFile('a.txt', 'in folder', folderId: folder.id);
      final top = await addFile('b.txt', 'at top');
      final index = await service.readProject(project);
      expect(index.filesIn(folder.id).single.id, inside);
      expect(index.filesIn(null).single.id, top);
      expect(await blobs(), hasLength(2));
    });

    test('a folder that does not exist is refused before anything is encrypted', () async {
      final source = File('${(await tempFolder()).path}/a.txt')..writeAsStringSync('x');
      await expectLater(service.addFiles(project, [source.path], folderId: '0' * 32), throwsStateError);
      expect(await blobs(), isEmpty);
    });
  });

  group('moving', () {
    test('files and folders move in one saved change, and contents stay readable', () async {
      final docs = await service.createFolder(project, name: 'Docs');
      final sub = await service.createFolder(project, name: 'Sub');
      final fileId = await addFile('a.txt', 'hello');
      final result = await service.moveItems(project, fileIds: [fileId], folderIds: [sub.id], targetFolderId: docs.id);
      expect(result.moved, 2);
      expect(result.renamed, isEmpty);
      final index = await service.readProject(project);
      expect(index.filesIn(docs.id).single.id, fileId);
      expect(index.foldersIn(docs.id).single.id, sub.id);
      expect(utf8.decode(await service.readFile(project, index.files.single, maxBytes: 100)), 'hello');
    });

    test('moving to the top level (null) takes things out of a folder', () async {
      final docs = await service.createFolder(project, name: 'Docs');
      final fileId = await addFile('a.txt', 'x', folderId: docs.id);
      await service.moveItems(project, fileIds: [fileId], targetFolderId: null);
      expect((await service.readProject(project)).filesIn(null).single.id, fileId);
    });

    test('a folder can never go into itself or a folder inside it, and nothing changes', () async {
      final a = await service.createFolder(project, name: 'A');
      final b = await service.createFolder(project, name: 'B', parentId: a.id);
      final c = await service.createFolder(project, name: 'C', parentId: b.id);
      final before = (await service.readProject(project)).toJson();
      for (final target in [a.id, b.id, c.id]) {
        await expectLater(service.moveItems(project, folderIds: [a.id], targetFolderId: target), throwsStateError);
      }
      await expectLater(service.moveItems(project, folderIds: [b.id], targetFolderId: c.id), throwsStateError);
      expect((await service.readProject(project)).toJson(), before);
    });

    test('a clashing name gets (2), (3)…, with a file\'s number before its extension', () async {
      final docs = await service.createFolder(project, name: 'Docs');
      await service.createFolder(project, name: 'Plans', parentId: docs.id);
      await addFile('report.txt', 'inside', folderId: docs.id);
      final plans = await service.createFolder(project, name: 'plans');
      final one = await addFile('Report.txt', 'one');
      final two = await addFile('report.txt', 'two');
      final result = await service.moveItems(project, fileIds: [one, two], folderIds: [plans.id], targetFolderId: docs.id);
      expect(result.moved, 3);
      expect(result.renamed, [('plans', 'plans (2)'), ('Report.txt', 'Report (2).txt'), ('report.txt', 'report (3).txt')]);
      final index = await service.readProject(project);
      expect(index.filesIn(docs.id).map((f) => f.name), ['report.txt', 'Report (2).txt', 'report (3).txt']);
      expect(index.foldersIn(docs.id).map((f) => f.name), ['Plans', 'plans (2)']);
    });

    test('items already in the target are left alone, and nothing is written', () async {
      final docs = await service.createFolder(project, name: 'Docs');
      final fileId = await addFile('a.txt', 'x', folderId: docs.id);
      final changed = (await service.readProject(project)).changedAt;
      final result = await service.moveItems(project, fileIds: [fileId], targetFolderId: docs.id);
      expect(result.moved, 0);
      expect((await service.readProject(project)).changedAt, changed);
    });

    test('a target that does not exist is refused', () async {
      final fileId = await addFile('a.txt', 'x');
      await expectLater(service.moveItems(project, fileIds: [fileId], targetFolderId: '0' * 32), throwsStateError);
    });
  });

  group('deleting a folder', () {
    test('removes the folder, everything inside at any depth, and the encrypted files, and reports the counts', () async {
      final a = await service.createFolder(project, name: 'A');
      final b = await service.createFolder(project, name: 'B', parentId: a.id);
      final keep = await service.createFolder(project, name: 'Keep');
      await addFile('one.txt', '1', folderId: a.id);
      await addFile('two.txt', '22', folderId: b.id);
      final kept = await addFile('keep.txt', 'kept', folderId: keep.id);
      await addFile('top.txt', 'top');
      expect(await blobs(), hasLength(4));

      final stats = await service.deleteFolder(project, a.id);
      expect((stats.files, stats.folders, stats.bytes), (2, 1, 3));
      final index = await service.readProject(project);
      expect(index.folders.map((f) => f.id), [keep.id]);
      expect(index.files.map((f) => f.name), unorderedEquals(['keep.txt', 'top.txt']));
      expect(await blobs(), hasLength(2));
      expect(utf8.decode(await service.readFile(project, index.files.firstWhere((f) => f.id == kept), maxBytes: 100)), 'kept');
    });

    test('an empty folder can be deleted', () async {
      final a = await service.createFolder(project, name: 'A');
      final stats = await service.deleteFolder(project, a.id);
      expect((stats.files, stats.folders, stats.bytes), (0, 0, 0));
      expect((await service.readProject(project)).folders, isEmpty);
    });

    test('a crash after the index is saved leaves only unlisted files, which clean-up removes', () async {
      final a = await service.createFolder(project, name: 'A');
      await addFile('one.txt', '1', folderId: a.id);
      service.crashPoint = (at) {
        if (at == 'index saved') {
          throw _Crash();
        }
      };
      await expectLater(service.deleteFolder(project, a.id), throwsA(isA<_Crash>()));
      final index = await service.readProject(project);
      expect(index.folders, isEmpty);
      expect(index.files, isEmpty);
      expect(await blobs(), hasLength(1));
      expect(await service.cleanUp(), 1);
      expect(await blobs(), isEmpty);
    });

    test('a folder that does not exist is refused', () async {
      await expectLater(service.deleteFolder(project, '0' * 32), throwsStateError);
    });
  });
}
