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
}
