import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:portfolio_jockey/vault/native/libc.dart';
import 'package:portfolio_jockey/vault/native/sodium.dart';

/// Why a PDF couldn't be opened.
enum PdfOpenFailure {
  /// The PDF needs a password. Encrypted PDFs aren't supported in previews.
  passwordProtected,

  /// Poppler couldn't read it, or Poppler isn't installed.
  unreadable,
}

final class PdfOpenException implements Exception {
  const PdfOpenException(this.failure, this.detail);

  final PdfOpenFailure failure;
  final String detail;

  @override
  String toString() => 'PdfOpenException(${failure.name}): $detail';
}

/// A page couldn't be rendered.
final class PdfRenderException implements Exception {
  const PdfRenderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One rendered page: premultiplied BGRA pixels (cairo's ARGB32 on a
/// little-endian machine), `width * 4` bytes per row.
final class PdfPageImage {
  const PdfPageImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
}

/// A PDF opened in memory with poppler-glib, rendered page by page.
///
/// Everything runs in one worker isolate. The PDF's bytes are moved there
/// once, copied into C memory that GLib reads without copying again
/// (`g_bytes_new_static`), and wiped with `sodium_memzero` on [close]. The
/// document is never opened from a path or a GFile (gvfs could fetch remote
/// files), and no signature, link or form functions are bound, so Poppler's
/// NSS signature checks are never reached. Only the functions listed in
/// tool/allowed-native-libs.txt may be bound here.
final class PdfDocument {
  PdfDocument._(this._requests, this._replies, this.pageSizes);

  /// The largest side of a rendered page, in pixels.
  static const int maxPixels = 4096;

  final SendPort _requests;
  final StreamIterator<Object?> _replies;

  /// Each page's size in PDF points (1/72 inch).
  final List<({double width, double height})> pageSizes;

  bool _closed = false;
  Future<void> _queue = Future.value();

  int get pageCount => pageSizes.length;

  /// Opens [bytes] (the decrypted PDF). The caller still owns [bytes] and
  /// should wipe it afterwards; the worker keeps its own C copy.
  static Future<PdfDocument> open(Uint8List bytes) async {
    final port = ReceivePort();
    final replies = StreamIterator<Object?>(port);
    await Isolate.spawn(_worker, port.sendPort, debugName: 'pdf');
    await replies.moveNext();
    final requests = replies.current! as SendPort;
    requests.send(TransferableTypedData.fromList([bytes]));
    await replies.moveNext();
    final opened = replies.current! as List<Object?>;
    if (opened.first case final String failure) {
      requests.send(null);
      port.close();
      throw PdfOpenException(PdfOpenFailure.values.byName(failure), opened[1]! as String);
    }
    final sizes = [
      for (final size in (opened[1]! as List<Object?>).cast<List<Object?>>())
        (width: size[0]! as double, height: size[1]! as double),
    ];
    return PdfDocument._(requests, replies, sizes);
  }

  /// Renders page [index] (0-based) at [scale] pixels per PDF point, capped
  /// at [maxPixels] on the longer side. Requests run one at a time.
  Future<PdfPageImage> render(int index, double scale) {
    RangeError.checkValidIndex(index, pageSizes, 'index');
    final result = _queue.then((_) async {
      if (_closed) {
        throw StateError('PDF is closed');
      }
      _requests.send([index, scale]);
      await _replies.moveNext();
      final reply = _replies.current! as List<Object?>;
      if (reply.first case final String error) {
        throw PdfRenderException("Couldn't render page ${index + 1}: $error");
      }
      final pixels = (reply[2]! as TransferableTypedData).materialize().asUint8List();
      return PdfPageImage(reply[0]! as int, reply[1]! as int, pixels);
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Frees the document and wipes the worker's copy of the PDF.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await _queue;
    _closed = true;
    _requests.send(null);
    await _replies.moveNext();
    await _replies.cancel();
  }
}

// --- Worker isolate --------------------------------------------------------

const int _popplerErrorEncrypted = 1; // POPPLER_ERROR_ENCRYPTED
const int _cairoFormatArgb32 = 0; // CAIRO_FORMAT_ARGB32

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Uint8> message;
}

final class _Poppler {
  _Poppler() {
    final poppler = DynamicLibrary.open('libpoppler-glib.so.8');
    final cairo = DynamicLibrary.open('libcairo.so.2');
    final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    final glib = DynamicLibrary.open('libglib-2.0.so.0');
    newFromBytes = poppler.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<_GError>>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<_GError>>)
    >('poppler_document_new_from_bytes');
    nPages = poppler.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('poppler_document_get_n_pages');
    getPage = poppler.lookupFunction<Pointer<Void> Function(Pointer<Void>, Int), Pointer<Void> Function(Pointer<Void>, int)>('poppler_document_get_page');
    pageSize = poppler.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Double>, Pointer<Double>),
      void Function(Pointer<Void>, Pointer<Double>, Pointer<Double>)
    >('poppler_page_get_size');
    renderPage = poppler.lookupFunction<Void Function(Pointer<Void>, Pointer<Void>), void Function(Pointer<Void>, Pointer<Void>)>('poppler_page_render');
    surfaceCreate = cairo.lookupFunction<Pointer<Void> Function(Int, Int, Int), Pointer<Void> Function(int, int, int)>('cairo_image_surface_create');
    surfaceStatus = cairo.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('cairo_surface_status');
    create = cairo.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('cairo_create');
    scale = cairo.lookupFunction<Void Function(Pointer<Void>, Double, Double), void Function(Pointer<Void>, double, double)>('cairo_scale');
    setSourceRgb = cairo.lookupFunction<
      Void Function(Pointer<Void>, Double, Double, Double),
      void Function(Pointer<Void>, double, double, double)
    >('cairo_set_source_rgb');
    paint = cairo.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('cairo_paint');
    destroy = cairo.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('cairo_destroy');
    surfaceFlush = cairo.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('cairo_surface_flush');
    surfaceData = cairo.lookupFunction<Pointer<Uint8> Function(Pointer<Void>), Pointer<Uint8> Function(Pointer<Void>)>('cairo_image_surface_get_data');
    surfaceStride = cairo.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('cairo_image_surface_get_stride');
    surfaceDestroy = cairo.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('cairo_surface_destroy');
    bytesNewStatic = glib.lookupFunction<Pointer<Void> Function(Pointer<Uint8>, Size), Pointer<Void> Function(Pointer<Uint8>, int)>('g_bytes_new_static');
    bytesUnref = glib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_bytes_unref');
    errorFree = glib.lookupFunction<Void Function(Pointer<_GError>), void Function(Pointer<_GError>)>('g_error_free');
    objectUnref = gobject.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('g_object_unref');
  }

  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<_GError>>) newFromBytes;
  late final int Function(Pointer<Void>) nPages;
  late final Pointer<Void> Function(Pointer<Void>, int) getPage;
  late final void Function(Pointer<Void>, Pointer<Double>, Pointer<Double>) pageSize;
  late final void Function(Pointer<Void>, Pointer<Void>) renderPage;
  late final Pointer<Void> Function(int, int, int) surfaceCreate;
  late final int Function(Pointer<Void>) surfaceStatus;
  late final Pointer<Void> Function(Pointer<Void>) create;
  late final void Function(Pointer<Void>, double, double) scale;
  late final void Function(Pointer<Void>, double, double, double) setSourceRgb;
  late final void Function(Pointer<Void>) paint;
  late final void Function(Pointer<Void>) destroy;
  late final void Function(Pointer<Void>) surfaceFlush;
  late final Pointer<Uint8> Function(Pointer<Void>) surfaceData;
  late final int Function(Pointer<Void>) surfaceStride;
  late final void Function(Pointer<Void>) surfaceDestroy;
  late final Pointer<Void> Function(Pointer<Uint8>, int) bytesNewStatic;
  late final void Function(Pointer<Void>) bytesUnref;
  late final void Function(Pointer<_GError>) errorFree;
  late final void Function(Pointer<Void>) objectUnref;
}

