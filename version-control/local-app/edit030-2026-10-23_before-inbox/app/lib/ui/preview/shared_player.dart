import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The one mpv player the app uses for audio and video previews. It's made the
/// first time media is previewed and is never disposed: media_kit_video's CPU
/// (S/W) path frees its pixel buffer on dispose while Flutter's raster thread
/// may still be reading it, which froze the app after closing a playing video
/// (docs/dependencies.md). Closing a preview only stops playback.
///
/// One file at a time. Opening a file replaces the previous one; closing a file
/// that has already been replaced only waits until mpv has let go of it, so the
/// caller can wipe its readable copy. Files open paused (PM decision).
final class SharedPlayer {
  SharedPlayer({
    required this.command,
    required this.pause,
    required this.stop,
    required this.getProperty,
    this.player,
    this.video,
    this.timeout = const Duration(seconds: 2),
    this.settle = const Duration(milliseconds: 250),
    this.interval = const Duration(milliseconds: 20),
  });

  /// The app's player, made on first use with [lockedDownOptions] applied.
  /// If making it fails, the next call tries again.
  static Future<SharedPlayer> instance({required void Function() prepare, required Map<String, String> lockedDownOptions}) {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    final created = _create(prepare, lockedDownOptions);
    _instance = created;
    unawaited(created.then<void>((_) {}, onError: (Object _) => _instance = null));
    return created;
  }

  static Future<SharedPlayer> _create(void Function() prepare, Map<String, String> lockedDownOptions) async {
    prepare();
    final player = Player(configuration: const PlayerConfiguration(title: 'Portfolio Jockey', protocolWhitelist: ['file']));
    final native = player.platform! as NativePlayer;
    for (final MapEntry(:key, :value) in lockedDownOptions.entries) {
      await native.setProperty(key, value);
    }
    final video = VideoController(player);
    // pause() and stop() go through media_kit, not raw mpv commands, so its own
    // playing state stays in step and the Play button works on the next file.
    return SharedPlayer(
      command: native.command,
      pause: player.pause,
      stop: player.stop,
      getProperty: native.getProperty,
      player: player,
      video: video,
    );
  }

  static Future<SharedPlayer>? _instance;

  final Future<void> Function(List<String> command) command;
  final Future<void> Function() pause;
  final Future<void> Function() stop;
  final Future<String> Function(String property) getProperty;
  final Player? player;
  final VideoController? video;
  final Duration timeout;

  /// How long the main thread gets to draw queued frames between pausing and
  /// stopping.
  final Duration settle;
  final Duration interval;

  String? _current;
  Future<void> _queue = Future<void>.value();

  /// Loads [copy] paused. Waits (up to [timeout]) until mpv has it open.
  Future<void> open(File copy) => _serial(() async {
    _current = copy.path;
    await pause();
    // Player.open() would write a playlist file with this path to /tmp, so
    // the file is loaded with mpv's own command instead.
    await command(['loadfile', copy.path, 'replace']);
    await _waitUntil('idle-active', (v) => v == 'no');
  });

  /// Stops [copy] if it's still the file playing, and waits (up to [timeout])
  /// until mpv no longer has it open. Never throws and never disposes.
  Future<void> close(File copy) => _serial(() async {
    try {
      if (_current == copy.path) {
        _current = null;
        // stop() is a blocking mpv call on the main thread, and in the CPU
        // (S/W) path mpv waits for that thread to draw its pending frames
        // while it shuts the video output down. Pausing first and letting the
        // main thread draw what's queued leaves nothing for stop() to wait on.
        await pause();
        await Future<void>.delayed(settle);
        await stop();
        await _waitUntil('idle-active', (v) => v == 'yes');
      } else {
        await _waitUntil('path', (v) => v != copy.path);
      }
    } on Object {
      // Best effort: wiping the readable copy must still happen.
    }
  });

  Future<void> _waitUntil(String property, bool Function(String value) done) async {
    final deadline = DateTime.now().add(timeout);
    while (!done(await getProperty(property)) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
    }
  }

  // Runs [step] after every step started before it, so a close and the next
  // open never interleave.
  Future<void> _serial(Future<void> Function() step) {
    final next = _queue.then((_) => step());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }
}
