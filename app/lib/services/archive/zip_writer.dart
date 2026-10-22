import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:portfolio_jockey/services/archive/archive_entry.dart';

/// A ZIP archive of [entries], produced as it's read: each file's content
/// passes straight through, deflated (or stored, for formats that are already
/// compressed). Sizes and CRC-32 follow each file in a data descriptor, so
/// nothing has to be known in advance or held in memory. ZIP64 records are
/// used for files near or over 4 GB and for very large archives. Names are
/// UTF-8 (flag bit 11). Throws [EntrySizeMismatch] if an entry's content
/// isn't the size it declared.
Stream<List<int>> zipStream(Stream<ArchiveEntry> entries) async* {
  final central = <_CentralRecord>[];
  var offset = 0;
  Stream<List<int>> emit(List<int> bytes) async* {
    offset += bytes.length;
    yield bytes;
  }

  await for (final entry in entries) {
    final name = utf8.encode(entry.path);
    final deflate = !_alreadyCompressed(entry.path);
    // Deflate can grow incompressible data slightly, so leave a margin.
    final zip64 = entry.size >= 0xFF000000;
    final record = _CentralRecord(
      name: name,
      method: deflate ? 8 : 0,
      zip64: zip64,
      dosTime: _dosTime(entry.modified),
      dosDate: _dosDate(entry.modified),
      offset: offset,
    );
    yield* emit(_localHeader(record));

    final crc = Crc32();
    var read = 0;
    var compressed = 0;
    final collected = <List<int>>[];
    final encoder = deflate ? ZLibEncoder(raw: true, level: 6).startChunkedConversion(_Collect(collected)) : null;
    await for (final chunk in entry.open()) {
      read += chunk.length;
      if (read > entry.size) {
        throw EntrySizeMismatch(entry.path, entry.size, read);
      }
      crc.add(chunk);
      if (encoder == null) {
        compressed += chunk.length;
        yield* emit(chunk);
      } else {
        encoder.add(chunk);
        for (final out in collected) {
          compressed += out.length;
          yield* emit(out);
        }
        collected.clear();
      }
    }
    if (encoder != null) {
      encoder.close();
      for (final out in collected) {
        compressed += out.length;
        yield* emit(out);
      }
      collected.clear();
    }
    if (read != entry.size) {
      throw EntrySizeMismatch(entry.path, entry.size, read);
    }
    record
      ..crc = crc.value
      ..size = read
      ..compressed = compressed;
    yield* emit(_dataDescriptor(record));
    central.add(record);
  }

  final centralStart = offset;
  for (final record in central) {
    yield* emit(_centralHeader(record));
  }
  final centralSize = offset - centralStart;
  final needsZip64End = central.length >= 0xFFFF || centralStart >= 0xFFFFFFFF || centralSize >= 0xFFFFFFFF;
  if (needsZip64End) {
    final zip64End = offset;
    yield* emit(
      _bytes((b) {
        b
          ..u32(0x06064b50)
          ..u64(44) // size of the rest of this record
          ..u16(_madeBy)
          ..u16(45)
          ..u32(0)
          ..u32(0)
          ..u64(central.length)
          ..u64(central.length)
          ..u64(centralSize)
          ..u64(centralStart);
      }),
    );
    yield* emit(
      _bytes((b) {
        b
          ..u32(0x07064b50)
          ..u32(0)
          ..u64(zip64End)
          ..u32(1);
      }),
    );
  }
  yield* emit(
    _bytes((b) {
      final count = needsZip64End ? 0xFFFF : central.length;
      b
        ..u32(0x06054b50)
        ..u16(0)
        ..u16(0)
        ..u16(count)
        ..u16(count)
        ..u32(needsZip64End ? 0xFFFFFFFF : centralSize)
        ..u32(needsZip64End ? 0xFFFFFFFF : centralStart)
        ..u16(0); // comment length
    }),
  );
}

const int _madeBy = (3 << 8) | 45; // Unix, ZIP 4.5
const int _flags = (1 << 3) | (1 << 11); // data descriptor, UTF-8 names

final class _CentralRecord {
  _CentralRecord({required this.name, required this.method, required this.zip64, required this.dosTime, required this.dosDate, required this.offset});

  final List<int> name;
  final int method;
  final bool zip64;
  final int dosTime;
  final int dosDate;
  final int offset;
  int crc = 0;
  int size = 0;
  int compressed = 0;

