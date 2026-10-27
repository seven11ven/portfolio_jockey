import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/services/file_picker.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/kdf.dart';
import 'package:portfolio_jockey/vault/vault.dart';

enum AppStage { loading, setup, locked, unlocked }

/// The app's top-level state: whether a vault exists, and whether it's
/// unlocked. Locking wipes the master key and drops every decrypted value.
class AppController extends ChangeNotifier {
  AppController({required this.settingsStore, this.filePicker = const SystemFilePicker(), this.kdf});

  final SettingsStore settingsStore;
  final FilePicker filePicker;

  /// Argon2id settings for new vaults. Null means libsodium MODERATE; tests
  /// pass smaller ones.
  final KdfParams? kdf;

  AppStage _stage = AppStage.loading;
  AppStage get stage => _stage;

  String? _storagePath;
  String? get storagePath => _storagePath;

  ProjectService? _projects;

  /// The unlocked vault's projects. Only valid while [stage] is unlocked.
  ProjectService get projects => _projects ?? (throw StateError('The vault is locked'));

  final UnlockBackoff backoff = UnlockBackoff();

  Future<void> start() async {
    final settings = await settingsStore.load();
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
    await settingsStore.save(AppSettings(storagePath: path));
    _storagePath = path;
    _open(vault);
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

  void lock() {
    _projects?.vault.lock();
    _projects = null;
    _stage = AppStage.locked;
    notifyListeners();
  }

  void _open(UnlockedVault vault) {
    _projects = ProjectService(vault);
    _stage = AppStage.unlocked;
    notifyListeners();
  }

  @override
  void dispose() {
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
