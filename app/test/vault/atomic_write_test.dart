import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/atomic_write.dart';

import 'test_helpers.dart';

void main() {
  test('replaces the file and leaves no temporary file', () async {
    final folder = await tempFolder();
    final target = File('${folder.path}/index.enc');
    await target.writeAsString('old');

    await writeBytesAtomically(target, 'new'.codeUnits);

    expect(await target.readAsString(), 'new');
    expect((await folder.list().toList()).map((e) => e.path), [target.path]);
  });

  test('a failed write leaves the original untouched and no temporary file', () async {
    final folder = await tempFolder();
    final target = File('${folder.path}/index.enc');
    await target.writeAsString('original');

    await expectLater(
      writeAtomically(target, (file) async {
        await file.writeString('half');
        throw const FileSystemException('disk full');
      }),
      throwsA(isA<FileSystemException>()),
    );

    expect(await target.readAsString(), 'original');
    expect((await folder.list().toList()).map((e) => e.path), [target.path]);
  });
}
