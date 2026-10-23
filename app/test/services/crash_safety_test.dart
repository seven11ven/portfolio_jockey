import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/vault/journal.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import '../vault/test_helpers.dart';

/// Thrown at a crash point to stand in for a crash or power cut there.
class _Crash implements Exception {}

void main() {
  late Directory root;
  late ProjectService service;

  setUp(() async {
    root = await tempFolder();
    final vault = await Vault.create(root, 'test passphrase', kdf: fastKdf);
    addTearDown(vault.lock);
    service = ProjectService(vault, trasher: FakeTrash(await tempFolder()));
  });

  /// A fresh service on the same vault, as after a restart.
  Future<ProjectService> restart() async {
    final vault = await Vault.unlock(root, 'test passphrase');
    addTearDown(vault.lock);
    return ProjectService(vault, trasher: FakeTrash(await tempFolder()));
  }

  Future<String> contents(ProjectService s, String id) async =>
      utf8.decode(await s.readFile(id, (await s.readProject(id)).files.single, maxBytes: 1000));

  Future<(String, File)> projectWithFile(String text) async {
    final id = await service.createProject(name: 'P');
    final source = File('${(await tempFolder()).path}/notes.txt')..writeAsStringSync(text);
    await service.addFiles(id, [source.path]);
    final edited = File('${(await tempFolder()).path}/edited.txt');
    return (id, edited);
  }

  group('saving an edit', () {
    for (final step in ['blob written', 'index saved']) {
      test('a crash after "$step" leaves one complete version', () async {
        final (id, edited) = await projectWithFile('old text');
        edited.writeAsStringSync('new, longer text');
        final fileId = (await service.readProject(id)).files.single.id;
        service.crashPoint = (at) {
          if (at == step) {
            throw _Crash();
          }
        };
        await expectLater(service.replaceContent(id, fileId, edited), throwsA(isA<_Crash>()));

        final after = await restart();
        final text = await contents(after, id);
        final entry = (await after.readProject(id)).files.single;
        expect(text, step == 'blob written' ? 'old text' : 'new, longer text');
        expect(entry.size, utf8.encode(text).length, reason: 'the size always matches the version the index points at');
      });
    }

    test('an entry from an older vault (no blobId) is edited the same way', () async {
      final (id, edited) = await projectWithFile('old text');
      expect((await service.readProject(id)).files.single.blobId, isNull);
      edited.writeAsStringSync('edited');
      await service.replaceContent(id, (await service.readProject(id)).files.single.id, edited);
      final entry = (await service.readProject(id)).files.single;
      expect(entry.blobId, isNotNull);
      expect(await contents(service, id), 'edited');
      expect(Directory('${root.path}/$id/blobs').listSync().length, 1, reason: 'the old blob is deleted');
    });
  });

  group('replacing a cover', () {
    for (final step in ['cover written', 'index saved']) {
      test('a crash after "$step" leaves a readable cover', () async {
        final first = Uint8List.fromList([1, 2, 3]);
        final second = Uint8List.fromList([4, 5, 6, 7]);
        final id = await service.createProject(name: 'P', cover: first);
        service.crashPoint = (at) {
          if (at == step) {
            throw _Crash();
          }
        };
        await expectLater(service.updateDetails(id, description: '', cover: ReplaceCover(second)), throwsA(isA<_Crash>()));

        final after = await restart();
        expect(await after.readCover(id, await after.readProject(id)), step == 'cover written' ? first : second);
      });
    }
  });

  test('an edit cut off before session.json was written is wiped at unlock, never offered', () async {
    final folders = await fakePrivateFolders();
    final cutOff = await folders.create('edit');
    await Directory('${cutOff.path}/file').create();
    await File('${cutOff.path}/file/notes.txt').writeAsString('half a fi');
    final edits = EditSessions(folders: folders, launcher: FakeLauncher(), settle: Duration.zero);
    addTearDown(edits.dispose);
    await edits.findLeftovers();
    expect(edits.leftovers, isEmpty);
    expect(await cutOff.exists(), isFalse);
  });

  group('the journal, after a crash', () {
    test('an interrupted unlocked export: the readable temp file is zeroed and removed', () async {
      final folder = await tempFolder();
      final temp = File('${folder.path}/.Kitchen.zip.tmp-abc')..writeAsStringSync('readable project content');
      await service.journalPut(ExportStarted('e1', tempPath: temp.path));

      final notices = await (await restart()).recoverJournal(openEditIds: {});
      expect(await temp.exists(), isFalse);
      expect(notices.single, contains('export was interrupted'));
      expect(await (await restart()).journalEntries(), isEmpty);
    });

    test('an interrupted import: the projects it created are removed', () async {
      final keep = await service.createProject(name: 'Mine');
      final half = await service.createProject(name: 'Imported', id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90');
      await service.journalPut(const ImportStarted('i1', projectIds: ['a1b2c3d4e5f60718293a4b5c6d7e8f90', 'ffffffffffffffffffffffffffffffff']));

      final after = await restart();
      final notices = await after.recoverJournal(openEditIds: {});
      expect(notices.single, contains('import was interrupted'));
      final ids = [for (final p in (await after.listProjects()).projects) p.id];
      expect(ids, [keep]);
      expect(half, isNot(keep));
    });

    test('a move cut off before the switch: the unfinished copy is removed, the vault stays', () async {
      final target = await tempFolder();
      File('${target.path}/half-copied.enc').writeAsStringSync('x');
      await service.journalPut(MoveStarted('m1', source: root.absolute.path, target: target.absolute.path));

      final notices = await (await restart()).recoverJournal(openEditIds: {});
      expect(notices.single, contains('stay where they were'));
      expect(target.listSync(), isEmpty);
      expect(await File('${root.path}/.pj/vault').exists(), isTrue);
    });

    test('a move cut off after the switch: the old folder is removed', () async {
      final old = await tempFolder();
      await Process.run('cp', ['-a', '${root.path}/.', old.path]);
      // The vault in use is `root`; `old` is the copy the move came from.
      await service.journalPut(MoveStarted('m2', source: old.absolute.path, target: root.absolute.path));

      final notices = await (await restart()).recoverJournal(openEditIds: {});
      expect(notices.single, contains('move is complete'));
      expect(await old.exists(), isFalse);
      expect(await File('${root.path}/.pj/vault').exists(), isTrue);
    });

    test("an edit whose copy is gone is reported; one that's still there is left for the user", () async {
      await service.journalPut(const EditStarted('edit-gone', projectName: 'Kitchen', fileName: 'notes.txt'));
      await service.journalPut(const EditStarted('edit-here', projectName: 'Kitchen', fileName: 'plan.txt'));

      final after = await restart();
      final notices = await after.recoverJournal(openEditIds: {'edit-here'});
      expect(notices.single, contains('notes.txt in Kitchen was open when the app closed'));
      expect([for (final e in await after.journalEntries()) e.id], ['edit-here']);
    });

    test('a damaged journal is refused, not trusted', () async {
      await service.journalPut(const ExportStarted('e1', tempPath: '/nowhere'));
      final file = File('${root.path}/.pj/journal.enc');
      final bytes = file.readAsBytesSync()..[40] ^= 1;
      file.writeAsBytesSync(bytes);
      await expectLater((await restart()).recoverJournal(openEditIds: {}), throwsA(anything));
    });
  });

  group('clean-up at unlock', () {
    test('removes only unreferenced leftovers, and never touches an unreadable project', () async {
      final (id, _) = await projectWithFile('kept');
      final blobs = Directory('${root.path}/$id/blobs');
      final kept = blobs.listSync().single as File;
      final orphan = File('${blobs.path}/0123456789abcdef0123456789abcdef.enc')..writeAsStringSync('orphan');
      final temp = File('${blobs.path}/.x.enc.tmp-1')..writeAsStringSync('t');
      final oldCover = File('${root.path}/$id/cover.enc')..writeAsStringSync('old cover');
      final fresh = File('${blobs.path}/fedcba9876543210fedcba9876543210.enc')..writeAsStringSync('being added right now');
      await fresh.setLastModified(DateTime.now().add(const Duration(hours: 1)));
      final broken = await service.createProject(name: 'Broken');
      File('${root.path}/$broken/index.enc').writeAsStringSync('not an index');
      final brokenBlob = File('${root.path}/$broken/blobs/0000000000000000000000000000aaaa.enc')..writeAsStringSync('keep');

      final removed = await (await restart()).cleanUp();
      expect(removed, 3);
      expect(await orphan.exists(), isFalse);
      expect(await temp.exists(), isFalse);
      expect(await oldCover.exists(), isFalse);
      expect(await kept.exists(), isTrue);
      expect(await fresh.exists(), isTrue, reason: 'written after the clean-up started');
      expect(await brokenBlob.exists(), isTrue, reason: 'an unreadable project is never cleaned');
      expect(await contents(await restart(), id), 'kept');
    });
  });
}
