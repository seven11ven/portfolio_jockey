import 'dart:typed_data';

import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/sealed_json.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

/// A notice for the user, kept in the vault's inbox (`.pj/inbox.enc`, a
/// sealed JSON file, magic "PJIB") until it's dismissed. Notices name files
/// and projects, so they're encrypted like everything else.
final class InboxNotice {
  const InboxNotice({required this.id, required this.title, required this.text, required this.at, this.read = false});

  factory InboxNotice.fromJson(Map<String, Object?> json) => InboxNotice(
    id: json['id']! as String,
    title: json['title']! as String,
    text: json['text']! as String,
    at: DateTime.parse(json['at']! as String),
    read: json['read'] == true,
  );

  final String id;
  final String title;
  final String text;
  final DateTime at;
  final bool read;

  InboxNotice asRead() => InboxNotice(id: id, title: title, text: text, at: at, read: true);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'text': text, 'at': at.toUtc().toIso8601String(), 'read': read};
}

Uint8List encryptInbox(List<InboxNotice> notices, {required SecureBuffer masterKey}) =>
    sealJson([for (final n in notices) n.toJson()], magic: 'PJIB', label: 'inbox', masterKey: masterKey);

/// Throws [VaultFormatError] if it isn't an inbox, and [TamperedData] if it
/// was changed.
List<InboxNotice> decryptInbox(Uint8List bytes, {required SecureBuffer masterKey}) {
  final json = openSealedJson(bytes, magic: 'PJIB', label: 'inbox', masterKey: masterKey);
  try {
    return [for (final n in json! as List<Object?>) InboxNotice.fromJson((n! as Map).cast<String, Object?>())];
  } on Object catch (e) {
    throw VaultFormatError('The inbox is not valid: $e');
  }
}