Future<void> _worker(SendPort replies) async {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  final messages = StreamIterator<Object?>(requests);
  await messages.moveNext();
  final received = (messages.current! as TransferableTypedData).materialize().asUint8List();

  final libc = Libc.instance;
  final sodium = Sodium.instance;
  final size = received.length;
  final data = libc.malloc(size == 0 ? 1 : size);
  data.asTypedList(size).setAll(0, received);
  received.fillRange(0, size, 0);

  _Poppler? lib;
  var bytes = nullptr.cast<Void>();
  var document = nullptr.cast<Void>();
  try {
    lib = _Poppler();
    bytes = lib.bytesNewStatic(data, size);
    document = _openDocument(lib, bytes);
    final sizes = <List<double>>[];
    final count = lib.nPages(document);
    final widthOut = libc.malloc(sizeOf<Double>() * 2).cast<Double>();
    try {
      for (var i = 0; i < count; i++) {
        final page = lib.getPage(document, i);
        lib.pageSize(page, widthOut, widthOut + 1);
        sizes.add([widthOut.value, (widthOut + 1).value]);
        lib.objectUnref(page);
      }
    } finally {
      libc.free(widthOut);
    }
    replies.send([null, sizes]);

    while (await messages.moveNext()) {
      final request = messages.current;
      if (request == null) {
        break;
      }
      final [index as int, scale as double] = request as List<Object?>;
      try {
        replies.send(_renderPage(lib, document, index, scale));
      } on Object catch (error) {
        replies.send(['$error']);
      }
    }
  } on PdfOpenException catch (error) {
    replies.send([error.failure.name, error.detail]);
    await messages.moveNext(); // the close request
  } on Object catch (error) {
    replies.send([PdfOpenFailure.unreadable.name, '$error']);
    await messages.moveNext();
  } finally {
    if (document != nullptr) {
      lib!.objectUnref(document);
    }
    if (bytes != nullptr) {
      lib!.bytesUnref(bytes);
    }
    sodium.wipe(data, size);
    libc.free(data);
    replies.send(null);
    requests.close();
  }
}

