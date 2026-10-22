import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';
import 'package:portfolio_jockey/services/native/gio_trash.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

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

/// A mountinfo line saying [path] is mounted as [type].
String mountLine(String path, {String type = 'tmpfs'}) => '36 25 0:32 / $path rw,nosuid,nodev - $type $type rw,size=100k,mode=700';

/// Private folders in a new 0700 temporary folder that a fake mount table
/// reports as tmpfs, so tests never touch the real XDG_RUNTIME_DIR.
Future<PrivateFolders> fakePrivateFolders({String type = 'tmpfs'}) async {
  final runtime = Directory('${(await tempFolder()).path}/run');
  Libc.instance.makeDirectory(runtime.path, 0x1C0);
  final resolved = await runtime.resolveSymbolicLinks();
  return PrivateFolders(runtimeDir: runtime.path, readMountInfo: () async => '${mountLine('/')}\n${mountLine(resolved, type: type)}\n');
}

/// A stand-in for opening files in other apps: records what was opened.
class FakeLauncher implements AppLauncher {
  FakeLauncher({this.apps = const [InstalledApp(id: 'org.example.Editor.desktop', name: 'Text Editor', isDefault: true)], this.usesDesktopChooser = false});

  final List<InstalledApp> apps;

  @override
  final bool usesDesktopChooser;

  final List<(String path, String? appId)> opened = [];

  @override
  Future<List<InstalledApp>> appsFor(String fileName) async => usesDesktopChooser ? [] : apps;

  @override
  Future<void> open(String path, {String? appId}) async => opened.add((path, appId));
}
