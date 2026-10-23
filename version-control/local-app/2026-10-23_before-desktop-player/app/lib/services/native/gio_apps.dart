import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:portfolio_jockey/services/native/portal.dart';
import 'package:portfolio_jockey/services/sandbox.dart';
import 'package:portfolio_jockey/vault/native/libc.dart';

/// An app installed on the device that can open a file type.
final class InstalledApp {
  const InstalledApp({required this.id, required this.name, required this.isDefault});

  /// The desktop file ID, for example `org.gnome.TextEditor.desktop`.
  final String id;
  final String name;

  /// Whether it's the desktop's default app for this file type.
  final bool isDefault;
}

/// Opens files in other apps.
abstract interface class AppLauncher {
  /// Inside a Flatpak, apps can't be listed: the desktop's own app chooser
  /// (the OpenURI portal) asks instead.
  bool get usesDesktopChooser;

  /// The apps that can open a file named [fileName], the default first.
  /// Empty when [usesDesktopChooser].
  Future<List<InstalledApp>> appsFor(String fileName);

  /// Opens [path] in the app [appId], or through the desktop's chooser when
  /// [appId] is null. Throws [FileSystemException] if it can't be launched.
  Future<void> open(String path, {String? appId});

  /// Shows the folder [path] in the desktop's file manager. Throws
  /// [FileSystemException] if it can't.
  Future<void> openFolder(String path);
}

/// GLib's app-info functions (GIO).
///
/// Apps are found from their installed .desktop files by the file's type,
/// guessed from its name only (the file's content is never passed to GLib).
/// Launching runs the chosen app's own command with the file's path; GIO
/// also sends a local "Launched" signal on the session D-Bus, which desktops
/// use for their app lists. Inside a Flatpak, `g_app_info_launch_default_for_uri`
/// goes through the OpenURI portal, which shows the desktop's app chooser.
/// Reviewed in GLib's gio/gdesktopappinfo.c and gio/gappinfo.c; see
/// docs/dependencies.md. Only the functions listed in
/// tool/allowed-native-libs.txt may be bound here.
final class GioAppLauncher implements AppLauncher {
  const GioAppLauncher();

  @override
  bool get usesDesktopChooser => runningInFlatpak();

  @override
  Future<List<InstalledApp>> appsFor(String fileName) async {
    if (usesDesktopChooser) {
      return [];
    }
    final apps = await Isolate.run(() => _listApps(fileName));
    return [
      for (final [id, name, isDefault] in apps) InstalledApp(id: id! as String, name: name! as String, isDefault: isDefault! as bool),
    ];
  }

