import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/gio_trash.dart';
import 'package:portfolio_jockey/vault/kdf.dart';

/// libsodium's smallest Argon2id settings, so tests run fast. Real vaults use
/// [KdfParams.moderate].
const KdfParams fastKdf = KdfParams(opsLimit: 1, memLimit: 8192);

/// A stand-in Trash: moves files into its own temporary folder, so tests
/// never touch the real Trash. Set [failWith] to make it refuse.
class FakeTrash implements Trasher {
  FakeTrash(this.folder);

  final Directory folder;
  final List<String> trashed = [];
  String? failWith;

  @override
  Future<void> trash(String path) async {
    if (failWith case final reason?) {
      throw FileSystemException(reason, path);
    }
    await File(path).rename('${folder.path}/${File(path).uri.pathSegments.last}');
    trashed.add(path);
  }
}

/// A new empty folder, deleted after the test.
Future<Directory> tempFolder() async {
  final folder = await Directory.systemTemp.createTemp('pj_vault_test_');
  addTearDown(() => folder.delete(recursive: true));
  return folder;
}
