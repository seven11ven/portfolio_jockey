import 'dart:io';

import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// Writes [target] so it ends up either completely written or untouched.
///
/// [write] fills a temporary file in the same folder. That file is flushed to
/// disk and renamed over [target] (a rename within one folder is atomic), and
/// then the folder is synced so the rename itself survives a power cut. If
/// [write] fails, the temporary file is removed and [target] is unchanged;
/// [beforeDelete] runs first, for example to overwrite readable content.
Future<void> writeAtomically(File target, Future<void> Function(RandomAccessFile file) write, {Future<void> Function(File temp)? beforeDelete}) async {
  final folder = target.parent;
  final name = target.uri.pathSegments.last;
  final temp = File('${folder.path}/.$name.tmp-${newId()}');
  var renamed = false;
  try {
    final file = await temp.open(mode: FileMode.writeOnly);
    try {
      await write(file);
      await file.flush();
    } finally {
      await file.close();
    }
    await temp.rename(target.path);
    renamed = true;
  } finally {
    if (!renamed && await temp.exists()) {
      await beforeDelete?.call(temp);
      await temp.delete();
    }
  }
  Libc.instance.syncDirectory(folder.path);
}

Future<void> writeBytesAtomically(File target, List<int> bytes) => writeAtomically(target, (file) async {
  await file.writeFrom(bytes);
});
