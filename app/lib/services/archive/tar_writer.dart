import 'dart:convert';
import 'dart:typed_data';

import 'package:portfolio_jockey/services/archive/archive_entry.dart';

const int _block = 512;

/// A POSIX tar archive of [entries], produced as it's read: each file's
/// content passes straight through. Names that are long or not ASCII, and
/// files of 8 GiB or more, get a PAX extended header, which every modern tar
/// reads. Throws [EntrySizeMismatch] if an entry's content isn't the size it
/// declared.
Stream<List<int>> tarStream(Stream<ArchiveEntry> entries) async* {
  await for (final entry in entries) {
    final name = utf8.encode(entry.path);
    final needsPax = name.length > 100 || name.any((b) => b > 0x7E || b < 0x20) || entry.size >= 0x200000000;
    if (needsPax) {
      final records = utf8.encode('${_paxRecord('path', entry.path)}${_paxRecord('size', '${entry.size}')}');
      yield _header(name: 'PaxHeaders/${_asciiFallback(entry.path)}', size: records.length, modified: entry.modified, type: 0x78); // 'x'
      yield records;
      yield Uint8List(_padding(records.length));
    }
    yield _header(name: needsPax ? _asciiFallback(entry.path) : entry.path, size: needsPax && entry.size >= 0x200000000 ? 0 : entry.size, modified: entry.modified, type: 0x30); // '0'
    var written = 0;
    await for (final chunk in entry.open()) {
      written += chunk.length;
      if (written > entry.size) {
        throw EntrySizeMismatch(entry.path, entry.size, written);
      }
      yield chunk;
    }
    if (written != entry.size) {
      throw EntrySizeMismatch(entry.path, entry.size, written);
    }
    yield Uint8List(_padding(entry.size));
  }
  yield Uint8List(_block * 2); // end of archive
}

int _padding(int size) => (_block - size % _block) % _block;

/// A PAX record: `<length> <key>=<value>\n`, where the length counts itself.
String _paxRecord(String key, String value) {
  final body = ' $key=$value\n';
  final bodyLength = utf8.encode(body).length;
  var length = bodyLength + 1;
  while ('$length'.length + bodyLength != length) {
    length++;
  }
  return '$length$body';
}

/// The name a tar without PAX support would show: ASCII only, at most 100
/// bytes, keeping the end (usually the file name and extension).
String _asciiFallback(String path) {
  final ascii = path.runes.map((r) => r >= 0x20 && r <= 0x7E ? String.fromCharCode(r) : '_').join();
  return ascii.length <= 100 ? ascii : ascii.substring(ascii.length - 100);
}

Uint8List _header({required String name, required int size, required DateTime modified, required int type}) {
  final header = Uint8List(_block);
  void text(int offset, int length, String value) {
    final bytes = utf8.encode(value);
    header.setRange(offset, offset + (bytes.length < length ? bytes.length : length), bytes);
  }

  void octal(int offset, int length, int value) => text(offset, length, '${value.toRadixString(8).padLeft(length - 1, '0')}\u0000');

  text(0, 100, name);
  octal(100, 8, 0x1A4); // mode 0644
  octal(108, 8, 0); // uid
  octal(116, 8, 0); // gid
  octal(124, 12, size);
  octal(136, 12, modified.millisecondsSinceEpoch ~/ 1000);
  header[156] = type;
  text(257, 6, 'ustar\u0000');
  text(263, 2, '00');
  // The checksum is computed with its own field filled with spaces.
  header.fillRange(148, 156, 0x20);
  final sum = header.fold<int>(0, (a, b) => a + b);
  text(148, 8, '${sum.toRadixString(8).padLeft(6, '0')}\u0000 ');
  return header;
}
