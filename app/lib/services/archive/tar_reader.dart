import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const int _block = 512;

/// The content inside a locked export isn't a tar this app wrote.
final class BadArchive implements Exception {
  const BadArchive(this.message);

  final String message;

  @override
  String toString() => 'The export is damaged: $message';
}

/// One file in the archive. Read its content with [TarReader.content] or
/// [TarReader.readAll] before asking for the next one.
final class TarEntry {
  const TarEntry(this.path, this.size);

  final String path;
  final int size;
}

/// Reads the tar inside a locked export, as written by `tarStream`.
///
/// Deliberately strict, because only this app's own archives are read:
/// regular files and PAX `path`/`size` records only (no links, folders or
/// devices), checksums verified, and every path must pass [isSafePath].
final class TarReader {
  TarReader(Stream<List<int>> input) : _input = StreamIterator(input);

  final StreamIterator<List<int>> _input;
  Uint8List _buffer = Uint8List(0);
  int _at = 0;
  int _pending = 0; // content (plus padding) of the current entry not yet read

  /// The next file, or null at the end of the archive.
  Future<TarEntry?> next() async {
    if (_pending > 0) {
      throw StateError("The previous entry's content wasn't read");
    }
    String? paxPath;
    int? paxSize;
    while (true) {
      final header = await _read(_block);
      if (header.every((b) => b == 0)) {
        return null; // end-of-archive marker
      }
      _checkChecksum(header);
      final type = header[156];
      final headerSize = _octal(header, 124, 12);
      if (type == 0x78) {
        // 'x': PAX extended header for the next entry.
        final size = headerSize;
        if (size > 64 * 1024) {
          throw const BadArchive('extended header too large');
        }
        final records = await _read(size);
        await _read((_block - size % _block) % _block);
        (paxPath, paxSize) = _parsePax(records);
        continue;
      }
      final size = paxSize ?? headerSize;
      if (type != 0x30 && type != 0) {
        throw BadArchive('unsupported entry type ${String.fromCharCode(type)}');
      }
      final path = paxPath ?? _text(header, 0, 100);
      if (!isSafePath(path)) {
        throw BadArchive('unsafe path "$path"');
      }
      _pending = size + (_block - size % _block) % _block;
      return TarEntry(path, size);
    }
  }

  /// The current entry's content, chunk by chunk.
  Stream<Uint8List> content(TarEntry entry) async* {
    var left = entry.size;
    while (left > 0) {
      final chunk = await _readUpTo(left < 64 * 1024 ? left : 64 * 1024);
      left -= chunk.length;
      _pending -= chunk.length;
      yield chunk;
    }
    await _read(_pending);
    _pending = 0;
  }

  /// The current entry's whole content, which must be at most [maxBytes].
  Future<Uint8List> readAll(TarEntry entry, {required int maxBytes}) async {
    if (entry.size > maxBytes) {
      throw BadArchive('${entry.path} is too large');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in content(entry)) {
      out.add(chunk);
    }
    return out.takeBytes();
  }

  /// Reads the input to its end after [next] returned null. The input must
  /// hold only zero padding there. For a locked export this also lets the
  /// decryption reach its final chunk, which proves nothing was cut off.
  Future<void> finish() async {
    void checkZero(Uint8List bytes) {
      if (bytes.any((b) => b != 0)) {
        throw const BadArchive('data after the end of the archive');
      }
    }

    checkZero(Uint8List.sublistView(_buffer, _at));
    _at = _buffer.length;
    while (await _input.moveNext()) {
      final chunk = _input.current;
      checkZero(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    }
  }

  Future<void> cancel() => _input.cancel();

  /// Relative paths of plain ASCII segments: no `..`, `.`, empty segments,
  /// leading `/` or backslashes.
  static bool isSafePath(String path) {
    if (path.isEmpty || path.length > 255 || path.startsWith('/') || path.contains(r'\')) {
      return false;
    }
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..' || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(segment)) {
        return false;
      }
    }
    return true;
  }

  Future<Uint8List> _read(int count) async {
    final out = Uint8List(count);
    var filled = 0;
    while (filled < count) {
      final chunk = await _readUpTo(count - filled);
      out.setAll(filled, chunk);
      filled += chunk.length;
    }
    return out;
  }

  Future<Uint8List> _readUpTo(int max) async {
    while (_at >= _buffer.length) {
      if (!await _input.moveNext()) {
        throw const BadArchive('the archive ends too early');
      }
      final next = _input.current;
      _buffer = next is Uint8List ? next : Uint8List.fromList(next);
      _at = 0;
    }
    final count = _buffer.length - _at < max ? _buffer.length - _at : max;
    final chunk = Uint8List.sublistView(_buffer, _at, _at + count);
    _at += count;
    return chunk;
  }

  static void _checkChecksum(Uint8List header) {
    final stored = _octal(header, 148, 8);
    var sum = 0;
    for (var i = 0; i < _block; i++) {
      sum += i >= 148 && i < 156 ? 0x20 : header[i];
    }
    if (sum != stored) {
      throw const BadArchive('header checksum mismatch');
    }
  }

  static int _octal(Uint8List header, int offset, int length) {
    final text = _text(header, offset, length).trim();
    final value = text.isEmpty ? 0 : int.tryParse(text, radix: 8);
    if (value == null || value < 0) {
      throw const BadArchive('invalid number in header');
    }
    return value;
  }

  static String _text(Uint8List header, int offset, int length) {
    var end = offset;
    while (end < offset + length && header[end] != 0) {
      end++;
    }
    return utf8.decode(header.sublist(offset, end), allowMalformed: true);
  }

  static (String?, int?) _parsePax(Uint8List records) {
    String? path;
    int? size;
    var at = 0;
    while (at < records.length) {
      final space = records.indexOf(0x20, at);
      final length = space < 0 ? null : int.tryParse(ascii.decode(records.sublist(at, space), allowInvalid: true));
      if (length == null || length <= 0 || at + length > records.length) {
        throw const BadArchive('invalid extended header');
      }
      final record = utf8.decode(records.sublist(space + 1, at + length - 1), allowMalformed: true);
      final equals = record.indexOf('=');
      if (equals > 0) {
        final key = record.substring(0, equals);
        final value = record.substring(equals + 1);
        if (key == 'path') {
          path = value;
        } else if (key == 'size') {
          size = int.tryParse(value);
          if (size == null || size < 0) {
            throw const BadArchive('invalid size in extended header');
          }
        }
      }
      at += length;
    }
    return (path, size);
  }
}
