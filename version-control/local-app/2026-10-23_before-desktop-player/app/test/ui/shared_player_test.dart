import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/ui/preview/preview_views.dart';
import 'package:portfolio_jockey/ui/preview/shared_player.dart';

/// A stand-in for the player: records what's sent and answers `idle-active` and
/// `path` the way mpv would.
class FakeMpv {
  final calls = <String>[];
  String? path;
  bool fail = false;
  bool neverIdle = false;

  /// Steps that never finish, like a media_kit call whose mpv reply is lost.
  final Set<String> hang = {};

  SharedPlayer player({Duration timeout = const Duration(seconds: 2), Duration stepLimit = const Duration(seconds: 5), Future<void>? ready}) => SharedPlayer(
    command: (command) async {
      if (hang.contains(command.first)) {
        await Completer<void>().future;
      }
      if (fail) {
        throw StateError('mpv gone');
      }
      calls.add(command.join(' '));
      if (command.first == 'loadfile') {
        path = command[1];
      }
    },
    pause: () async {
      if (hang.contains('pause')) {
        await Completer<void>().future;
      }
      calls.add('pause');
    },
    stop: () async {
      if (hang.contains('stop')) {
        await Completer<void>().future;
      }
      if (fail) {
        throw StateError('mpv gone');
      }
      calls.add('stop');
      path = null;
    },
    getProperty: (property) async => switch (property) {
      'idle-active' => path == null && !neverIdle ? 'yes' : 'no',
      'path' => path ?? '',
      _ => '',
    },
    setProperty: (property, value) async {
      if (hang.contains('set')) {
        await Completer<void>().future;
      }
      calls.add('set $property=$value');
    },
    ready: ready,
    timeout: timeout,
    stepLimit: stepLimit,
    interval: Duration.zero,
    settle: Duration.zero,
  );
}

void main() {
  final a = File('/dev/shm/x/a.mp4');
  final b = File('/dev/shm/x/b.mp3');

  test('open loads the file paused; close stops it; nothing is ever disposed', () async {
    final mpv = FakeMpv();
    final player = mpv.player();
    await player.open(a);
    expect(mpv.calls, ['pause', 'loadfile ${a.path} replace']);
    await player.close(a);
    expect(mpv.calls.sublist(2), ['pause', 'stop'], reason: 'paused before stopping, so mpv has no frame in flight');
    expect(mpv.path, isNull);
  });

  test('options are set after pausing and before the file loads', () async {
    final mpv = FakeMpv();
    final player = mpv.player();
    await player.open(a, options: {'hwdec': 'no', 'vf': ''});
    expect(mpv.calls, ['pause', 'set hwdec=no', 'set vf=', 'loadfile ${a.path} replace']);
  });

  test('open waits until the video output has started, so its own hwdec cannot win', () async {
    final mpv = FakeMpv();
    final started = Completer<void>();
    final player = mpv.player(ready: started.future);
    final opening = player.open(a, options: {'hwdec': 'auto-copy-safe'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mpv.calls, isEmpty);
    started.complete();
    await opening;
    expect(mpv.calls.first, 'pause');
    expect(mpv.calls[1], 'set hwdec=auto-copy-safe');
  });

  test('switching files: the old preview closing late does not stop the new file', () async {
    final mpv = FakeMpv();
    final player = mpv.player();
    await player.open(a);
    // Flutter starts the next preview before it disposes the old one.
    final opening = player.open(b);
    final closing = player.close(a);
    await Future.wait([opening, closing]);
    expect(mpv.path, b.path, reason: 'b keeps playing');
    expect(mpv.calls.where((c) => c == 'stop'), isEmpty);
    await player.close(b);
    expect(mpv.path, isNull);
  });

  test('close gives up after the time limit instead of hanging', () async {
    final mpv = FakeMpv()..neverIdle = true;
    final player = mpv.player(timeout: const Duration(milliseconds: 100));
    await player.open(a);
    final watch = Stopwatch()..start();
    await player.close(a);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('an mpv error on close is swallowed, so the copy can still be wiped', () async {
    final mpv = FakeMpv();
    final player = mpv.player();
    await player.open(a);
    mpv.fail = true;
    await expectLater(player.close(a), completes);
  });

  group('a player that stops responding', () {
    const limit = Duration(milliseconds: 100);

    test('open gives up within the limit, and the player is set aside', () async {
      final mpv = FakeMpv()..hang.add('pause');
      final player = mpv.player(stepLimit: limit);
      final watch = Stopwatch()..start();
      await expectLater(player.open(a), throwsA(isA<PlayerStuck>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(player.stuck, isTrue);
      await expectLater(player.open(b), throwsA(isA<PlayerStuck>()), reason: 'a stuck player is not used again');
    });

    test('a stuck stop during close still lets the copy be wiped, and marks the player stuck', () async {
      final mpv = FakeMpv();
      final player = mpv.player(stepLimit: limit);
      await player.open(a);
      mpv.hang.add('stop');
      await expectLater(player.close(a), completes);
      expect(player.stuck, isTrue);
    });

    test('an option that never sets is caught too', () async {
      final mpv = FakeMpv()..hang.add('set');
      final player = mpv.player(stepLimit: limit);
      await expectLater(player.open(a, options: {'vf': ''}), throwsA(isA<PlayerStuck>()));
      expect(player.stuck, isTrue);
    });

    test('a video output that never starts is caught too', () async {
      final mpv = FakeMpv();
      final player = mpv.player(stepLimit: limit, ready: Completer<void>().future);
      await expectLater(player.open(a), throwsA(isA<PlayerStuck>()));
    });

    test('loadfile that never returns is caught too', () async {
      final mpv = FakeMpv()..hang.add('loadfile');
      final player = mpv.player(stepLimit: limit);
      await expectLater(player.open(a), throwsA(isA<PlayerStuck>()));
    });

    test('the message says what to do', () {
      expect(const PlayerStuck().toString(), 'The player stopped responding. Close this preview and open it again.');
    });
  });

  test('video playback options: hardware decoding on, or off', () {
    expect(videoPlaybackOptions(hardwareDecoding: true), {'hwdec': 'auto-copy-safe'});
    expect(videoPlaybackOptions(hardwareDecoding: false), {'hwdec': 'no'});
  });
}
