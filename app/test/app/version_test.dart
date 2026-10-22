import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/version.dart';

void main() {
  test('appVersion and appBuild match pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.substring('version:'.length).trim(), '$appVersion+$appBuild');
  });
}
