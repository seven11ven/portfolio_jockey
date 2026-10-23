import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:portfolio_jockey/vault/native/libc.dart';

/// The desktop's OpenURI portal (`org.freedesktop.portal.OpenURI`), called
/// directly over the session D-Bus that Flatpak always provides to an app.
/// It's local D-Bus only: no network, and no extra sandbox permission.
///
/// GLib's own `g_app_info_launch_default_for_uri` sends the portal request
/// asynchronously on the calling thread's main loop, which our short-lived
/// worker isolates don't run, so nothing appeared. These calls are
/// synchronous, pass options GLib doesn't (`ask`, `writable`), and report the
/// portal's errors instead of losing them.
///
/// Only the symbols listed in tool/allowed-native-libs.txt may be looked up
/// here; tool/check-privacy.sh enforces that.
abstract final class OpenUriPortal {
  /// Asks the desktop to open [path] in an app the user picks every time
  /// (`ask`), with write access (`writable`) so the app can save its edits.
  /// Throws [PortalException] if the portal refuses.
  static Future<void> openFile(String path) => _run(path, 'OpenFile', openFileArguments, writable: true);

  /// Asks the desktop's file manager to show the folder that contains [path].
  static Future<void> openContainingFolder(String path) => _run(path, 'OpenDirectory', openDirectoryArguments, writable: false);

  /// The arguments of `OpenFile`, in GVariant text format: the parent window
  /// (none), the file as fd handle 0 of the attached list, and the options.
  static const String openFileArguments = "('', handle 0, {'ask': <true>, 'writable': <true>})";

  /// The arguments of `OpenDirectory`: no parent window, fd handle 0, no options.
  static const String openDirectoryArguments = "('', handle 0, @a{sv} {})";

  /// Parses [arguments] the way a request does, against the `(sha{sv})`
  /// signature both methods take. Returns null if they're valid, else GLib's
  /// reason. For tests.
  static String? checkArguments(String arguments) {
    final g = _GDBus();
    final libc = Libc.instance;
    final errorOut = libc.malloc(sizeOf<Pointer<_GError>>()).cast<Pointer<_GError>>();
    errorOut.value = nullptr;
    final type = _toC('(sha{sv})');
    final text = _toC(arguments);
    try {
      final parsed = g.variantParse(type, text, nullptr, nullptr, errorOut);
      if (parsed == nullptr) {
        return g.takeError(errorOut, 'invalid');
      }
      g.variantUnref(parsed);
      return null;
    } finally {
      libc
        ..free(type)
        ..free(text)
        ..free(errorOut.cast());
    }
  }

  static Future<void> _run(String path, String method, String arguments, {required bool writable}) async {
    final error = await Isolate.run(() => _call(path, method, arguments, writable));
    if (error != null) {
      throw PortalException(error);
    }
  }
}

/// The portal refused a request, with its reason.
final class PortalException implements Exception {
  const PortalException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Uint8> message;
}

