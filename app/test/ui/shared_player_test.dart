import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/ui/preview/shared_player.dart';

/// A stand-in for the player: records what's sent and answers `idle-active` and
/// `path` the way mpv would.
class FakeMpv {
  final calls = <String>[];
  String? path;
  bool fail = false;
  bool neverIdle = false;

  SharedPlayer player({Duration timeout = const Duration(seconds: 2)}) => SharedPlayer(
    command: (command) async {
      if (fail) {
        throw StateError('mpv gone');
      }
      calls.add(command.join(' '));
      if (command.first == 'loadfile') {
        path = command[1];
      }
    },
    pause: () async => calls.add('pause'),
    stop: () async {
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
    timeout: timeout,
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
}
