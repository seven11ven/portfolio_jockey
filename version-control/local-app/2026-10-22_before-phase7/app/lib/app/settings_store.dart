import 'dart:convert';
import 'dart:io';

import 'package:portfolio_jockey/vault/atomic_write.dart';

/// App settings that aren't secret. For now, only where projects are stored.
final class AppSettings {
  const AppSettings({this.storagePath});

  factory AppSettings.fromJson(Map<String, Object?> json) =>
      AppSettings(storagePath: json['storagePath'] is String ? json['storagePath']! as String : null);

  final String? storagePath;

  Map<String, Object?> toJson() => {'storagePath': storagePath};
}

/// Reads and writes `settings.json` in the app's config folder
/// (`$XDG_CONFIG_HOME/portfolio_jockey/`, usually `~/.config/portfolio_jockey/`).
final class SettingsStore {
  SettingsStore(this.file);

  factory SettingsStore.standard() {
    final env = Platform.environment;
    final configHome = env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return SettingsStore(File('$configHome/portfolio_jockey/settings.json'));
  }

  final File file;

  /// The settings, or defaults if there are none yet or the file is unreadable.
  Future<AppSettings> load() async {
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? AppSettings.fromJson(json) : const AppSettings();
    } on FileSystemException {
      return const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await file.parent.create(recursive: true);
    await writeBytesAtomically(file, utf8.encode(const JsonEncoder.withIndent('  ').convert(settings.toJson())));
  }
}

/// The storage location suggested on first run: `~/Documents/Portfolio Jockey`.
String defaultStoragePath() => '${Platform.environment['HOME']}/Documents/Portfolio Jockey';
