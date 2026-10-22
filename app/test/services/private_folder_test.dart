import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/private_folder.dart';

import '../vault/test_helpers.dart';

void main() {
  group('memoryFileSystemOf', () {
    const mountInfo = '''
22 1 8:1 / / rw,relatime - ext4 /dev/sda1 rw
25 22 0:22 / /run rw,nosuid - tmpfs tmpfs rw,mode=755
40 25 0:35 / /run/user/1000 rw,nosuid,nodev - tmpfs tmpfs rw,size=1600k,mode=700
41 22 0:36 / /home/me/My\\040Files rw - tmpfs tmpfs rw
42 40 8:2 / /run/user/1000/disk rw - ext4 /dev/sdb1 rw
''';

    test('finds the deepest mount that holds the path', () {
      expect(PrivateFolders.memoryFileSystemOf('/run/user/1000', mountInfo), 'tmpfs');
      expect(PrivateFolders.memoryFileSystemOf('/run/user/1000/portfolio_jockey', mountInfo), 'tmpfs');
      expect(PrivateFolders.memoryFileSystemOf('/run/user/1000/disk/x', mountInfo), isNull);
      expect(PrivateFolders.memoryFileSystemOf('/home/me', mountInfo), isNull);
      expect(PrivateFolders.memoryFileSystemOf('/run/user/10000', mountInfo), 'tmpfs', reason: '/run, not /run/user/1000');
    });

    test('unescapes spaces in mount points', () {
      expect(PrivateFolders.memoryFileSystemOf('/home/me/My Files/x', mountInfo), 'tmpfs');
    });

    test('a later mount on the same place wins', () {
      expect(PrivateFolders.memoryFileSystemOf('/run/x', '$mountInfo${mountLine('/run', type: 'ext4')}\n'), isNull);
    });
  });

  group('create', () {
    test('makes a 0700 folder in a 0700 app folder', () async {
      final folders = await fakePrivateFolders();
      final folder = await folders.create('edit');
      expect(folder.path, contains('/${PrivateFolders.appFolderName}/edit-'));
      expect((await folder.stat()).mode & 0x1FF, 0x1C0);
      expect((await folder.parent.stat()).mode & 0x1FF, 0x1C0);
      expect(await folders.existing('edit'), [isA<Directory>().having((d) => d.path, 'path', folder.path)]);
      expect(await folders.existing('view'), isEmpty);
    });

    test('refuses when XDG_RUNTIME_DIR is not set', () async {
      await expectLater(PrivateFolders(runtimeDir: null).create('edit'), throwsA(isA<NoPrivateFolder>()));
      await expectLater(PrivateFolders(runtimeDir: 'relative').create('edit'), throwsA(isA<NoPrivateFolder>()));
    });

    test('refuses a folder that is not in memory, and writes nothing', () async {
      final folders = await fakePrivateFolders(type: 'ext4');
      await expectLater(folders.create('edit'), throwsA(isA<NoPrivateFolder>().having((e) => e.message, 'message', contains("isn't in memory"))));
      expect(await Directory(folders.runtimeDir!).list().toList(), isEmpty);
    });

    test('refuses a session folder others can read', () async {
      final folders = await fakePrivateFolders();
      await Process.run('chmod', ['755', folders.runtimeDir!]);
      await expectLater(folders.create('edit'), throwsA(isA<NoPrivateFolder>().having((e) => e.message, 'message', contains('other users'))));
    });

    test('refuses when the app folder is a link', () async {
      final folders = await fakePrivateFolders();
      final elsewhere = await tempFolder();
      await Link('${folders.runtimeDir}/${PrivateFolders.appFolderName}').create(elsewhere.path);
      await expectLater(folders.create('edit'), throwsA(isA<NoPrivateFolder>()));
    });
  });

  group('wipe', () {
    test('overwriteWithZeros keeps the length and zeroes the content', () async {
      final file = File('${(await tempFolder()).path}/secret.txt');
      await file.writeAsBytes(List.generate(150 * 1000, (i) => i % 251 + 1));
      await PrivateFolders.overwriteWithZeros(file);
      final bytes = await file.readAsBytes();
      expect(bytes.length, 150 * 1000);
      expect(bytes.every((b) => b == 0), isTrue);
    });

    test('deletes everything, including links, without following them', () async {
      final folders = await fakePrivateFolders();
      final folder = await folders.create('edit');
      final outside = File('${(await tempFolder()).path}/outside.txt');
      await outside.writeAsString('keep me');
      await Directory('${folder.path}/file').create();
      await File('${folder.path}/file/notes.txt').writeAsString('secret');
      await File('${folder.path}/file/.notes.txt.swp').writeAsString('editor backup');
      await Link('${folder.path}/file/link').create(outside.path);

      await PrivateFolders.wipe(folder);
      expect(await folder.exists(), isFalse);
      expect(await outside.readAsString(), 'keep me');
      await PrivateFolders.wipe(folder); // already gone: fine
    });
  });
}
