import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/storage_move.dart';

import '../vault/test_helpers.dart';

void main() {
  test('copies every file and folder, checks them, and leaves the source alone', () async {
    final source = await tempFolder();
    await Directory('${source.path}/.pj').create();
    await File('${source.path}/.pj/vault').writeAsString('header');
    await Directory('${source.path}/p1/blobs').create(recursive: true);
    await File('${source.path}/p1/index.enc').writeAsString('index');
    await File('${source.path}/p1/blobs/a.enc').writeAsBytes(List.filled(70000, 7));
    final picked = await tempFolder();
    final move = await StorageMove.plan(source, picked);
    final watch = Stopwatch()..start();
    await move.copyAndVerify();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await File('${move.target.path}/p1/blobs/a.enc').length(), 70000);
    expect(await File('${move.target.path}/.pj/vault').readAsString(), 'header');
    expect(await File('${source.path}/p1/index.enc').exists(), isTrue);
  });
}
