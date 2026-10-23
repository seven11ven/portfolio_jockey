import 'dart:convert';
import 'dart:io';

import 'package:portfolio_jockey/vault/atomic_write.dart';

/// App settings that aren't secret: where projects are stored, and how the
/// app looks.
final class AppSettings {
  const AppSettings({this.storagePath, this.themeMode = 'system', this.accent = 'indigo', this.allowPassphraseCopy = true, this.hardwareDecoding = true});

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    storagePath: json['storagePath'] is String ? json['storagePath']! as String : null,
    themeMode: switch (json['themeMode']) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    },
    accent: json['accent'] is String ? json['accent']! as String : 'indigo',
    allowPassphraseCopy: json['allowPassphraseCopy'] is! bool || json['allowPassphraseCopy']! as bool,
    hardwareDecoding: json['hardwareDecoding'] is! bool || json['hardwareDecoding']! as bool,
  );

  final String? storagePath;

  /// "system", "light" or "dark".
  final String themeMode;

  /// The accent colour's name (see `PjAccent`).
  final String accent;

  /// Whether a passphrase shown with the eye button can be copied. On by
  /// default: the user's choice (PM decision, 2026-10-22).
  final bool allowPassphraseCopy;

  /// Whether video previews may decode on the graphics card. On by default
  /// (PM decision, 2026-10-23); mpv falls back to the processor by itself.
  final bool hardwareDecoding;

  AppSettings copyWith({String? storagePath, String? themeMode, String? accent, bool? allowPassphraseCopy, bool? hardwareDecoding}) => AppSettings(

    storagePath: storagePath ?? this.storagePath,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    allowPassphraseCopy: allowPassphraseCopy ?? this.allowPassphraseCopy,
    hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
  );

  Map<String, Object?> toJson() => {
    'storagePath': storagePath,
    'themeMode': themeMode,
    'accent': accent,
    'allowPassphraseCopy': allowPassphraseCopy,
    'hardwareDecoding': hardwareDecoding,
  };
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

/// The storage location suggested on first run: `~/Documents/Portfolio Jockey`,
/// or inside a Flatpak the app's own data folder
/// (`~/.var/app/<app ID>/data/Portfolio Jockey`, which Flatpak sets as
/// `XDG_DATA_HOME`), because the sandbox can't write to `~/Documents`.
String defaultStoragePath({bool sandboxed = false}) {
  final env = Platform.environment;
  if (sandboxed) {
    return '${env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share'}/Portfolio Jockey';
  }
  return '${env['HOME']}/Documents/Portfolio Jockey';
}
