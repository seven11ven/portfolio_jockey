import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/libc.dart';

/// Why the storage location can't be moved where the user chose.
final class MoveRefused implements Exception {
  const MoveRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

final class MoveProgress {
  const MoveProgress(this.bytesDone, this.bytesTotal);

  final int bytesDone;
  final int bytesTotal;
}

/// Moves the vault folder: everything is copied, each copy is read back and
/// compared byte for byte, and only then may the old folder be removed. If
/// anything fails, the partial copy is removed and the old folder stays in
/// use.
final class StorageMove {
  StorageMove._(this.source, this.target, this.bytesTotal, this.fileCount);

  final Directory source;
  final Directory target;
  final int bytesTotal;
  final int fileCount;

  /// Plans a move of [source] into the folder the user [picked]: the picked
  /// folder itself if it's empty, otherwise a new "Portfolio Jockey" folder
  /// inside it. Throws [MoveRefused] if that isn't possible.
  static Future<StorageMove> plan(Directory source, Directory picked) async {
    final from = await source.resolveSymbolicLinks();
    final pickedPath = await picked.resolveSymbolicLinks();
    final target = await _isEmpty(Directory(pickedPath)) ? Directory(pickedPath) : Directory('$pickedPath/Portfolio Jockey');
    final to = target.path;
    if (to == from || to.startsWith('$from/') || from.startsWith('$to/')) {
      throw const MoveRefused('The new location is the same folder, or inside the current one.');
    }
    if (await target.exists() && !await _isEmpty(target)) {
      throw MoveRefused('$to already exists and isn\'t empty. Choose an empty folder.');
    }
    var bytes = 0;
    var files = 0;
    await for (final entity in Directory(from).list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw MoveRefused('The storage folder contains a link (${entity.path}), which isn\'t moved.');
      }
      if (entity is File) {
        bytes += await entity.length();
        files++;
      }
    }
    return StorageMove._(Directory(from), target, bytes, files);
  }

  /// Bytes free where the copy goes, or null if unknown.
  int? get freeAtTarget {
    var folder = target;
    while (!folder.existsSync() && folder.parent.path != folder.path) {
      folder = folder.parent;
    }
    return Libc.instance.freeBytes(folder.path);
  }

  /// Copies everything to [target] and checks every copy. On failure the
  /// partial copy is removed and the error is rethrown.
  Future<void> copyAndVerify({void Function(MoveProgress progress)? onProgress}) async {
    final createdTarget = !await target.exists();
    var done = 0;
    try {
      await target.create(recursive: true);
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        final relative = entity.path.substring(source.path.length);
        if (entity is Directory) {
          await Directory('${target.path}$relative').create(recursive: true);
        } else if (entity is File) {
          final copy = File('${target.path}$relative');
          await copy.parent.create(recursive: true);
          await _copy(entity, copy);
          await _verify(entity, copy);
          done += await entity.length();
          // The journal entry for this move is written after planning, so the
          // copy can be a little bigger than planned.
          onProgress?.call(MoveProgress(done < bytesTotal ? done : bytesTotal, bytesTotal));
        }
      }
      // Every folder of the copy, deepest first, then the folder holding the
      // target: the copy must be on disk before the old folder is removed.
      final folders = [await for (final e in target.list(recursive: true, followLinks: false)) if (e is Directory) e.path]
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final folder in [...folders, target.path, target.parent.path]) {
        Libc.instance.syncDirectory(folder);
      }
    } on Object {
      if (createdTarget) {
        await target.delete(recursive: true).catchError((_) => target);
      } else {
        // The picked folder was empty: empty it again.
        await for (final entity in target.list(followLinks: false)) {
          await entity.delete(recursive: true);
        }
      }
      rethrow;
    }
  }

  /// Removes the old folder, once the vault is in use from [target].
  Future<void> removeSource() => source.delete(recursive: true);

  static Future<bool> _isEmpty(Directory folder) async => !await folder.exists() || await folder.list().isEmpty;

  static Future<void> _copy(File from, File to) async {
    final out = await to.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in from.openRead()) {
        await out.writeFrom(chunk);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  static Future<void> _verify(File original, File copy) async {
    final a = await original.open();
    final b = await copy.open();
    try {
      if (await a.length() != await b.length()) {
        throw FileSystemException('The copy has a different size', copy.path);
      }
      const block = 1024 * 1024;
      while (true) {
        final x = await a.read(block);
        final y = await b.read(block);
        if (!_same(x, y)) {
          throw FileSystemException("The copy doesn't match the original", copy.path);
        }
        if (x.isEmpty) {
          return;
        }
      }
    } finally {
      await a.close();
      await b.close();
    }
  }

  static bool _same(Uint8List x, Uint8List y) {
    if (x.length != y.length) {
      return false;
    }
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) {
        return false;
      }
    }
    return true;
  }
}
