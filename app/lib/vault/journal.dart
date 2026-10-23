import 'dart:typed_data';

import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/sealed_json.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

/// One piece of work that touches the disk in several steps and must be
/// tidied up if the app stops halfway (a crash or a power cut). It holds
/// paths and IDs only, never file contents; the journal is encrypted because
/// those can be private.
sealed class JournalEntry {
  const JournalEntry(this.id);

  /// Which entry this is, so it can be removed when the work finishes.
  final String id;

  Map<String, Object?> toJson();

  static JournalEntry fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    return switch (json['kind']) {
      'export' => ExportStarted(id, tempPath: json['temp']! as String),
      'import' => ImportStarted(id, projectIds: [for (final p in json['projects']! as List<Object?>) p! as String]),
      'move' => MoveStarted(id, source: json['source']! as String, target: json['target']! as String),
      'edit' => EditStarted(id, projectName: json['project']! as String, fileName: json['file']! as String),
      final kind => throw VaultFormatError('Unknown journal entry "$kind"'),
    };
  }
}

/// An export is being written to [tempPath], next to where the user saved it.
/// If it's still listed, the file there is unfinished (and for an unlocked
/// export, readable), so it's overwritten with zeros and deleted.
final class ExportStarted extends JournalEntry {
  const ExportStarted(super.id, {required this.tempPath});

  final String tempPath;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'export', 'temp': tempPath};
}

/// An import is creating [projectIds]. If it's still listed, the import
/// didn't finish, so those projects are deleted: imports are all or nothing.
final class ImportStarted extends JournalEntry {
  const ImportStarted(super.id, {required this.projectIds});

  final List<String> projectIds;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'import', 'projects': projectIds};
}

/// The vault is being moved from [source] to [target]. If it's still listed,
/// whichever of the two isn't in use is a leftover copy.
final class MoveStarted extends JournalEntry {
  const MoveStarted(super.id, {required this.source, required this.target});

  final String source;
  final String target;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'move', 'source': source, 'target': target};
}

/// A file is open in another app. If it's still listed and its readable copy
/// is gone (inside a Flatpak, the sandbox's memory folder doesn't outlive the
/// app), the user is told that the edit's changes weren't saved.
final class EditStarted extends JournalEntry {
  const EditStarted(super.id, {required this.projectName, required this.fileName});

  final String projectName;
  final String fileName;

  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': 'edit', 'project': projectName, 'file': fileName};
}

// journal.enc: a sealed JSON file (sealed_json.dart), magic "PJJN", label
// "journal".
Uint8List encryptJournal(List<JournalEntry> entries, {required SecureBuffer masterKey}) =>
    sealJson([for (final e in entries) e.toJson()], magic: 'PJJN', label: 'journal', masterKey: masterKey);

/// Throws [VaultFormatError] if it isn't a journal, and [TamperedData] if it
/// was changed.
List<JournalEntry> decryptJournal(Uint8List bytes, {required SecureBuffer masterKey}) {
  final json = openSealedJson(bytes, magic: 'PJJN', label: 'journal', masterKey: masterKey);
  try {
    return [for (final e in json! as List<Object?>) JournalEntry.fromJson((e! as Map).cast<String, Object?>())];
  } on VaultFormatError {
    rethrow;
  } on Object catch (e) {
    throw VaultFormatError('Journal is not valid: $e');
  }
}
