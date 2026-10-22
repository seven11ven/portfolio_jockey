import 'dart:convert';
import 'dart:io';

import 'package:portfolio_jockey/vault/atomic_write.dart';

/// App settings that aren't secret: where projects are stored, and how the
/// app looks.
final class AppSettings {
  const AppSettings({this.storagePath, this.themeMode = 'system', this.accent = 'indigo'});

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    storagePath: json['storagePath'] is String ? json['storagePath']! as String : null,
    themeMode: switch (json['themeMode']) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    },
    accent: json['accent'] is String ? json['accent']! as String : 'indigo',
  );

  final String? storagePath;

  /// "system", "light" or "dark".
  final String themeMode;

  /// The accent colour's name (see `PjAccent`).
  final String accent;

  AppSettings copyWith({String? storagePath, String? themeMode, String? accent}) =>
      AppSettings(storagePath: storagePath ?? this.storagePath, themeMode: themeMode ?? this.themeMode, accent: accent ?? this.accent);

  Map<String, Object?> toJson() => {'storagePath': storagePath, 'themeMode': themeMode, 'accent': accent};
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
