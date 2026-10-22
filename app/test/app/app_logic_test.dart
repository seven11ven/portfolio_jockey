import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/app/passphrase_rules.dart';
import 'package:portfolio_jockey/ui/common.dart';

void main() {
  group('passphrase strength', () {
    test('anything under 12 characters is too short', () {
      expect(passphraseStrength(''), 0);
      expect(passphraseStrength('Short1!'), 0);
      expect(passphraseStrength('elevenchars'), 0);
    });

    test('12 characters is the minimum, and longer or mixed is stronger', () {
      expect(passphraseStrength('twelvechars!'), 1);
      expect(passphraseStrength('correct horse battery'), 3);
      expect(passphraseStrength('correct horse battery staple'), 4);
      expect(passphraseStrength('Abcdefghijk1'), 2);
    });

    test('characters are counted, not bytes', () {
      expect(passphraseStrength('ééééééééééé'), 0); // 11 characters, 22 bytes.
    });
  });

  group('unlock delay', () {
    test('doubles from 1 second up to 30', () {
      expect([for (var i = 0; i <= 7; i++) UnlockBackoff.delayAfter(i).inSeconds], [0, 1, 2, 4, 8, 16, 30, 30]);
    });

    test('counts down from the failure and resets on success', () {
      var now = DateTime(2026, 10, 22, 12);
      final backoff = UnlockBackoff(clock: () => now);
      expect(backoff.remaining, Duration.zero);

      backoff
        ..recordFailure()
        ..recordFailure();
      expect(backoff.remaining, const Duration(seconds: 2));
      now = now.add(const Duration(milliseconds: 1500));
      expect(backoff.remaining, const Duration(milliseconds: 500));
      now = now.add(const Duration(seconds: 1));
      expect(backoff.remaining, Duration.zero);

      backoff.reset();
      expect(backoff.failures, 0);
    });
  });

  group('formatting', () {
    test('sizes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(310000), '310 KB');
      expect(formatBytes(4200000), '4.2 MB');
      expect(formatBytes(186000000), '186 MB');
    });

    test('change dates', () {
      final now = DateTime(2026, 10, 22, 15);
      expect(formatChanged(DateTime(2026, 10, 22, 1), now: now), 'Changed today');
      expect(formatChanged(DateTime(2026, 10, 21, 23), now: now), 'Changed yesterday');
      expect(formatChanged(DateTime(2026, 10, 19), now: now), 'Changed Oct 19');
      expect(formatChanged(DateTime(2025, 3, 2), now: now), 'Changed Mar 2, 2025');
    });
  });
}
