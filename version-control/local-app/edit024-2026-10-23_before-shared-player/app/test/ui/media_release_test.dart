import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/ui/preview/preview_views.dart';

void main() {
  test('pauses, turns video off, then waits until mpv has closed its video output', () async {
    final calls = <String>[];
    var polls = 0;
    await stopVideoOutput(
      (property, value) async => calls.add('$property=$value'),
      (property) async {
        calls.add('get $property');
        return ++polls < 3 ? 'yes' : 'no';
      },
      interval: Duration.zero,
    );
    expect(calls, ['pause=yes', 'vid=no', 'get vo-configured', 'get vo-configured', 'get vo-configured']);
  });

  test('audio only: the output is already closed, so it returns at once', () async {
    var polls = 0;
    await stopVideoOutput((_, _) async {}, (_) async {
      polls++;
      return 'no';
    });
    expect(polls, 1);
  });

  test('gives up after the time limit instead of hanging', () async {
    final watch = Stopwatch()..start();
    await stopVideoOutput((_, _) async {}, (_) async => 'yes', timeout: const Duration(milliseconds: 100), interval: const Duration(milliseconds: 10));
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('an mpv error is swallowed, so disposing the player still happens', () async {
    await expectLater(stopVideoOutput((_, _) async => throw StateError('mpv gone'), (_) async => 'no'), completes);
    await expectLater(stopVideoOutput((_, _) async {}, (_) async => throw StateError('mpv gone')), completes);
  });
}