  @override
  Future<void> open(String path, {String? appId}) async {
    if (usesDesktopChooser) {
      // The portal can only hand the other app a file the desktop can reach:
      // one in the memory folder Flatpak shares with it. Anywhere else, it
      // fails without telling us, so refuse clearly instead.
      final env = Platform.environment;
      final shared = '${env['XDG_RUNTIME_DIR']}/app/${env['FLATPAK_ID']}';
      // Inside the sandbox that folder is a link to /run/flatpak/app/<id>,
      // and the copy's path is the resolved one, so accept either form.
      final sharedDir = Directory(shared);
      final resolved = sharedDir.existsSync() ? sharedDir.resolveSymbolicLinksSync() : shared;
      if (!isInFolder(path, [shared, resolved])) {
        throw FileSystemException("Couldn't open it in another app: the readable copy isn't in the folder the desktop can reach ($shared)", path);
      }
      // Through the portal directly: GLib's own call sends the request on a
      // main loop our worker isolate doesn't run, and can't ask for the
      // chooser or for write access (see portal.dart).
      try {
        await OpenUriPortal.openFile(path);
      } on PortalException catch (e) {
        throw FileSystemException("Couldn't open it in another app: $e", path);
      }
      return;
    }
    final error = await Isolate.run(() => _launch(path, appId));
    if (error != null) {
      throw FileSystemException("Couldn't open it in another app: $error", path);
    }
  }
  @override
  Future<void> openFolder(String path) async {
    if (usesDesktopChooser) {
      // OpenDirectory shows the folder that contains the file it's given, so
      // it's given the vault's own .pj folder, which every vault has.
      try {
        await OpenUriPortal.openContainingFolder('$path/.pj');
      } on PortalException catch (e) {
        throw FileSystemException("Couldn't open the folder: $e", path);
      }
      return;
    }
    final error = await Isolate.run(() => _launch(path, null));
    if (error != null) {
      throw FileSystemException("Couldn't open the folder: $error", path);
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

final class _GList extends Struct {
  external Pointer<Void> data;
  external Pointer<_GList> next;
  external Pointer<_GList> prev;
}

final class _Gio {
  _Gio() {
    final gio = DynamicLibrary.open('libgio-2.0.so.0');
    final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    final glib = DynamicLibrary.open('libglib-2.0.so.0');
    contentTypeGuess = gio.lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Size, Pointer<Int>),
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Int>)
    >('g_content_type_guess');
    allForType = gio.lookupFunction<Pointer<_GList> Function(Pointer<Uint8>), Pointer<_GList> Function(Pointer<Uint8>)>('g_app_info_get_all_for_type');
    defaultForType = gio.lookupFunction<Pointer<Void> Function(Pointer<Uint8>, Int), Pointer<Void> Function(Pointer<Uint8>, int)>('g_app_info_get_default_for_type');
    getId = gio.lookupFunction<Pointer<Uint8> Function(Pointer<Void>), Pointer<Uint8> Function(Pointer<Void>)>('g_app_info_get_id');
    getName = gio.lookupFunction<Pointer<Uint8> Function(Pointer<Void>), Pointer<Uint8> Function(Pointer<Void>)>('g_app_info_get_name');
    launch = gio.lookupFunction<
      Int Function(Pointer<Void>, Pointer<_GList>, Pointer<Void>, Pointer<Pointer<_GError>>),
      int Function(Pointer<Void>, Pointer<_GList>, Pointer<Void>, Pointer<Pointer<_GError>>)
    >('g_app_info_launch');
    launchDefaultForUri = gio.lookupFunction<
      Int Function(Pointer<Uint8>, Pointer<Void>, Pointer<Pointer<_GError>>),
      int Function(Pointer<Uint8>, Pointer<Void>, Pointer<Pointer<_GError>>)
    >('g_app_info_launch_default_for_uri');
    fileNewForPath = gio.lookupFunction<Pointer<Void> Function(Pointer<Uint8>), Pointer<Void> Function(Pointer<Uint8>)>('g_file_new_for_path');
    filenameToUri = glib.lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<_GError>>),
      Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<_GError>>)
    >('g_filename_to_uri');
    listAppend = glib.lookupFunction<Pointer<_GList> Function(Pointer<_GList>, Pointer<Void>), Pointer<_GList> Function(Pointer<_GList>, Pointer<Void>)>('g_list_append');
    listFree = glib.lookupFunction<Void Function(Pointer<_GList>), void Function(Pointer<_GList>)>('g_list_free');
    free = glib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_free');
    errorFree = glib.lookupFunction<Void Function(Pointer<_GError>), void Function(Pointer<_GError>)>('g_error_free');
    objectUnref = gobject.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_object_unref');
  }

  late final Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Int>) contentTypeGuess;
  late final Pointer<_GList> Function(Pointer<Uint8>) allForType;
  late final Pointer<Void> Function(Pointer<Uint8>, int) defaultForType;
  late final Pointer<Uint8> Function(Pointer<Void>) getId;
  late final Pointer<Uint8> Function(Pointer<Void>) getName;
  late final int Function(Pointer<Void>, Pointer<_GList>, Pointer<Void>, Pointer<Pointer<_GError>>) launch;
  late final int Function(Pointer<Uint8>, Pointer<Void>, Pointer<Pointer<_GError>>) launchDefaultForUri;
  late final Pointer<Void> Function(Pointer<Uint8>) fileNewForPath;
  late final Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Pointer<_GError>>) filenameToUri;
  late final Pointer<_GList> Function(Pointer<_GList>, Pointer<Void>) listAppend;
  late final void Function(Pointer<_GList>) listFree;
  late final void Function(Pointer<Void>) free;
  late final void Function(Pointer<_GError>) errorFree;
  late final void Function(Pointer<Void>) objectUnref;

  /// The file type GLib guesses from [fileName] alone. Free it with [free].
  Pointer<Uint8> guessType(String fileName) {
    final name = _toC(fileName);
    try {
      return contentTypeGuess(name, nullptr, 0, nullptr);
    } finally {
      Libc.instance.free(name);
    }
  }

  /// Unrefs every app in [list] and frees the list.
  void freeApps(Pointer<_GList> list) {
    for (var node = list; node != nullptr; node = node.ref.next) {
      objectUnref(node.ref.data);
    }
    listFree(list);
  }

  /// Takes GLib's error out of [errorOut] and frees it.
  String takeError(Pointer<Pointer<_GError>> errorOut) {
    final error = errorOut.value;
    if (error == nullptr) {
      return 'unknown error';
    }
    final message = _fromC(error.ref.message) ?? 'unknown error';
    errorFree(error);
    return message;
  }
}

