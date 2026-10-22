import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:portfolio_jockey/vault/native/libc.dart';

/// Moves files to the system Trash.
abstract interface class Trasher {
  /// Throws [FileSystemException] if the file can't be moved to the Trash.
  Future<void> trash(String path);
}

/// The desktop's Trash, through GLib's `g_file_trash()`.
///
/// Inside a Flatpak, GLib hands the file to the Trash portal over the session
/// D-Bus (local IPC, not the network). Otherwise it moves the file into the
/// freedesktop Trash (`~/.local/share/Trash`, or `.Trash-<uid>` on other
/// drives). Reviewed in GLib's gio/glocalfile.c and gio/gtrashportal.c; see
/// docs/dependencies.md. Only the four functions below may be bound here
/// (tool/allowed-native-libs.txt), so GIO's network functions stay out of reach.
final class GioTrash implements Trasher {
  const GioTrash();

  @override
  Future<void> trash(String path) async {
    final error = await Isolate.run(() => _trashNow(path));
    if (error != null) {
      throw FileSystemException("Couldn't move it to the Trash: $error", path);
    }
  }
}

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Uint8> message;
}

/// Returns null on success, or GLib's error message.
String? _trashNow(String path) {
  final gio = DynamicLibrary.open('libgio-2.0.so.0');
  final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
  final glib = DynamicLibrary.open('libglib-2.0.so.0');
  final newForPath = gio.lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>('g_file_new_for_path');
  final trash = gio.lookupFunction<
    Int Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<_GError>>),
    int Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<_GError>>)
  >('g_file_trash');
  final unref = gobject.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_object_unref');
  final freeError = glib.lookupFunction<Void Function(Pointer<_GError>), void Function(Pointer<_GError>)>('g_error_free');

  final libc = Libc.instance;
  final bytes = utf8.encode(path);
  final cPath = libc.malloc(bytes.length + 1);
  final errorOut = libc.malloc(sizeOf<Pointer<_GError>>()).cast<Pointer<_GError>>();
  try {
    cPath.asTypedList(bytes.length).setAll(0, bytes);
    cPath[bytes.length] = 0;
    errorOut.value = nullptr;
    final file = newForPath(cPath);
    try {
      if (trash(file, nullptr, errorOut) != 0) {
        return null;
      }
      final error = errorOut.value;
      if (error == nullptr) {
        return 'unknown error';
      }
      final message = _cString(error.ref.message);
      freeError(error);
      return message;
    } finally {
      unref(file);
    }
  } finally {
    libc
      ..free(cPath)
      ..free(errorOut);
  }
}

String _cString(Pointer<Uint8> chars) {
  if (chars == nullptr) {
    return 'unknown error';
  }
  var length = 0;
  while (chars[length] != 0) {
    length++;
  }
  return utf8.decode(chars.asTypedList(length), allowMalformed: true);
}
