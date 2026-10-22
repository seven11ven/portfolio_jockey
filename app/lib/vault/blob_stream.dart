import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/atomic_write.dart';
import 'package:portfolio_jockey/vault/errors.dart';
import 'package:portfolio_jockey/vault/native/scratch_buffer.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';
import 'package:portfolio_jockey/vault/secure_buffer.dart';

// Encrypted file layout (`blobs/<id>.enc`, `cover.enc`):
//    0   4  magic "PJBL"
//    4   1  format version (1)
//    5   3  reserved, zero
//    8   4  chunk size in bytes (little-endian)
//   12  24  secretstream header
//   36   …  chunks: each is up to `chunk size` bytes of the file plus a 17-byte
//           tag. Every chunk but the last is full; the last carries the FINAL tag.
// The first 12 bytes are the associated data of every chunk, so changing the
// chunk size breaks the integrity check. secretstream itself detects changed,
// reordered or dropped chunks; a missing FINAL tag means the file was cut short.

/// The chunk size for new files.
const int defaultChunkSize = 64 * 1024;

/// The largest chunk size accepted when reading, so a damaged header can't
/// make the reader allocate a huge buffer.
const int maxChunkSize = 16 * 1024 * 1024;

const List<int> _magic = [0x50, 0x4a, 0x42, 0x4c]; // "PJBL"
const int _formatVersion = 1;
const int _prefixLength = 12;

/// Encrypts [plaintext] into [target] with [key], streaming, so a large file
/// is never held in memory whole. [target] is written atomically.
Future<void> encryptToFile(Stream<List<int>> plaintext, File target, SecureBuffer key, {int chunkSize = defaultChunkSize}) =>
    writeAtomically(target, (out) => encryptTo(out, plaintext, key, chunkSize: chunkSize));

/// Writes [plaintext], encrypted with [key], to [out] from its current
/// position: the 12-byte prefix, the secretstream header, then the chunks.
/// Used by [encryptToFile], and by locked exports after their own header.
Future<void> encryptTo(RandomAccessFile out, Stream<List<int>> plaintext, SecureBuffer key, {int chunkSize = defaultChunkSize}) async {
  if (chunkSize <= 0 || chunkSize > maxChunkSize) {
    throw ArgumentError.value(chunkSize, 'chunkSize');
  }
  final sodium = Sodium.instance;
  if (key.length != sodium.streamKeyBytes) {
    throw ArgumentError.value(key.length, 'key', 'must be ${sodium.streamKeyBytes} bytes');
  }
  final prefix = _prefix(chunkSize);
  final state = SecureBuffer.allocate(sodium.streamStateBytes);
  final streamHeader = ScratchBuffer(sodium.streamHeaderBytes);
  final ad = ScratchBuffer.from(prefix);
  final input = ScratchBuffer(chunkSize);
  final output = ScratchBuffer(chunkSize + sodium.streamTagBytes);
  final chunk = Uint8List(chunkSize);
  try {
    state.use((s) => key.use((k) => sodium.streamInitPush(s, streamHeader.pointer, k)));
    await out.writeFrom(prefix);
    await out.writeFrom(streamHeader.copy());

    Future<void> push(int length, int tag) async {
      input.view.setRange(0, length, chunk);
      state.use((s) => sodium.streamPush(s, output.pointer, input.pointer, length, ad.pointer, ad.length, tag));
      await out.writeFrom(output.copy(length + sodium.streamTagBytes));
    }

    // A full chunk is only pushed once more data arrives, so the last chunk
    // (even an empty one) is always the one tagged FINAL.
    var filled = 0;
    await for (final data in plaintext) {
      var offset = 0;
      while (offset < data.length) {
        if (filled == chunkSize) {
          await push(filled, sodium.streamTagMessage);
          filled = 0;
        }
        final count = min(chunkSize - filled, data.length - offset);
        chunk.setRange(filled, filled + count, data, offset);
        filled += count;
        offset += count;
      }
    }
    await push(filled, sodium.streamTagFinal);
  } finally {
    chunk.fillRange(0, chunk.length, 0);
    state.dispose();
    streamHeader.free();
    ad.free();
    input.free();
    output.free();
  }
}

