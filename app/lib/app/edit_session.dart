import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

/// Which project file an edit belongs to. Saved as `session.json` next to the
/// readable copy, so an edit left by a crash can be found at the next unlock.
final class EditInfo {
  const EditInfo({required this.projectId, required this.projectName, required this.fileId, required this.fileName, required this.startedAt, this.appName});

  factory EditInfo.fromJson(Map<String, Object?> json) => EditInfo(
    projectId: json['projectId']! as String,
    projectName: json['projectName']! as String,
    fileId: json['fileId']! as String,
    fileName: json['fileName']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    appName: json['appName'] as String?,
  );

  final String projectId;
  final String projectName;
  final String fileId;
  final String fileName;
  final DateTime startedAt;

  /// The app it was opened in, or null for the desktop's chooser.
  final String? appName;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'projectName': projectName,
    'fileId': fileId,
    'fileName': fileName,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'appName': appName,
  };
}

/// One readable copy being edited, in its private memory-only folder:
/// `edit-<random>/session.json` and `edit-<random>/file/<name>`. The other
/// app only gets the `file/` folder's path.
final class EditSession {
  const EditSession(this.folder, this.info);

  final Directory folder;
  final EditInfo info;

  File get copy => File('${folder.path}/file/${info.fileName}');

  /// When the copy was last saved by the other app, or null if it's gone.
  Future<DateTime?> lastChanged() async => await copy.exists() ? copy.lastModified() : null;
}

/// Why an edited copy can't be saved yet. Nothing is written in either case.
enum EditNotReadyReason {
  /// The copy changed during the check: the other app is still saving it.
  stillWriting,

  /// The copy is empty but the project's version isn't, which usually means
  /// the other app failed partway. Saving needs the user's confirmation.
  empty,
}

/// Thrown by [EditSessions.save] when the copy isn't ready to be saved.
final class EditNotReady implements Exception {
  const EditNotReady(this.reason);

  final EditNotReadyReason reason;

  @override
  String toString() => switch (reason) {
    EditNotReadyReason.stillWriting => "The other app is still saving this file. Wait until it's done, then try again. Nothing has been changed.",
    EditNotReadyReason.empty => "The edited copy is empty. If you didn't mean to clear the file, cancel and check it in the other app.",
  };
}

/// "Edit in another app", and the readable copies audio and video play from.
///
/// Only one edit at a time. Saving re-encrypts the copy into the project;
/// saving and discarding both wipe the folder. Edits are never wiped
/// silently: one left by a crash is found by [findLeftovers] after unlocking,
/// and the user decides. Media copies (`view-*`) are wiped whenever a preview
/// closes, when the vault locks, and at unlock.
class EditSessions extends ChangeNotifier {
  EditSessions({required this.folders, required this.launcher, this.settle = const Duration(seconds: 1)});

  /// How long the copy must stay unchanged before it's saved, so a save the
  /// other app is still writing isn't encrypted half-done.
  final Duration settle;

  static const String _editPrefix = 'edit';
  static const String _viewPrefix = 'view';

  final PrivateFolders folders;
  final AppLauncher launcher;

  EditSession? _active;
  List<EditSession> _leftovers = const [];

  /// The edit in progress.
  EditSession? get active => _active;

  /// Edits found at unlock that weren't saved or discarded.
  List<EditSession> get leftovers => _leftovers;

  /// Decrypts [file] into a new private folder and opens it in [app] (or the
  /// desktop's chooser when null). Throws [NoPrivateFolder] if there's no
  /// memory-only folder; anything already written is wiped on failure.
  Future<EditSession> start({
    required ProjectService service,
    required String projectId,
    required String projectName,
    required FileEntry file,
    InstalledApp? app,
  }) async {
    if (_active != null) {
      throw StateError('Another file is being edited');
    }
    final folder = await folders.create(_editPrefix);
    final session = EditSession(
      folder,
      EditInfo(projectId: projectId, projectName: projectName, fileId: file.id, fileName: file.name, startedAt: DateTime.now(), appName: app?.name),
    );
    try {
      await Directory('${folder.path}/file').create();
      await File('${folder.path}/session.json').writeAsString(jsonEncode(session.info.toJson()), flush: true);
      await service.decryptTo(projectId, file, session.copy);
      await launcher.open(session.copy.path, appId: app?.id);
    } on Object {
      await PrivateFolders.wipe(folder);
      rethrow;
    }
    _active = session;
    notifyListeners();
    return session;
  }

