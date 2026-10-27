import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/portal.dart';

void main() {
  test('both portal requests are valid (sha{sv}) arguments for GLib', () {
    expect(OpenUriPortal.checkArguments(OpenUriPortal.openFileArguments), isNull);
    expect(OpenUriPortal.checkArguments(OpenUriPortal.openDirectoryArguments), isNull);
  });

  test('"Edit in another app" always asks and lets the editor save', () {
    expect(OpenUriPortal.openFileArguments, contains("'ask': <true>"));
    expect(OpenUriPortal.openFileArguments, contains("'writable': <true>"));
  });

  test('a malformed request is caught by the same check', () {
    expect(OpenUriPortal.checkArguments("('', 'not a handle', {})"), isNotNull, reason: 'a string is not a handle');
  });
}
