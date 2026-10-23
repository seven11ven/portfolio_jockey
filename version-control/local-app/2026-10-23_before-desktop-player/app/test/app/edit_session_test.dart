import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import '../vault/test_helpers.dart';

void main() {
  late ProjectService service;
  late PrivateFolders folders;
  late FakeLauncher launcher;
  late EditSessions edits;
  late String projectId;
  late FileEntry notes;

  setUp(() async {
    final vault = await Vault.create(await tempFolder(), 'test passphrase', kdf: fastKdf);
    addTearDown(vault.lock);
    service = ProjectService(vault, trasher: FakeTrash(await tempFolder()));
    folders = await fakePrivateFolders();
    launcher = FakeLauncher();
    edits = EditSessions(folders: folders, launcher: launcher, settle: Duration.zero);
    addTearDown(edits.dispose);
    projectId = await service.createProject(name: 'Kitchen Remodel');
    final original = File('${(await tempFolder()).path}/measurements.txt');
    await original.writeAsString('Counter: 240 cm\n');
    await service.addFiles(projectId, [original.path]);
    notes = (await service.readProject(projectId)).files.single;
  });

  Future<EditSession> start({FileEntry? file}) =>
      edits.start(service: service, projectId: projectId, projectName: 'Kitchen Remodel', file: file ?? notes, app: launcher.apps.first);

  group('readFile', () {
    test('decrypts the whole file into memory', () async {
      expect(utf8.decode(await service.readFile(projectId, notes, maxBytes: 1000)), 'Counter: 240 cm\n');
    });

    test('refuses files over the limit before decrypting', () async {
      await expectLater(service.readFile(projectId, notes, maxBytes: 5), throwsA(isA<TooLargeToPreview>()));
    });

    test('returns nothing from a damaged file', () async {
      final blob = service.vault.layout.blobFile(projectId, notes.id);
      final bytes = await blob.readAsBytes();
      bytes[bytes.length - 3] ^= 1;
      await blob.writeAsBytes(bytes);
      await expectLater(service.readFile(projectId, notes, maxBytes: 1000), throwsA(isA<VaultException>()));
    });
  });

  test('start decrypts into a private folder and opens the copy', () async {
    final session = await start();
    expect(edits.active, same(session));
    expect(session.copy.path, startsWith(folders.runtimeDir!));
    expect(session.copy.path, endsWith('/file/measurements.txt'));
    expect(await session.copy.readAsString(), 'Counter: 240 cm\n');
    expect(launcher.opened, [(session.copy.path, 'org.example.Editor.desktop')]);
    final manifest = jsonDecode(await File('${session.folder.path}/session.json').readAsString()) as Map<String, Object?>;
    expect(manifest['fileId'], notes.id);
    expect(manifest['appName'], 'Text Editor');
    await expectLater(start(), throwsStateError, reason: 'one edit at a time');
  });

  test('no private folder: nothing is decrypted or opened', () async {
    final disk = EditSessions(folders: await fakePrivateFolders(type: 'ext4'), launcher: launcher);
    addTearDown(disk.dispose);
    await expectLater(
      disk.start(service: service, projectId: projectId, projectName: 'Kitchen Remodel', file: notes),
      throwsA(isA<NoPrivateFolder>()),
    );
    expect(launcher.opened, isEmpty);
    expect(disk.active, isNull);
  });

  test('a failed launch wipes the copy', () async {
    final failing = EditSessions(folders: folders, launcher: _FailingLauncher());
    addTearDown(failing.dispose);
    await expectLater(failing.start(service: service, projectId: projectId, projectName: 'K', file: notes), throwsA(isA<FileSystemException>()));
    expect(await folders.existing('edit'), isEmpty);
    expect(failing.active, isNull);
  });

  test('save re-encrypts the edited copy, updates the size and wipes the folder', () async {
    final session = await start();
    expect(await edits.hasChanges(service, session), isFalse);
    await session.copy.writeAsString('Counter: 245 cm\nSink: 60 cm\n');
    expect(await edits.hasChanges(service, session), isTrue);

    await edits.save(service, session);
    expect(edits.active, isNull);
    expect(await session.folder.exists(), isFalse);
    final saved = (await service.readProject(projectId)).files.single;
    expect(saved.id, notes.id);
    expect(saved.size, 28);
    expect(utf8.decode(await service.readFile(projectId, saved, maxBytes: 1000)), 'Counter: 245 cm\nSink: 60 cm\n');
  });

  group('save refuses a copy that is not ready, and keeps the project version', () {
    Future<String> projectText() async => utf8.decode(await service.readFile(projectId, (await service.readProject(projectId)).files.single, maxBytes: 1000));

    test('while the other app is still writing', () async {
      final slow = EditSessions(folders: folders, launcher: launcher, settle: const Duration(milliseconds: 400));
      addTearDown(slow.dispose);
      final session = await slow.start(service: service, projectId: projectId, projectName: 'Kitchen Remodel', file: notes, app: launcher.apps.first);
      Timer(const Duration(milliseconds: 100), () => session.copy.writeAsStringSync('Counter: 260 cm, half writ'));
      await expectLater(slow.save(service, session), throwsA(isA<EditNotReady>().having((e) => e.reason, 'reason', EditNotReadyReason.stillWriting)));
      expect(await projectText(), 'Counter: 240 cm\n');
      expect(await session.folder.exists(), isTrue, reason: 'the edit stays open');
    });

    test('an empty copy needs confirmation', () async {
      final session = await start();
      await session.copy.writeAsString('');
      await expectLater(edits.save(service, session), throwsA(isA<EditNotReady>().having((e) => e.reason, 'reason', EditNotReadyReason.empty)));
      expect(await projectText(), 'Counter: 240 cm\n');
      await edits.save(service, session, allowEmpty: true);
      expect((await service.readProject(projectId)).files.single.size, 0);
    });

    test('a copy replaced by a folder is refused', () async {
      final session = await start();
      await session.copy.delete();
      await Directory(session.copy.path).create();
      await expectLater(edits.save(service, session), throwsA(isA<FileSystemException>()));
      expect(await projectText(), 'Counter: 240 cm\n');
    });

    test('an unreadable copy fails partway: the old version is kept and the edit stays open', () async {
      final session = await start();
      await session.copy.writeAsString('Counter: 999 cm\n');
      await Process.run('chmod', ['000', session.copy.path]);
      addTearDown(() => Process.run('chmod', ['600', session.copy.path]));
      await expectLater(edits.save(service, session), throwsA(isA<Exception>()));
      expect(await projectText(), 'Counter: 240 cm\n');
      expect(await session.folder.exists(), isTrue);
    });
  });

  test('same-length edits are detected too', () async {
    final session = await start();
    await session.copy.writeAsString('Counter: 250 cm\n');
    expect(await edits.hasChanges(service, session), isTrue);
  });

  test('discard wipes the copy and keeps the project version', () async {
    final session = await start();
    await session.copy.writeAsString('changed');
    await edits.discard(session);
    expect(edits.active, isNull);
    expect(await session.folder.exists(), isFalse);
    expect(utf8.decode(await service.readFile(projectId, notes, maxBytes: 1000)), 'Counter: 240 cm\n');
  });

  test('an edit left by a crash is found again, and can be saved', () async {
    final session = await start();
    await session.copy.writeAsString('edited before the crash');
    final media = await edits.mediaCopy(service, projectId, notes);
    await Directory('${folders.runtimeDir}/${PrivateFolders.appFolderName}/edit-broken').create();

    final next = EditSessions(folders: folders, launcher: launcher);
    addTearDown(next.dispose);
    await next.findLeftovers();
    expect(next.leftovers.map((s) => s.info.fileName), ['measurements.txt']);
    expect(await media.exists(), isFalse, reason: 'media copies are wiped at unlock');
    expect(await Directory('${folders.runtimeDir}/${PrivateFolders.appFolderName}/edit-broken').exists(), isFalse);

    await next.save(service, next.leftovers.single);
    expect(next.leftovers, isEmpty);
    expect(await folders.existing('edit'), isEmpty);
    final saved = (await service.readProject(projectId)).files.single;
    expect(utf8.decode(await service.readFile(projectId, saved, maxBytes: 1000)), 'edited before the crash');
  });

  test('an edit of a deleted file has no project entry and no changes', () async {
    final session = await start();
    await session.copy.writeAsString('changed');
    await service.deleteFromProject(projectId, notes.id);
    expect(await edits.entryFor(service, session), isNull);
    expect(await edits.hasChanges(service, session), isFalse);
  });

  test('edit copies go in the edit folders, media copies stay in the private ones', () async {
    final shared = await fakePrivateFolders();
    final split = EditSessions(folders: folders, editFolders: shared, launcher: launcher, settle: Duration.zero);
    addTearDown(split.dispose);
    final session = await split.start(service: service, projectId: projectId, projectName: 'Kitchen Remodel', file: notes, app: launcher.apps.first);
    expect(session.folder.path, startsWith(shared.runtimeDir!));
    final media = await split.mediaCopy(service, projectId, notes);
    expect(media.path, startsWith(folders.runtimeDir!));
    expect(media.path, isNot(startsWith(shared.runtimeDir!)));
    await split.discard(session);
  });

  test('clearing temporary files keeps the open edit and wipes everything else', () async {
    final session = await start();
    final media = await edits.mediaCopy(service, projectId, notes);
    final stray = await folders.create('edit');
    expect(await edits.clearTemporaryFiles(), 2, reason: 'the media copy and the stray edit folder');
    expect(await media.exists(), isFalse);
    expect(await stray.exists(), isFalse);
    expect(await session.copy.exists(), isTrue, reason: 'unsaved changes are never cleared here');
    await edits.discard(session);
  });

  test('a media copy is a readable copy in its own private folder', () async {
    final copy = await edits.mediaCopy(service, projectId, notes);
    expect(copy.path, contains('/${PrivateFolders.appFolderName}/view-'));
    expect(await copy.readAsBytes(), Uint8List.fromList(utf8.encode('Counter: 240 cm\n')));
    await edits.wipeMediaCopies();
    expect(await copy.parent.exists(), isFalse);
  });
}

class _FailingLauncher extends FakeLauncher {
  @override
  Future<void> open(String path, {String? appId}) async => throw FileSystemException('no such app', path);
}
