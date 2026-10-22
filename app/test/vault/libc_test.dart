import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

void main() {
  test('freeBytes matches df (statvfs struct layout on 64-bit Linux)', () async {
    final folder = Directory.systemTemp.path;
    final free = Libc.instance.freeBytes(folder);
    final df = await Process.run('df', ['-B1', '--output=avail', folder]);
    final expected = int.parse('${df.stdout}'.trim().split('\n').last.trim());
    expect(free, isNotNull);
    // Other processes may write meanwhile, so allow 64 MB of drift.
    expect((free! - expected).abs(), lessThan(64 * 1024 * 1024));
  });

  test('freeBytes is null for a folder that does not exist', () {
    expect(Libc.instance.freeBytes('/no/such/folder/anywhere'), isNull);
  });

  test('hostPath is null for an ordinary file and for a missing one', () async {
    final file = File('${(await Directory.systemTemp.createTemp('pj_xattr')).path}/a.txt');
    addTearDown(() => file.parent.delete(recursive: true));
    await file.writeAsString('a');
    expect(Libc.instance.hostPath(file.path), isNull);
    expect(Libc.instance.hostPath('/no/such/file/anywhere'), isNull);
  });

  test('hostPath reads the document portal attribute', () async {
    final file = File('${(await Directory.systemTemp.createTemp('pj_xattr')).path}/a.txt');
    addTearDown(() => file.parent.delete(recursive: true));
    await file.writeAsString('a');
    // The portal's own mount can't exist here, so set the same attribute on
    // a temp file (needs a filesystem with user attributes).
    const script = 'import os,sys; os.setxattr(sys.argv[1], "user.document-portal.host-path", "/home/someone/Ünïcode a.txt".encode() + bytes([0]))';
    final set = await Process.run('python3', ['-I', '-c', script, file.path]);
    if (set.exitCode != 0) {
      markTestSkipped('This filesystem has no user attributes: ${set.stderr}');
      return;
    }
    expect(Libc.instance.hostPath(file.path), '/home/someone/Ünïcode a.txt');
  });
}