List<List<Object?>> _listApps(String fileName) {
  final gio = _Gio();
  final type = gio.guessType(fileName);
  try {
    final fallback = gio.defaultForType(type, 0);
    final defaultId = fallback == nullptr ? null : _fromC(gio.getId(fallback));
    if (fallback != nullptr) {
      gio.objectUnref(fallback);
    }
    final list = gio.allForType(type);
    try {
      final apps = <List<Object?>>[];
      for (var node = list; node != nullptr; node = node.ref.next) {
        final id = _fromC(gio.getId(node.ref.data));
        final name = _fromC(gio.getName(node.ref.data));
        if (id != null && name != null && !apps.any((a) => a[0] == id)) {
          apps.add([id, name, id == defaultId]);
        }
      }
      apps.sort((a, b) => (a[2]! as bool) == (b[2]! as bool) ? 0 : ((a[2]! as bool) ? -1 : 1));
      return apps;
    } finally {
      gio.freeApps(list);
    }
  } finally {
    gio.free(type.cast());
  }
}

/// Returns null on success, or GLib's error message.
String? _launch(String path, String? appId) {
  final gio = _Gio();
  final libc = Libc.instance;
  final cPath = _toC(path);
  final errorOut = libc.malloc(sizeOf<Pointer<_GError>>()).cast<Pointer<_GError>>();
  errorOut.value = nullptr;
  try {
    if (appId == null) {
      final uri = gio.filenameToUri(cPath, nullptr, errorOut);
      if (uri == nullptr) {
        return gio.takeError(errorOut);
      }
      try {
        return gio.launchDefaultForUri(uri, nullptr, errorOut) != 0 ? null : gio.takeError(errorOut);
      } finally {
        gio.free(uri.cast());
      }
    }
    final type = gio.guessType(path.substring(path.lastIndexOf('/') + 1));
    final list = gio.allForType(type);
    gio.free(type.cast());
    try {
      for (var node = list; node != nullptr; node = node.ref.next) {
        if (_fromC(gio.getId(node.ref.data)) != appId) {
          continue;
        }
        final file = gio.fileNewForPath(cPath);
        final files = gio.listAppend(nullptr, file);
        try {
          return gio.launch(node.ref.data, files, nullptr, errorOut) != 0 ? null : gio.takeError(errorOut);
        } finally {
          gio
            ..listFree(files)
            ..objectUnref(file);
        }
      }
      return 'that app is no longer installed';
    } finally {
      gio.freeApps(list);
    }
  } finally {
    libc
      ..free(cPath)
      ..free(errorOut);
  }
}

Pointer<Uint8> _toC(String text) {
  final bytes = utf8.encode(text);
  final pointer = Libc.instance.malloc(bytes.length + 1);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  pointer[bytes.length] = 0;
  return pointer;
}

String? _fromC(Pointer<Uint8> chars) {
  if (chars == nullptr) {
    return null;
  }
  var length = 0;
  while (chars[length] != 0) {
    length++;
  }
  return utf8.decode(chars.asTypedList(length), allowMalformed: true);
}

/// Whether [path] is inside one of [folders] (each given without a trailing
/// slash), and not merely a name that starts the same way.
bool isInFolder(String path, List<String> folders) => folders.any((f) => path.startsWith('$f/'));
