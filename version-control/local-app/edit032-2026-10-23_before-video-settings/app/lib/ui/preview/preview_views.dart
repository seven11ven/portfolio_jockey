import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/native/poppler.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/preview/shared_player.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// How a file is previewed.
enum PreviewKind {
  image(200 * 1000 * 1000),
  text(5 * 1000 * 1000),
  markdown(5 * 1000 * 1000),
  pdf(200 * 1000 * 1000),

  /// Audio and video, played from a memory-only copy (no size limit here;
  /// the memory folder's own size is the limit).
  media(0),
  none(0);

  const PreviewKind(this.maxBytes);

  /// The most that's decrypted into memory for this kind.
  final int maxBytes;
}

PreviewKind previewKind(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  const markdown = {'md', 'markdown'};
  const text = {
    'txt', 'text', 'csv', 'tsv', 'json', 'log', 'xml', 'yaml', 'yml', 'ini', 'conf', 'toml', //
    'html', 'css', 'js', 'ts', 'dart', 'py', 'sh', 'c', 'h', 'cpp', 'java', 'kt', 'rs', 'go', 'rb', 'php', 'sql',
  };
  const media = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', 'mp3', 'm4a', 'wav', 'flac', 'ogg', 'opus', 'aac'};
  if (images.contains(ext)) {
    return PreviewKind.image;
  }
  if (markdown.contains(ext)) {
    return PreviewKind.markdown;
  }
  if (text.contains(ext)) {
    return PreviewKind.text;
  }
  if (ext == 'pdf') {
    return PreviewKind.pdf;
  }
  if (media.contains(ext)) {
    return PreviewKind.media;
  }
  return PreviewKind.none;
}

/// An image decoded from memory. On dispose it's evicted from Flutter's image
/// cache and its bytes are zeroed.
class ImagePreview extends StatefulWidget {
  const ImagePreview({required this.bytes, this.onSize, super.key});

  final Uint8List bytes;
  final void Function(int width, int height)? onSize;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  late final MemoryImage _image = MemoryImage(widget.bytes);
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) => widget.onSize?.call(info.image.width, info.image.height));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = _image.resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    unawaited(_image.evict());
    widget.bytes.fillRange(0, widget.bytes.length, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    maxScale: 8,
    child: Center(
      child: Image(image: _image, errorBuilder: (_, _, _) => const Notice("This image can't be shown. It may be damaged or in a format the app can't read.")),
    ),
  );
}

/// Plain text, shown in a monospace font. The bytes are zeroed once decoded.
class TextPreview extends StatefulWidget {
  const TextPreview({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  State<TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<TextPreview> {
  late final String _text = utf8.decode(widget.bytes, allowMalformed: true);

  @override
  void initState() {
    super.initState();
    _text.length; // Decode now, then wipe the bytes.
    widget.bytes.fillRange(0, widget.bytes.length, 0);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText(_text, style: pathStyle.copyWith(fontSize: 13.5, height: 1.45)),
  );
}

/// Formatted Markdown. Images are never loaded: [placeholderImage] always
/// replaces them (flutter_markdown_plus would otherwise fetch them from the
/// network or read them from disk), and links do nothing.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  late final String _text = utf8.decode(widget.bytes, allowMalformed: true);

  @override
  void initState() {
    super.initState();
    _text.length;
    widget.bytes.fillRange(0, widget.bytes.length, 0);
  }

  @override
  Widget build(BuildContext context) => Markdown(
    data: _text,
    selectable: true,
    padding: const EdgeInsets.all(20),
    imageBuilder: (_, _, _) => placeholderImage(context),
  );
}

/// What a Markdown image shows instead of the image.
Widget placeholderImage(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      Icon(Icons.image_not_supported_outlined, size: 18, color: PjColors.of(context).muted),
      const Flexible(child: Muted('Image not loaded: images in Markdown files are never fetched.')),
    ],
  ),
);

/// A PDF rendered page by page in memory by Poppler.
class PdfPreview extends StatefulWidget {
  const PdfPreview({required this.bytes, this.onPageCount, super.key});