Pointer<Void> _openDocument(_Poppler lib, Pointer<Void> bytes) {
  final libc = Libc.instance;
  final errorOut = libc.malloc(sizeOf<Pointer<_GError>>()).cast<Pointer<_GError>>();
  try {
    errorOut.value = nullptr;
    final document = lib.newFromBytes(bytes, nullptr, errorOut);
    if (document != nullptr) {
      return document;
    }
    final error = errorOut.value;
    if (error == nullptr) {
      throw const PdfOpenException(PdfOpenFailure.unreadable, 'unknown error');
    }
    final message = _cString(error.ref.message);
    final encrypted = error.ref.code == _popplerErrorEncrypted;
    lib.errorFree(error);
    throw PdfOpenException(encrypted ? PdfOpenFailure.passwordProtected : PdfOpenFailure.unreadable, message);
  } finally {
    libc.free(errorOut);
  }
}

List<Object?> _renderPage(_Poppler lib, Pointer<Void> document, int index, double scale) {
  final libc = Libc.instance;
  final sizeOut = libc.malloc(sizeOf<Double>() * 2).cast<Double>();
  final page = lib.getPage(document, index);
  if (page == nullptr) {
    libc.free(sizeOut);
    return ['no such page'];
  }
  try {
    lib.pageSize(page, sizeOut, sizeOut + 1);
    final pointWidth = sizeOut.value;
    final pointHeight = (sizeOut + 1).value;
    final longest = pointWidth > pointHeight ? pointWidth : pointHeight;
    var pixelScale = scale;
    if (longest * pixelScale > PdfDocument.maxPixels) {
      pixelScale = PdfDocument.maxPixels / longest;
    }
    final width = (pointWidth * pixelScale).ceil().clamp(1, PdfDocument.maxPixels);
    final height = (pointHeight * pixelScale).ceil().clamp(1, PdfDocument.maxPixels);

    final surface = lib.surfaceCreate(_cairoFormatArgb32, width, height);
    try {
      if (lib.surfaceStatus(surface) != 0) {
        return ['cairo surface status ${lib.surfaceStatus(surface)}'];
      }
      final cr = lib.create(surface);
      lib
        ..setSourceRgb(cr, 1, 1, 1)
        ..paint(cr)
        ..scale(cr, pixelScale, pixelScale)
        ..renderPage(page, cr)
        ..destroy(cr)
        ..surfaceFlush(surface);
      final stride = lib.surfaceStride(surface);
      final source = lib.surfaceData(surface);
      final pixels = Uint8List(width * height * 4);
      for (var row = 0; row < height; row++) {
        pixels.setRange(row * width * 4, (row + 1) * width * 4, (source + row * stride).asTypedList(width * 4));
      }
      return [width, height, TransferableTypedData.fromList([pixels])];
    } finally {
      lib.surfaceDestroy(surface);
    }
  } finally {
    lib.objectUnref(page);
    libc.free(sizeOut);
  }
}

String _cString(Pointer<Uint8> chars) {
  if (chars == nullptr) {
    return 'unknown error';
  }
  var length = 0;
  while (chars[length] != 0) {
    length++;
  }
  return utf8.decode(chars.asTypedList(length), allowMalformed: true);
}