final class _GDBus {
  _GDBus() {
    final gio = DynamicLibrary.open('libgio-2.0.so.0');
    final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    final glib = DynamicLibrary.open('libglib-2.0.so.0');
    busGetSync = gio.lookupFunction<Pointer<Void> Function(Int, Pointer<Void>, Pointer<Pointer<_GError>>), Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<_GError>>)>('g_bus_get_sync');
    callWithFds = gio.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>, Int, Int, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<_GError>>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>, int, int, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<_GError>>)
    >('g_dbus_connection_call_with_unix_fd_list_sync');
    fdListNew = gio.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('g_unix_fd_list_new');
    fdListAppend = gio.lookupFunction<Int Function(Pointer<Void>, Int, Pointer<Pointer<_GError>>), int Function(Pointer<Void>, int, Pointer<Pointer<_GError>>)>('g_unix_fd_list_append');
    variantParse = glib.lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<Uint8>>, Pointer<Pointer<_GError>>),
      Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<Uint8>>, Pointer<Pointer<_GError>>)
    >('g_variant_parse');
    variantUnref = glib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_variant_unref');
    errorFree = glib.lookupFunction<Void Function(Pointer<_GError>), void Function(Pointer<_GError>)>('g_error_free');
    objectUnref = gobject.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_object_unref');
  }

  late final Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<_GError>>) busGetSync;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>, int, int, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<_GError>>) callWithFds;
  late final Pointer<Void> Function() fdListNew;
  late final int Function(Pointer<Void>, int, Pointer<Pointer<_GError>>) fdListAppend;
  late final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<Uint8>>, Pointer<Pointer<_GError>>) variantParse;
  late final void Function(Pointer<Void>) variantUnref;
  late final void Function(Pointer<_GError>) errorFree;
  late final void Function(Pointer<Void>) objectUnref;

  /// Takes the message out of a GError and frees it.
  String takeError(Pointer<Pointer<_GError>> errorOut, String fallback) {
    final error = errorOut.value;
    if (error == nullptr) {
      return fallback;
    }
    final message = _fromC(error.ref.message);
    errorFree(error);
    errorOut.value = nullptr;
    return message;
  }
}

const int _sessionBus = 2; // G_BUS_TYPE_SESSION

/// Runs in a worker isolate. Returns null on success, else the reason.
String? _call(String path, String method, String arguments, bool writable) {
  final g = _GDBus();
  final libc = Libc.instance;
  final errorOut = libc.malloc(sizeOf<Pointer<_GError>>()).cast<Pointer<_GError>>();
  errorOut.value = nullptr;
  final strings = <Pointer<Uint8>>[];
  Pointer<Uint8> c(String text) {
    final pointer = _toC(text);
    strings.add(pointer);
    return pointer;
  }

  final fd = writable ? libc.openReadWrite(path) : libc.openReadOnly(path);
  if (fd < 0) {
    libc.free(errorOut.cast());
    return "can't open $path";
  }
  Pointer<Void> bus = nullptr;
  Pointer<Void> fds = nullptr;
  Pointer<Void> parameters = nullptr;
  try {
    bus = g.busGetSync(_sessionBus, nullptr, errorOut);
    if (bus == nullptr) {
      return g.takeError(errorOut, 'no session D-Bus');
    }
    fds = g.fdListNew();
    if (g.fdListAppend(fds, fd, errorOut) < 0) {
      return g.takeError(errorOut, "couldn't pass the file to the portal");
    }
    // The GVariantType argument is a type string.
    parameters = g.variantParse(c('(sha{sv})'), c(arguments), nullptr, nullptr, errorOut);
    if (parameters == nullptr) {
      return g.takeError(errorOut, 'bad portal request');
    }
    final reply = g.callWithFds(
      bus,
      c('org.freedesktop.portal.Desktop'),
      c('/org/freedesktop/portal/desktop'),
      c('org.freedesktop.portal.OpenURI'),
      c(method),
      parameters,
      nullptr,
      0,
      -1,
      fds,
      nullptr,
      nullptr,
      errorOut,
    );
    if (reply == nullptr) {
      return g.takeError(errorOut, 'the portal refused the request');
    }
    g.variantUnref(reply);
    return null;
  } finally {
    if (parameters != nullptr) {
      g.variantUnref(parameters);
    }
    if (fds != nullptr) {
      g.objectUnref(fds);
    }
    if (bus != nullptr) {
      g.objectUnref(bus);
    }
    libc.closeFd(fd);
    for (final pointer in strings) {
      libc.free(pointer);
    }
    libc.free(errorOut.cast());
  }
}

Pointer<Uint8> _toC(String text) {
  final bytes = utf8.encode(text);
  final pointer = Libc.instance.malloc(bytes.length + 1);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  pointer[bytes.length] = 0;
  return pointer;
}

String _fromC(Pointer<Uint8> pointer) {
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}