  /// Whether [session]'s copy differs from the file in the project. False if
  /// the project file is gone.
  Future<bool> hasChanges(ProjectService service, EditSession session) async {
    final file = await _entry(service, session);
    if (file == null || !await session.copy.exists()) {
      return false;
    }
    return service.differsFrom(session.info.projectId, file, session.copy);
  }

  /// The project file [session] edits, or null if it was deleted meanwhile.
  Future<FileEntry?> entryFor(ProjectService service, EditSession session) => _entry(service, session);

  /// Encrypts the edited copy into the project, then wipes the folder.
  /// First waits [settle] and throws [EditNotReady] if the copy is still
  /// changing, or if it's empty while the project's version isn't (unless
  /// [allowEmpty]). If anything fails, the project's version is kept and the
  /// edit stays open.
  Future<void> save(ProjectService service, EditSession session, {bool allowEmpty = false}) async {
    final before = await session.copy.stat();
    await Future<void>.delayed(settle);
    final after = await session.copy.stat();
    if (after.type != FileSystemEntityType.file) {
      throw FileSystemException('The edited copy is gone or not a file', session.copy.path);
    }
    if (before.size != after.size || before.modified != after.modified) {
      throw const EditNotReady(EditNotReadyReason.stillWriting);
    }
    final current = await _entry(service, session);
    if (!allowEmpty && after.size == 0 && current != null && current.size > 0) {
      throw const EditNotReady(EditNotReadyReason.empty);
    }
    await service.replaceContent(session.info.projectId, session.info.fileId, session.copy);
    await _finish(session);
  }

  /// Wipes the edited copy. The project keeps its current version.
  Future<void> discard(EditSession session) => _finish(session);

  /// Looks for edits left by a crash or power cut. Call after unlocking.
  /// Folders whose session.json can't be read are wiped (they hold nothing
  /// that could be saved back), as are leftover media copies.
  Future<void> findLeftovers() async {
    await wipeMediaCopies();
    final found = <EditSession>[];
    for (final folder in await folders.existing(_editPrefix)) {
      if (folder.path == _active?.folder.path) {
        continue;
      }
      try {
        final json = jsonDecode(await File('${folder.path}/session.json').readAsString()) as Map<String, Object?>;
        found.add(EditSession(folder, EditInfo.fromJson(json)));
      } on Object {
        await PrivateFolders.wipe(folder);
      }
    }
    _leftovers = found;
    notifyListeners();
  }

  /// Makes a readable copy of [file] for the media player, in a private
  /// memory-only folder. Wipe it with [PrivateFolders.wipe] when the preview
  /// closes.
  Future<File> mediaCopy(ProjectService service, String projectId, FileEntry file) async {
    final folder = await folders.create(_viewPrefix);
    final copy = File('${folder.path}/${file.name}');
    try {
      await service.decryptTo(projectId, file, copy);
    } on Object {
      await PrivateFolders.wipe(folder);
      rethrow;
    }
    return copy;
  }

  /// Wipes every media copy (none should outlive its preview).
  Future<void> wipeMediaCopies() async {
    for (final folder in await folders.existing(_viewPrefix)) {
      await PrivateFolders.wipe(folder);
    }
  }

  Future<void> _finish(EditSession session) async {
    await PrivateFolders.wipe(session.folder);
    if (identical(_active, session) || _active?.folder.path == session.folder.path) {
      _active = null;
    }
    _leftovers = [for (final s in _leftovers) if (s.folder.path != session.folder.path) s];
    notifyListeners();
  }

  static Future<FileEntry?> _entry(ProjectService service, EditSession session) async {
    try {
      final index = await service.readProject(session.info.projectId);
      return index.files.where((f) => f.id == session.info.fileId).firstOrNull;
    } on Exception {
      return null; // The project was deleted, or can't be read.
    }
  }
}