/// Decrypts [source] with [key], one chunk at a time.
///
/// The stream ends with [TamperedData] if any chunk was changed, reordered or
/// dropped, if the file was cut short, or if data follows the final chunk.
/// Chunks before the failure have already been delivered by then, so a caller
/// must throw away everything it received from a stream that ends in an error.
Stream<Uint8List> decryptFile(File source, SecureBuffer key) async* {
  final file = await source.open();
  try {
    yield* decryptFrom(file, key);
  } finally {
    await file.close();
  }
}

/// Decrypts what [encryptTo] wrote, reading [file] from its current position
/// to its end. [file] stays open. Errors are reported as for [decryptFile].
Stream<Uint8List> decryptFrom(RandomAccessFile file, SecureBuffer key) async* {
  final sodium = Sodium.instance;
  final state = SecureBuffer.allocate(sodium.streamStateBytes);
  final buffers = <ScratchBuffer>[];
  ScratchBuffer scratch(ScratchBuffer buffer) {
    buffers.add(buffer);
    return buffer;
  }

  try {
    final prefix = await file.read(_prefixLength);
    final chunkSize = _readPrefix(prefix);
    final streamHeader = scratch(ScratchBuffer.from(await file.read(sodium.streamHeaderBytes)));
    if (streamHeader.length != sodium.streamHeaderBytes ||
        !state.use((s) => key.use((k) => sodium.streamInitPull(s, streamHeader.pointer, k)))) {
      throw const TamperedData('Encrypted file header is damaged');
    }
    final ad = scratch(ScratchBuffer.from(prefix));
    final fullChunk = chunkSize + sodium.streamTagBytes;
    final input = scratch(ScratchBuffer(fullChunk));
    final output = scratch(ScratchBuffer(chunkSize));
    final tag = scratch(ScratchBuffer(1));

    var finished = false;
    while (true) {
      final bytes = await file.read(fullChunk);
      if (bytes.isEmpty) {
        break;
      }
      if (finished) {
        throw const TamperedData('Encrypted file has data after its final chunk');
      }
      input.view.setAll(0, bytes);
      final chunkTag = state.use(
        (s) => sodium.streamPull(s, output.pointer, tag.pointer, input.pointer, bytes.length, ad.pointer, ad.length),
      );
      if (chunkTag == null) {
        throw const TamperedData('Encrypted file failed its integrity check');
      }
      finished = chunkTag == sodium.streamTagFinal;
      yield output.copy(bytes.length - sodium.streamTagBytes);
    }
    if (!finished) {
      throw const TamperedData('Encrypted file is incomplete');
    }
  } finally {
    state.dispose();
    for (final buffer in buffers) {
      buffer.free();
    }
  }
}

Uint8List _prefix(int chunkSize) {
  final bytes = Uint8List(_prefixLength)
    ..setAll(0, _magic)
    ..[4] = _formatVersion;
  ByteData.sublistView(bytes).setUint32(8, chunkSize, Endian.little);
  return bytes;
}

int _readPrefix(Uint8List bytes) {
  if (bytes.length < _prefixLength) {
    throw const VaultFormatError('Encrypted file is too short');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const VaultFormatError('Not a Portfolio Jockey encrypted file');
    }
  }
  if (bytes[4] != _formatVersion) {
    throw VaultFormatError('Unsupported encrypted file version ${bytes[4]}');
  }
  final chunkSize = ByteData.sublistView(bytes).getUint32(8, Endian.little);
  if (chunkSize == 0 || chunkSize > maxChunkSize) {
    throw VaultFormatError('Encrypted file has an invalid chunk size ($chunkSize)');
  }
  return chunkSize;
}
