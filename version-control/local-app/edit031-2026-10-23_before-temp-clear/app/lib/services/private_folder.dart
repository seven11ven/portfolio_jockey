import 'dart:io';

import 'package:portfolio_jockey/services/sandbox.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// Why the private memory-only folder can't be used. The message is shown
/// to the user as is.
final class NoPrivateFolder implements Exception {
  const NoPrivateFolder(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Private, memory-only folders for readable copies (editing, and playing
/// audio or video), under `$XDG_RUNTIME_DIR/portfolio_jockey/`.
///
/// `$XDG_RUNTIME_DIR` is the login session's own folder (mode 0700, usually
/// `/run/user/<uid>`), which desktops keep in memory (tmpfs). The app refuses
/// to make a readable copy anywhere else: if the folder isn't set, isn't
/// private, or isn't in memory, [create] throws [NoPrivateFolder] instead of
/// falling back to a disk folder. Folders are made with mode 0700 by libc's
/// `mkdir`, so they're never readable by others, not even briefly.
final class PrivateFolders {
  PrivateFolders({required this.runtimeDir, Future<String> Function()? readMountInfo})
    : _readMountInfo = readMountInfo ?? (() => File('/proc/self/mountinfo').readAsString());

  /// The real session folder, from `$XDG_RUNTIME_DIR`.
  factory PrivateFolders.standard() => PrivateFolders(runtimeDir: Platform.environment['XDG_RUNTIME_DIR']);

  /// Where "Edit in another app" copies go. Outside a Flatpak, the same as
  /// [PrivateFolders.standard]. Inside one, the memory folder Flatpak shares
  /// with the desktop (`$XDG_RUNTIME_DIR/app/$FLATPAK_ID`): the desktop's
  /// portal can't hand the other app a file in the sandbox's own memory folder
  /// ("Launch failed", found in testing, 2026-10-23). Same checks: private,
  /// in memory, never a disk fallback. Media copies stay in [standard].
  factory PrivateFolders.forEditing({bool? sandboxed, Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final runtime = env['XDG_RUNTIME_DIR'];
    final appId = env['FLATPAK_ID'];
    if ((sandboxed ?? runningInFlatpak()) && runtime != null && appId != null && appId.isNotEmpty && !appId.contains('/')) {
      return PrivateFolders(runtimeDir: '$runtime/app/$appId');
    }
    return PrivateFolders(runtimeDir: runtime);
  }

  static const String appFolderName = 'portfolio_jockey';
  static const int _privateMode = 0x1C0; // 0700
  static const Set<String> _memoryFileSystems = {'tmpfs', 'ramfs'};

  final String? runtimeDir;
  final Future<String> Function() _readMountInfo;

  /// Creates a new empty folder `<prefix>-<random>` with mode 0700.
  Future<Directory> create(String prefix) async {
    final root = await _root();
    final folder = Directory('${root.path}/$prefix-${newId()}');
    Libc.instance.makeDirectory(folder.path, _privateMode);
    return folder;
  }

  /// The existing `<prefix>-*` folders, for example an edit left by a crash.
  /// Empty if the app folder doesn't exist or can't be used.
  Future<List<Directory>> existing(String prefix) async {
    final dir = runtimeDir;
    if (dir == null || dir.isEmpty) {
      return [];
    }
    final root = Directory('$dir/$appFolderName');
    if (!await root.exists()) {
      return [];
    }
    return [
      await for (final entity in root.list(followLinks: false))
        if (entity is Directory && entity.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('$prefix-')) entity,
    ];
  }

  /// The app's folder in the session folder, after checking it's private and
  /// in memory.
  Future<Directory> _root() async {
    final dir = runtimeDir;
    if (dir == null || dir.isEmpty || !dir.startsWith('/')) {
      throw const NoPrivateFolder("XDG_RUNTIME_DIR isn't set");
    }
    final session = Directory(dir);
    if (!await session.exists()) {
      throw NoPrivateFolder("XDG_RUNTIME_DIR ($dir) doesn't exist");
    }
    final resolved = await session.resolveSymbolicLinks();
    await _checkPrivate(resolved);
    final fileSystem = memoryFileSystemOf(resolved, await _readMountInfo());
    if (fileSystem == null) {
      throw NoPrivateFolder("XDG_RUNTIME_DIR ($dir) isn't in memory");
    }
    final root = Directory('$resolved/$appFolderName');
    if (!await root.exists()) {
      Libc.instance.makeDirectory(root.path, _privateMode);
    }
    if (await FileSystemEntity.isLink(root.path)) {
      throw NoPrivateFolder('${root.path} is a link, not a folder');
    }
    await _checkPrivate(root.path);
    return root;
  }

  static Future<void> _checkPrivate(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.directory || stat.mode & 0x3F != 0) {
      throw NoPrivateFolder('$path can be read by other users');
    }
  }

  /// The memory file system type ("tmpfs" or "ramfs") that [path] is on,
  /// according to [mountInfo] (the format of `/proc/self/mountinfo`), or null
  /// if it's on anything else. [path] must have no symbolic links.
  static String? memoryFileSystemOf(String path, String mountInfo) {
    String? bestMount;
    String? bestType;
    for (final line in mountInfo.split('\n')) {
      final separator = line.indexOf(' - ');
      if (separator < 0) {
        continue;
      }
      final fields = line.substring(0, separator).split(' ');
      final after = line.substring(separator + 3).split(' ');
      if (fields.length < 5 || after.isEmpty) {
        continue;
      }
      final mount = _unescape(fields[4]);
      final inside = mount == '/' || path == mount || path.startsWith('$mount/');
      // Later lines are mounted on top of earlier ones at the same place.
      if (inside && (bestMount == null || mount.length >= bestMount.length)) {
        bestMount = mount;
        bestType = after.first;
      }
    }
    return _memoryFileSystems.contains(bestType) ? bestType : null;
  }

  /// mountinfo writes space, tab, newline and backslash as octal escapes.
  static String _unescape(String field) =>
      field.replaceAllMapped(RegExp(r'\\([0-7]{3})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)));

  /// Overwrites every file in [folder] with zeros, then deletes the folder and
  /// everything in it, including files an editor added (backups, lock files).
  /// Links are deleted, never followed.
  static Future<void> wipe(Directory folder) async {
    if (!await folder.exists()) {
      return;
    }
    await for (final entity in folder.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        await overwriteWithZeros(entity);
      }
    }
    await folder.delete(recursive: true);
  }

  /// Overwrites [file] with zeros in place, keeping its length.
  static Future<void> overwriteWithZeros(File file) async {
    const block = 64 * 1024;
    try {
      final out = await file.open(mode: FileMode.append);
      try {
        final length = await out.length();
        await out.setPosition(0);
        final zeros = List<int>.filled(block, 0);
        for (var done = 0; done < length; done += block) {
          await out.writeFrom(zeros, 0, length - done < block ? length - done : block);
        }
        await out.flush();
      } finally {
        await out.close();
      }
    } on FileSystemException {
      // Read-only or already gone: it's still deleted with the folder.
    }
  }
}
