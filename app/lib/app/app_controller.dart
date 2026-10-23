import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/export_service.dart';
import 'package:portfolio_jockey/services/file_picker.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';
import 'package:portfolio_jockey/services/native/gio_trash.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/services/sandbox.dart';
import 'package:portfolio_jockey/services/storage_move.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/ids.dart';
import 'package:portfolio_jockey/vault/inbox.dart';
import 'package:portfolio_jockey/vault/journal.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/vault.dart';

enum AppStage { loading, setup, locked, unlocked }

/// The app's top-level state: whether a vault exists, and whether it's
/// unlocked. Locking wipes the master key and drops every decrypted value.
class AppController extends ChangeNotifier {
  AppController({
    required this.settingsStore,
    this.filePicker = const SystemFilePicker(),
    this.trasher = const GioTrash(),
    AppLauncher launcher = const GioAppLauncher(),
    PrivateFolders? privateFolders,
    PrivateFolders? editFolders,
    bool? sandboxed,
    this.hostPathOf,
    this.kdf,
    Duration editSettle = const Duration(seconds: 1),
  }) : sandboxed = sandboxed ?? runningInFlatpak(),
       edits = EditSessions(
         folders: privateFolders ?? PrivateFolders.standard(),
         editFolders: editFolders ?? privateFolders ?? PrivateFolders.forEditing(sandboxed: sandboxed),
         launcher: launcher,
         settle: editSettle,
       );

  final SettingsStore settingsStore;
  final FilePicker filePicker;

  /// Where originals go when the user moves them to the Trash.
  final Trasher trasher;

  /// Whether the app runs inside a Flatpak. Then no `~/Documents` paths are
  /// suggested: storage defaults to the app's own data folder, and exports
  /// need a location chosen through the desktop's save dialog first.
  final bool sandboxed;

  /// Reads the real path behind a document portal path (tests use a fake;
  /// null uses the real one).
  final String? Function(String path)? hostPathOf;

  /// "Edit in another app", and the memory-only copies media plays from.
  final EditSessions edits;

  /// Argon2id settings for new vaults. Null means libsodium MODERATE; tests
  /// pass smaller ones.
  final KdfParams? kdf;

  AppStage _stage = AppStage.loading;
  AppStage get stage => _stage;

  String? _storagePath;
  String? get storagePath => _storagePath;

  AppSettings _settings = const AppSettings();