  /// The decrypted PDF. Zeroed as soon as Poppler has its own copy.
  final Uint8List bytes;
  final void Function(int pages)? onPageCount;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> {
  static const List<double> _zooms = [0.5, 0.75, 1, 1.25, 1.5, 2, 3];

  PdfDocument? _pdf;
  String? _error;
  int _page = 0;
  int _zoom = 2;
  ui.Image? _image;
  int _renderToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final pdf = await PdfDocument.open(widget.bytes);
      if (!mounted) {
        await pdf.close();
        return;
      }
      setState(() => _pdf = pdf);
      widget.onPageCount?.call(pdf.pageCount);
      await _render();
    } on PdfOpenException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.failure == PdfOpenFailure.passwordProtected
              ? "This PDF is password-protected, so it can't be previewed. Use “Edit in another app” to open it."
              : "This PDF can't be shown. It may be damaged, or Poppler (libpoppler-glib) isn't installed.",
        );
      }
    } finally {
      widget.bytes.fillRange(0, widget.bytes.length, 0);
    }
  }

  Future<void> _render() async {
    final pdf = _pdf;
    if (pdf == null || pdf.pageCount == 0) {
      return;
    }
    final token = ++_renderToken;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    try {
      final page = await pdf.render(_page, _zooms[_zoom] * ratio);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(page.pixels, page.width, page.height, ui.PixelFormat.bgra8888, completer.complete);
      final image = await completer.future;
      page.pixels.fillRange(0, page.pixels.length, 0);
      if (!mounted || token != _renderToken) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } on PdfRenderException catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
  }

  void _go({int? page, int? zoom}) {
    setState(() {
      _page = page ?? _page;
      _zoom = zoom ?? _zoom;
    });
    unawaited(_render());
  }

  @override
  void dispose() {
    _image?.dispose();
    unawaited(_pdf?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Notice(error)));
    }
    final pdf = _pdf;
    final image = _image;
    if (pdf == null || image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = pdf.pageSizes[_page];
    final zoom = _zooms[_zoom];
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: PjColors.of(context).muted.withValues(alpha: 0.12),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(border: Border.all(color: PjColors.of(context).border)),
                    child: SizedBox(
                      width: size.width * zoom,
                      height: size.height * zoom,
                      child: RawImage(image: image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(onPressed: _page > 0 ? () => _go(page: _page - 1) : null, icon: const Icon(Icons.chevron_left), label: const Text('Prev')),
              Text('Page ${_page + 1} of ${pdf.pageCount}'),
              TextButton.icon(
                onPressed: _page < pdf.pageCount - 1 ? () => _go(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
                iconAlignment: IconAlignment.end,
              ),
              const SizedBox(width: 12),
              IconButton(tooltip: 'Zoom out', onPressed: _zoom > 0 ? () => _go(zoom: _zoom - 1) : null, icon: const Icon(Icons.remove)),
              SizedBox(width: 48, child: Text('${(zoom * 100).round()}%', textAlign: TextAlign.center)),
              IconButton(tooltip: 'Zoom in', onPressed: _zoom < _zooms.length - 1 ? () => _go(zoom: _zoom + 1) : null, icon: const Icon(Icons.add)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A wakelock that does nothing. media_kit_video's wakelock (wakelock_plus)
/// would talk to the desktop over D-Bus and run `stat`; the app never wants
/// it, so this replaces it before any player exists.
final class _NoWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// Loads the system libmpv (pinned by name, so `LIBMPV_LIBRARY_PATH` can't
/// swap it) and replaces the wakelock. Safe to call more than once.
void ensureMediaReady() {
  if (WakelockPlusPlatformInterface.instance is! _NoWakelock) {
    WakelockPlusPlatformInterface.instance = _NoWakelock();
  }
  MediaKit.ensureInitialized(libmpv: 'libmpv.so.2');
}

/// mpv options that keep playback local. media_kit sets `cache-on-disk=yes`
/// and allows network protocols by default; see docs/dependencies.md.
const Map<String, String> lockedDownMpvOptions = {
  'cache-on-disk': 'no', // keep the demuxer cache in memory
  'ytdl': 'no', // unload the youtube-dl hook script
  'access-references': 'no', // don't follow references to other files inside media files
  'load-unsafe-playlists': 'no',
  'stream-lavf-o': 'protocol_whitelist=[file]', // FFmpeg streams: local files only
  'sub-auto': 'no', // don't look for subtitle files next to the copy
  'cover-art-auto': 'no',
  'save-position-on-quit': 'no',
  // Previews are short and read from a memory folder, so a big in-memory
  // read-ahead cache only adds memory that keeps growing (measured
  // 2026-10-23); mpv's defaults are 150 MiB plus a 50 MiB back buffer.
  'demuxer-max-bytes': '32MiB',
  'demuxer-max-back-bytes': '0',
};

/// Audio or video, played by libmpv from a readable copy in a private
/// memory-only folder. The copy is wiped when this closes.
class MediaPreview extends StatefulWidget {
  const MediaPreview({required this.copy, this.onDuration, super.key});

  final File copy;
  final void Function(Duration duration)? onDuration;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  Future<SharedPlayer>? _shared;
  VideoController? _video;
  StreamSubscription<Duration>? _duration;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final shared = SharedPlayer.instance(prepare: ensureMediaReady, lockedDownOptions: lockedDownMpvOptions);
      _shared = shared;
      final player = await shared;
      await player.open(widget.copy);
      if (!mounted) {
        return;
      }
      _duration = player.player?.stream.duration.listen((d) {
        if (d > Duration.zero) {
          widget.onDuration?.call(d);
        }
      });
      setState(() => _video = player.video);
    } on PlayerStuck catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = "This file can't be played: $e");
      }
    }
  }

  @override
  void dispose() {
    unawaited(_duration?.cancel());
    final shared = _shared;
    final copy = widget.copy;
    // The shared player is only stopped, never disposed (see SharedPlayer).
    unawaited(() async {
      await (await shared)?.close(copy);
      await PrivateFolders.wipe(copy.parent);
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Notice(error)));
    }
    final video = _video;
    if (video == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Video(controller: video, wakelock: false, controls: MaterialDesktopVideoControls);
  }
}
