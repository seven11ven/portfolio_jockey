import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// The few C library functions the app needs: plain memory for buffers that
/// hold no keys, syncing a folder after a rename, and creating a private
/// folder whose permissions are right from the start, free disk space, and
/// the real location of a file handed over by the document portal.
///
/// Only the symbols listed in tool/allowed-native-libs.txt may be looked up
/// here; tool/check-privacy.sh enforces that.
final class Libc {
  Libc._(DynamicLibrary lib)
    : _malloc = lib.lookupFunction<Pointer<Void> Function(Size), Pointer<Void> Function(int)>('malloc'),
      _free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free'),
      _open = lib.lookupFunction<Int Function(Pointer<Char>, Int, VarArgs<(UnsignedInt,)>), int Function(Pointer<Char>, int, int)>('open'),
      _fsync = lib.lookupFunction<Int Function(Int), int Function(int)>('fsync'),
      _close = lib.lookupFunction<Int Function(Int), int Function(int)>('close'),
      _mkdir = lib.lookupFunction<Int Function(Pointer<Char>, UnsignedInt), int Function(Pointer<Char>, int)>('mkdir'),
      _statvfs = lib.lookupFunction<Int Function(Pointer<Char>, Pointer<Uint8>), int Function(Pointer<Char>, Pointer<Uint8>)>('statvfs'),
      _getxattr = lib.lookupFunction<IntPtr Function(Pointer<Char>, Pointer<Char>, Pointer<Uint8>, Size), int Function(Pointer<Char>, Pointer<Char>, Pointer<Uint8>, int)>('getxattr');

  static Libc? _instance;

  /// The C library, loaded once per isolate.
  static Libc get instance => _instance ??= Libc._(DynamicLibrary.open('libc.so.6'));

  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final int Function(Pointer<Char>, int, int) _open;
  final int Function(int) _fsync;
  final int Function(int) _close;
  final int Function(Pointer<Char>, int) _mkdir;
  final int Function(Pointer<Char>, Pointer<Uint8>) _statvfs;
  final int Function(Pointer<Char>, Pointer<Char>, Pointer<Uint8>, int) _getxattr;

  static const int _readOnly = 0; // O_RDONLY, the same on every Linux architecture.

  /// Allocates [size] bytes of ordinary native memory. Free it with [free].
  Pointer<Uint8> malloc(int size) {
    final pointer = _malloc(size == 0 ? 1 : size);
    if (pointer == nullptr) {
      throw const OutOfMemoryError();
    }
    return pointer.cast();
  }

  void free(Pointer<NativeType> pointer) => _free(pointer.cast());

  /// Flushes a folder's entries to disk, so a rename inside it survives a power cut.
  ///
  /// Some file systems can't sync a folder. The rename has already happened by
  /// then, so a failed sync is ignored rather than reported as a failed write.
  void syncDirectory(String path) {
    final bytes = utf8.encode(path);
    final cPath = malloc(bytes.length + 1);
    try {
      cPath.asTypedList(bytes.length).setAll(0, bytes);
      cPath[bytes.length] = 0;
      final fd = _open(cPath.cast(), _readOnly, 0);
      if (fd < 0) {
        throw FileSystemException('Cannot open the folder to sync it', path);
      }
      _fsync(fd);
      _close(fd);
    } finally {
      free(cPath);
    }
  }

  /// Creates the folder [path] with permissions [mode] (for example `0x1C0`,
  /// which is 0700), so it is never readable by others, not even briefly. The
  /// process umask can only remove permissions. Throws if it can't be created,
  /// including when it already exists.
  void makeDirectory(String path, int mode) {
    final bytes = utf8.encode(path);
    final cPath = malloc(bytes.length + 1);
    try {
      cPath.asTypedList(bytes.length).setAll(0, bytes);
      cPath[bytes.length] = 0;
      if (_mkdir(cPath.cast(), mode) != 0) {
        throw FileSystemException('Cannot create the folder', path);
      }
    } finally {
      free(cPath);
    }
  }

  /// Bytes free for this user on the drive holding [path], or null if it
  /// can't be read. Uses glibc's `struct statvfs` on 64-bit Linux (x86-64 and
  /// arm64 share its layout): `f_frsize` at byte 8 and `f_bavail` at byte 32,
  /// both 64-bit.
  int? freeBytes(String path) {
    final bytes = utf8.encode(path);
    final cPath = malloc(bytes.length + 1);
    final result = malloc(_statvfsSize);
    try {
      cPath.asTypedList(bytes.length).setAll(0, bytes);
      cPath[bytes.length] = 0;
      if (_statvfs(cPath.cast(), result) != 0) {
        return null;
      }
      final data = ByteData.sublistView(result.asTypedList(_statvfsSize));
      return data.getUint64(32, Endian.host) * data.getUint64(8, Endian.host);
    } finally {
      free(cPath);
      free(result);
    }
  }

  // sizeof(struct statvfs) is 112 bytes on 64-bit glibc; a larger buffer
  // leaves room if a future glibc grows it.
  static const int _statvfsSize = 256;

  /// The real path of a file picked through the document portal (inside a
  /// Flatpak, picked files arrive as `/run/user/<uid>/doc/<id>/<name>`), or
  /// null if [path] has no such attribute, doesn't exist or is too long.
  /// Reads the portal's `user.document-portal.host-path` attribute.
  String? hostPath(String path) {
    final cPath = _cString(path);
    final cName = _cString(_hostPathAttribute);
    final value = malloc(_hostPathMax);
    try {
      final length = _getxattr(cPath.cast(), cName.cast(), value, _hostPathMax);
      if (length <= 0) {
        return null;
      }
      var bytes = value.asTypedList(length);
      if (bytes.last == 0) {
        bytes = bytes.sublist(0, length - 1);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      free(cPath);
      free(cName);
      free(value);
    }
  }

  Pointer<Uint8> _cString(String text) {
    final bytes = utf8.encode(text);
    final pointer = malloc(bytes.length + 1);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    pointer[bytes.length] = 0;
    return pointer;
  }

  static const String _hostPathAttribute = 'user.document-portal.host-path';

  // PATH_MAX on Linux. A longer value fails with ERANGE and gives null.
  static const int _hostPathMax = 4096;
}
