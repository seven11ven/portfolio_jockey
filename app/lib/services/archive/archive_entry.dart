import 'dart:typed_data';

/// One file to write into an archive. Its content is read only when the
/// writer gets to it, chunk by chunk, so nothing is held in memory whole.
final class ArchiveEntry {
  const ArchiveEntry({required this.path, required this.size, required this.modified, required this.open});

  /// The path inside the archive, with `/` between folders.
  final String path;

  /// The exact number of bytes [open] delivers. A tar header records it
  /// before the content, so a different count fails the export.
  final int size;

  final DateTime modified;

  /// Starts reading the content.
  final Stream<List<int>> Function() open;
}

/// The content delivered a different number of bytes than [ArchiveEntry.size].
final class EntrySizeMismatch implements Exception {
  const EntrySizeMismatch(this.path, this.expected, this.actual);

  final String path;
  final int expected;
  final int actual;

  @override
  String toString() => '$path: expected $expected bytes, got $actual';
}

/// CRC-32 (IEEE 802.3), as ZIP needs it.
final class Crc32 {
  static final Uint32List _table = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  int _crc = 0xFFFFFFFF;

  void add(List<int> bytes) {
    var c = _crc;
    for (final b in bytes) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  int get value => _crc ^ 0xFFFFFFFF;
}