  int get versionNeeded => zip64 || offset >= 0xFFFFFFFF ? 45 : 20;
}

List<int> _localHeader(_CentralRecord r) => _bytes((b) {
  b
    ..u32(0x04034b50)
    ..u16(r.zip64 ? 45 : 20)
    ..u16(_flags)
    ..u16(r.method)
    ..u16(r.dosTime)
    ..u16(r.dosDate)
    ..u32(0) // CRC-32: in the data descriptor
    ..u32(r.zip64 ? 0xFFFFFFFF : 0)
    ..u32(r.zip64 ? 0xFFFFFFFF : 0)
    ..u16(r.name.length)
    ..u16(r.zip64 ? 20 : 0)
    ..raw(r.name);
  if (r.zip64) {
    b
      ..u16(0x0001)
      ..u16(16)
      ..u64(0)
      ..u64(0);
  }
});

List<int> _dataDescriptor(_CentralRecord r) => _bytes((b) {
  b
    ..u32(0x08074b50)
    ..u32(r.crc);
  if (r.zip64) {
    b
      ..u64(r.compressed)
      ..u64(r.size);
  } else {
    b
      ..u32(r.compressed)
      ..u32(r.size);
  }
});

List<int> _centralHeader(_CentralRecord r) => _bytes((b) {
  final bigSize = r.size >= 0xFFFFFFFF;
  final bigCompressed = r.compressed >= 0xFFFFFFFF;
  final bigOffset = r.offset >= 0xFFFFFFFF;
  final extra = (bigSize ? 8 : 0) + (bigCompressed ? 8 : 0) + (bigOffset ? 8 : 0);
  b
    ..u32(0x02014b50)
    ..u16(_madeBy)
    ..u16(r.versionNeeded)
    ..u16(_flags)
    ..u16(r.method)
    ..u16(r.dosTime)
    ..u16(r.dosDate)
    ..u32(r.crc)
    ..u32(bigCompressed ? 0xFFFFFFFF : r.compressed)
    ..u32(bigSize ? 0xFFFFFFFF : r.size)
    ..u16(r.name.length)
    ..u16(extra == 0 ? 0 : extra + 4)
    ..u16(0) // comment length
    ..u16(0) // disk number
    ..u16(0) // internal attributes
    ..u32(0x81A4 << 16) // external attributes: regular file, mode 0644
    ..u32(bigOffset ? 0xFFFFFFFF : r.offset)
    ..raw(r.name);
  if (extra > 0) {
    // The ZIP64 extra field holds only the values that overflowed, in this order.
    b
      ..u16(0x0001)
      ..u16(extra);
    if (bigSize) {
      b.u64(r.size);
    }
    if (bigCompressed) {
      b.u64(r.compressed);
    }
    if (bigOffset) {
      b.u64(r.offset);
    }
  }
});

int _dosTime(DateTime t) {
  final local = t.toLocal();
  return (local.hour << 11) | (local.minute << 5) | (local.second ~/ 2);
}

int _dosDate(DateTime t) {
  final local = t.toLocal();
  if (local.year < 1980) {
    return (1 << 5) | 1; // 1980-01-01, the earliest a ZIP date can hold
  }
  return ((local.year - 1980).clamp(0, 127) << 9) | (local.month << 5) | local.day;
}

/// Formats that deflate can't shrink, so they're stored as they are.
bool _alreadyCompressed(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  const compressed = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', //
    'mp4', 'mov', 'mkv', 'webm', 'm4v', 'avi',
    'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac',
    'zip', 'gz', 'xz', 'bz2', 'zst', '7z', 'rar', 'pjx',
  };
  return compressed.contains(ext);
}

final class _Collect implements Sink<List<int>> {
  _Collect(this.out);

  final List<List<int>> out;

  @override
  void add(List<int> data) => out.add(data);

  @override
  void close() {}
}

final class _Writer {
  final BytesBuilder _builder = BytesBuilder();
  final ByteData _scratch = ByteData(8);

  void u16(int v) => _builder.add([v & 0xFF, (v >> 8) & 0xFF]);

  void u32(int v) {
    _scratch.setUint32(0, v, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void u64(int v) {
    _scratch.setUint64(0, v, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 8));
  }

  void raw(List<int> bytes) => _builder.add(bytes);
}

List<int> _bytes(void Function(_Writer b) build) {
  final writer = _Writer();
  build(writer);
  return writer._builder.takeBytes();
}
