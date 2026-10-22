import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/sodium.dart';

final RegExp _idPattern = RegExp(r'^[0-9a-f]{32}$');

/// A new random 128-bit ID, as 32 lowercase hex characters. Used for project
/// folders and file names, so they reveal nothing about the contents.
String newId() => toHex(Sodium.instance.randomBytes(16));

bool isValidId(String id) => _idPattern.hasMatch(id);

/// Rejects anything but a vault ID before it's used in a path, so a damaged
/// index can never point outside the storage location.
void checkId(String id) {
  if (!isValidId(id)) {
    throw ArgumentError.value(id, 'id', 'is not a vault ID');
  }
}

String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('Odd number of hex digits', hex);
  }
  return Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}