  ThemeMode get themeMode => switch (_settings.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  PjAccent get accent => PjAccent.named(_settings.accent);

  /// Whether a passphrase shown with the eye button may be copied (Settings).
  bool get allowPassphraseCopy => _settings.allowPassphraseCopy;

  Future<void> setAllowPassphraseCopy(bool allow) async {
    _settings = _settings.copyWith(allowPassphraseCopy: allow);
    notifyListeners();
    await settingsStore.save(_settings);
  }

  /// Saves the colour scheme. It's a preference, not project data, so it
  /// applies at once without a confirmation.
  Future<void> setAppearance({ThemeMode? mode, PjAccent? accent}) async {
    _settings = _settings.copyWith(themeMode: mode?.name, accent: accent?.name);
    notifyListeners();
    await settingsStore.save(_settings);
  }

  ProjectService? _projects;

  /// The unlocked vault's projects. Only valid while [stage] is unlocked.
  ProjectService get projects => _projects ?? (throw StateError('The vault is locked'));

  /// Whether [service] can still read: false once its vault was locked, even
  /// if the vault was unlocked again since. A read that fails then was cut off
  /// by the lock and needs no error message.
  bool isCurrent(ProjectService service) => _projects != null && !service.vault.isLocked;

  /// Export and import for the unlocked vault. Uses the same Argon2id
  /// settings as new vaults ([kdf]), so tests stay fast.
  ExportService get exports => ExportService(projects, kdf: kdf);

  final UnlockBackoff backoff = UnlockBackoff();

  Future<void> start() async {
    // On opening: no media copy should outlive the app. Edit copies stay
    // until unlock, which offers to save or discard them.
    await edits.wipeMediaCopies();
    final settings = await settingsStore.load();
    _settings = settings;
    _storagePath = settings.storagePath;
    final path = _storagePath;
    _stage = path != null && await Vault.exists(Directory(path)) ? AppStage.locked : AppStage.setup;
    notifyListeners();
  }

  /// Creates the vault and remembers its location. The first-run screen is
  /// this action's confirmation.
  Future<void> createVault(String path, String passphrase) async {
    final root = Directory(path);
    await root.create(recursive: true);
    final vault = await Vault.create(root, passphrase, kdf: kdf);
    _settings = _settings.copyWith(storagePath: path);
    await settingsStore.save(_settings);
    _storagePath = path;
    _open(vault);
  }

  /// Called when the window is about to close. False while a file is being
  /// edited (the user decides first); otherwise clears the temporary files
  /// and returns true.
  Future<bool> prepareToExit() async {
    if (edits.active != null) {
      return false;
    }
    try {
      await edits.clearTemporaryFiles();
    } on Object catch (e) {
      debugPrint("Couldn't clear the temporary files on exit: $e");
    }
    return true;
  }

  /// Moves the vault to [move]'s target: copies and checks everything, saves
  /// the new location, switches the open vault to it, then removes the old
  /// folder. Refused while a file is being edited. If the copy fails, the old
  /// location stays in use. Returns false if the old folder couldn't be
  /// removed (the move itself still succeeded).
  Future<bool> moveStorage(StorageMove move, {void Function(MoveProgress progress)? onProgress}) async {
    final current = _projects;
    if (current == null || edits.active != null) {
      throw StateError('Finish editing before moving the storage location');
    }
    // Listed before copying (and copied along), so a move cut off by a crash
    // is tidied up at the next unlock, whichever folder is in use then.
    final journalId = newId();
    await current.journalPut(MoveStarted(journalId, source: move.source.absolute.path, target: move.target.absolute.path));
    try {
      await move.copyAndVerify(onProgress: onProgress);
    } on Object {
      await current.journalRemove(journalId);
      rethrow;
    }
    _settings = _settings.copyWith(storagePath: move.target.path);
    await settingsStore.save(_settings);
    _storagePath = move.target.path;
    final moved = ProjectService(current.vault.relocatedTo(move.target), trasher: trasher, hostPathOf: hostPathOf);
    _projects = moved;
    edits.journal = moved;
    notifyListeners();
    try {
      await move.removeSource();
      return true;
    } on FileSystemException {
      return false;
    } finally {
      await moved.journalRemove(journalId);
    }
  }

  /// Re-wraps the master key with [replacement]. Files aren't re-encrypted,
  /// and the open vault stays open. Throws [WrongPassphrase] if [current] is
  /// wrong.
  Future<void> changePassphrase(String current, String replacement) async {
    final path = _storagePath;
    if (path == null) {
      throw StateError('No vault location');
    }
    await Vault.changePassphrase(Directory(path), current, replacement, kdf: kdf);
  }

  /// Throws [WrongPassphrase] (and records the failure) if it doesn't unlock.
  Future<void> unlock(String passphrase) async {
    final path = _storagePath;
    if (path == null) {
      throw StateError('No vault location');
    }
    if (backoff.remaining > Duration.zero) {
      throw StateError('Wait before trying again');
    }
    try {
      final vault = await Vault.unlock(Directory(path), passphrase);
      backoff.reset();
      _open(vault);
    } on WrongPassphrase {
      backoff.recordFailure();
      rethrow;
    }
  }

  /// False while a file is being edited: the edit must be saved or discarded
  /// first, so locking never leaves a readable copy behind.
  bool get canLock => edits.active == null;

  void lock() {
    if (!canLock) {
      throw StateError('Save or discard the edit before locking');
    }
    unawaited(edits.wipeMediaCopies());
    _projects?.vault.lock();
    _projects = null;
    edits.journal = null;
    _inbox = const [];
    _stage = AppStage.locked;
    notifyListeners();
  }

  void _open(UnlockedVault vault) {
    final projects = ProjectService(vault, trasher: trasher, hostPathOf: hostPathOf);
    _projects = projects;
    edits.journal = projects;
    _stage = AppStage.unlocked;
    notifyListeners();
    unawaited(_afterUnlock(projects));
  }

  List<InboxNotice> _inbox = const [];

  /// The inbox's notices, newest first, while unlocked.
  List<InboxNotice> get inbox => _inbox.reversed.toList();

  /// How many notices haven't been read yet (the number on the inbox icon).
  int get unreadCount => _inbox.where((n) => !n.read).length;

  /// Marks every notice as read (opening the inbox does this).
  Future<void> markAllRead() => _changeInbox((notices) => [for (final n in notices) n.asRead()]);

  /// Dismisses the notice [id].
  Future<void> dismiss(String id) => _changeInbox((notices) => [...notices.where((n) => n.id != id)]);

  /// Dismisses every notice.
  Future<void> clearInbox() => _changeInbox((_) => const []);

  Future<void> _changeInbox(List<InboxNotice> Function(List<InboxNotice> notices) change) async {
    final projects = _projects;
    if (projects == null) {
      return;
    }
    final changed = await projects.changeInbox(change);
    if (identical(_projects, projects)) {
      _inbox = changed;
      notifyListeners();
    }
  }

  /// Finds unfinished edits, then tidies up what the journal still lists
  /// (exports, imports, a storage move, an edit whose copy is gone), then
  /// removes leftovers inside projects. What was tidied up goes to the inbox.
  Future<void> _afterUnlock(ProjectService projects) async {
    final found = <({String title, String text})>[];
    try {
      await edits.findLeftovers();
      final open = {for (final s in edits.leftovers) s.journalId};
      found.addAll(await projects.recoverJournal(openEditIds: open));
      await projects.cleanUp();
    } on Object catch (e) {
      found.add((title: "Couldn't check for unfinished work", text: "Couldn't check for work left unfinished last time: $e"));
    }
    try {
      final now = DateTime.now();
      final inbox = found.isEmpty
          ? await projects.inbox()
          : await projects.changeInbox((notices) => [
              ...notices,
              for (final f in found) InboxNotice(id: newId(), title: f.title, text: f.text, at: now),
            ]);
      if (identical(_projects, projects)) {
        _inbox = inbox;
        notifyListeners();
      }
    } on Object catch (e) {
      debugPrint("Couldn't read the inbox: $e");
    }
  }

  @override
  void dispose() {
    edits.dispose();
    _projects?.vault.lock();
    super.dispose();
  }
}

/// Slows down passphrase guessing: after each failed unlock, the next try
/// waits 1, 2, 4, 8… seconds, up to 30. Kept in memory only.
class UnlockBackoff {
  UnlockBackoff({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int _failures = 0;
  DateTime? _nextTry;

  int get failures => _failures;

  static Duration delayAfter(int failures) {
    if (failures <= 0) {
      return Duration.zero;
    }
    final seconds = 1 << (failures - 1).clamp(0, 5);
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }

  /// How long until the next try is allowed.
  Duration get remaining {
    final next = _nextTry;
    if (next == null) {
      return Duration.zero;
    }
    final left = next.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  void recordFailure() {
    _failures++;
    _nextTry = _clock().add(delayAfter(_failures));
  }

  void reset() {
    _failures = 0;
    _nextTry = null;
  }
}
