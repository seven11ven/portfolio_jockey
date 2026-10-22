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
}
