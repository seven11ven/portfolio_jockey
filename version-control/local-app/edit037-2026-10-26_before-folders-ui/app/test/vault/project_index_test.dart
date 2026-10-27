import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/project_index.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import 'test_helpers.dart';

void main() {
  late Directory root;
  late UnlockedVault vault;

  setUp(() async {
    root = await tempFolder();
    vault = await Vault.create(root, 'pass', kdf: fastKdf);
    addTearDown(vault.lock);
  });

  test('an index round-trips every field', () async {
    final file = FileEntry.create(name: 'notes.md', size: 42, tags: ['draft']);
    final id = await vault.createProject(
      ProjectIndex(name: 'Novel', description: 'Chapter drafts', tags: ['draft', 'final'], files: [file], coverKey: 'abc='),
    );

    final index = await vault.readIndex(id);
    expect(index.name, 'Novel');
    expect(index.description, 'Chapter drafts');
    expect(index.tags, ['draft', 'final']);
    expect(index.coverKey, 'abc=');
    expect(index.files.single.toJson(), file.toJson());
  });

  test('updating an index replaces it', () async {
    final id = await vault.createProject(ProjectIndex(name: 'Old'));
    await vault.writeIndex(id, ProjectIndex(name: 'New'));
    expect((await vault.readIndex(id)).name, 'New');
  });

  test('names are not stored in plain text', () async {
    final id = await vault.createProject(ProjectIndex(name: 'SecretProjectName'));
    final bytes = await vault.layout.indexFile(id).readAsBytes();
    expect(String.fromCharCodes(bytes).contains('SecretProjectName'), isFalse);
  });

  test('projectIds lists projects and ignores other folders', () async {
    final a = await vault.createProject(ProjectIndex(name: 'A'));
    final b = await vault.createProject(ProjectIndex(name: 'B'));
    await Directory('${root.path}/not-a-project').create();
    expect(await vault.projectIds(), unorderedEquals([a, b]));
  });

  test('a changed index fails its integrity check', () async {
    final id = await vault.createProject(ProjectIndex(name: 'P'));
    final file = vault.layout.indexFile(id);
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 20] ^= 1;
    await file.writeAsBytes(bytes);
    await expectLater(vault.readIndex(id), throwsA(isA<TamperedData>()));
  });

  test('an index moved to another project fails its integrity check', () async {
    final a = await vault.createProject(ProjectIndex(name: 'A'));
    final b = await vault.createProject(ProjectIndex(name: 'B'));
    await vault.layout.indexFile(a).copy(vault.layout.indexFile(b).path);
    await expectLater(vault.readIndex(b), throwsA(isA<TamperedData>()));
  });

  test('an index from another vault fails its integrity check', () async {
    final otherRoot = await tempFolder();
    final other = await Vault.create(otherRoot, 'pass', kdf: fastKdf);
    addTearDown(other.lock);
    final id = await other.createProject(ProjectIndex(name: 'Other'));
    await vault.layout.blobDir(id).create(recursive: true);
    await other.layout.indexFile(id).copy(vault.layout.indexFile(id).path);
    await expectLater(vault.readIndex(id), throwsA(isA<TamperedData>()));
  });

  test('IDs that are not vault IDs never become paths', () {
    expect(() => vault.layout.indexFile('../etc'), throwsArgumentError);
    expect(() => vault.layout.blobFile('0' * 32, '../../x'), throwsArgumentError);
    expect(
      () => FileEntry(id: 'x/y', name: 'n', size: 0, addedAt: DateTime.now(), key: ''),
      throwsArgumentError,
    );
  });

  group('folders', () {
    String id(int n) => n.toRadixString(16).padLeft(32, '0');
    final created = DateTime.utc(2026, 10, 3);
    FolderEntry folder(int n, {String? name, int? parent}) => FolderEntry(id: id(n), name: name ?? 'Folder $n', parentId: parent == null ? null : id(parent), createdAt: created);
    FileEntry file(String name, {int? folder, int size = 10}) => FileEntry.create(name: name, size: size, folderId: folder == null ? null : id(folder));
    Map<String, Object?> jsonOf(ProjectIndex index) => index.toJson();

    test('folders and where files sit round-trip', () async {
      final inside = file('a.txt', folder: 2);
      final projectId = await vault.createProject(ProjectIndex(name: 'P', files: [inside, file('top.txt')], folders: [folder(1, name: 'Invoices'), folder(2, name: '2026', parent: 1)]));
      final read = await vault.readIndex(projectId);
      expect([for (final f in read.folders) f.toJson()], [for (final f in [folder(1, name: 'Invoices'), folder(2, name: '2026', parent: 1)]) f.toJson()]);
      expect(read.files.first.folderId, id(2));
      expect(read.files.last.folderId, isNull);
    });

    test('an index from before folders loads with everything at the top level', () {
      final old = jsonOf(ProjectIndex(name: 'Old', files: [file('a.txt')]));
      expect(old.containsKey('folders'), isFalse);
      expect((old['files']! as List).single as Map, isNot(contains('folderId')));
      final read = ProjectIndex.fromJson(old);
      expect(read.folders, isEmpty);
      expect(read.filesIn(null).single.name, 'a.txt');
    });

    test('an unsafe set of folders is refused on load', () {
      // The constructor doesn't validate; fromJson does.
      void bad(List<FolderEntry> folders, [List<FileEntry> files = const []]) => expect(() => ProjectIndex.fromJson(jsonOf(ProjectIndex(name: 'P', folders: folders, files: [...files]))), throwsFormatException);
      bad([folder(1), folder(1)]);
      bad([folder(1, parent: 9)]);
      bad([folder(1, parent: 1)]);
      bad([folder(1, parent: 2), folder(2, parent: 1)]);
      bad([folder(1)], [file('a', folder: 9)]);
      bad([folder(1, name: '')]);
      bad([folder(1, name: '  ')]);
      bad([folder(1, name: '.')]);
      bad([folder(1, name: '..')]);
      bad([folder(1, name: 'a/b')]);
      bad([folder(1, name: 'a\nb')]);
      bad([folder(1, name: 'a\u0000b')]);
    });

    test('a folder with an ID that is not a vault ID is refused on load, not thrown at', () {
      final json = jsonOf(ProjectIndex(name: 'P', folders: [folder(1)]));
      ((json['folders']! as List).single as Map<String, Object?>)['id'] = '../x';
      expect(() => ProjectIndex.fromJson(json), throwsFormatException);
    });

    test('an unsafe index is never written', () async {
      final projectId = await vault.createProject(ProjectIndex(name: 'P'));
      await expectLater(() => vault.writeIndex(projectId, ProjectIndex(name: 'P', folders: [folder(1, parent: 2), folder(2, parent: 1)])), throwsFormatException);
      expect((await vault.readIndex(projectId)).folders, isEmpty);
    });

    test('names have no length limit, and any text but slashes and control characters is fine', () {
      final long = 'é' * 5000;
      final index = ProjectIndex(name: 'P', folders: [folder(1, name: long), folder(2, name: '  Résumé 2026 (final)… 日本語 😀  '), folder(3, name: '.hidden'), folder(4, name: '...')]);
      expect(() => ProjectIndex.fromJson(jsonOf(index)), returnsNormally);
      expect(folderNameProblem(long), isNull);
      expect(folderNameProblem('a/b'), isNotNull);
    });

    test('a very deep chain of folders works without recursion', () {
      const depth = 50000;
      final folders = [for (var n = 1; n <= depth; n++) folder(n, parent: n == 1 ? null : n - 1)];
      final index = ProjectIndex.fromJson(jsonOf(ProjectIndex(name: 'P', folders: folders, files: [file('deep.txt', folder: depth, size: 7), file('mid.txt', folder: 100, size: 3)])));
      expect(index.pathTo(id(depth)), hasLength(depth));
      expect(index.pathTo(id(depth)).first.id, id(1));
      expect(index.subtreeIds(id(1)), hasLength(depth));
      final stats = index.statsOf(id(100));
      expect((stats.files, stats.folders, stats.bytes), (2, depth - 100, 10));
      expect(index.canMoveFolder(id(1), id(depth)), isFalse);
    });

    test('statistics count everything inside, at any depth', () {
      final index = ProjectIndex(
        name: 'P',
        folders: [folder(1, name: 'Invoices'), folder(2, name: '2026', parent: 1), folder(3, name: 'Plans')],
        files: [file('a', folder: 1, size: 100), file('b', folder: 2, size: 20), file('c', folder: 2, size: 3), file('d', folder: 3, size: 5), file('top', size: 1)],
      );
      final stats = index.statsOf(id(1));
      expect((stats.files, stats.folders, stats.bytes), (3, 1, 123));
      final empty = index.statsOf(id(3));
      expect((empty.files, empty.folders, empty.bytes), (1, 0, 5));
      expect([for (final f in index.foldersIn(null)) f.name], ['Invoices', 'Plans']);
      expect([for (final f in index.foldersIn(id(1))) f.name], ['2026']);
      expect([for (final f in index.filesIn(id(2))) f.name], ['b', 'c']);
      expect([for (final f in index.pathTo(id(2))) f.name], ['Invoices', '2026']);
      expect(index.pathTo(null), isEmpty);
    });

    test('a folder can move anywhere except into itself or its own contents', () {
      final index = ProjectIndex(name: 'P', folders: [folder(1), folder(2, parent: 1), folder(3, parent: 2), folder(4)]);
      expect(index.canMoveFolder(id(1), null), isTrue);
      expect(index.canMoveFolder(id(1), id(4)), isTrue);
      expect(index.canMoveFolder(id(3), id(1)), isTrue);
      expect(index.canMoveFolder(id(1), id(1)), isFalse);
      expect(index.canMoveFolder(id(1), id(3)), isFalse);
      expect(index.canMoveFolder(id(2), id(3)), isFalse);
    });
  });
}
