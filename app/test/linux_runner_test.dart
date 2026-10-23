import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // libmpv refuses to start unless LC_NUMERIC is "C", and GTK's startup sets it
  // from the environment. Tests run without GTK, so audio and video can't catch
  // a missing reset; this checks the runner keeps it, after GTK's startup.
  test('the Linux runner resets LC_NUMERIC to "C" after GTK starts, for libmpv', () {
    final code = File('linux/runner/my_application.cc').readAsStringSync();
    final startup = code.indexOf('G_APPLICATION_CLASS(my_application_parent_class)->startup(application);');
    final reset = code.indexOf('setlocale(LC_NUMERIC, "C");');
    expect(startup, isNonNegative);
    expect(reset, greaterThan(startup));
    final startupFunction = code.substring(code.indexOf('static void my_application_startup('));
    expect(startupFunction.indexOf('setlocale(LC_NUMERIC, "C");'), lessThan(startupFunction.indexOf('\n}\n')), reason: 'the reset must be inside my_application_startup');
  });
}
