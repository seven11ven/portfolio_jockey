import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

void main() {
  /// Records what the app puts on the clipboard.
  List<String> captureClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  EditableText editable(WidgetTester tester, String key) =>
      tester.widget<EditableText>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)));

  Future<void> copyAll(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('The eye button shows and hides a passphrase; copying follows the setting', (tester) async {
    final app = await startApp(tester);
    final copied = captureClipboard(tester);
    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse battery');
    await tester.pump();
    expect(editable(tester, 'passphrase').obscureText, isTrue, reason: 'hidden by default');

    await tester.tap(find.descendant(of: find.byKey(const Key('passphrase')), matching: find.byTooltip('Show passphrase')));
    await tester.pump();
    expect(editable(tester, 'passphrase').obscureText, isFalse);
    expect(find.byTooltip('Hide passphrase'), findsOneWidget);

    // Allowed by default (PM decision): Ctrl+C copies the shown passphrase.
    expect(app.controller.allowPassphraseCopy, isTrue);
    await copyAll(tester, 'passphrase');
    expect(copied, ['correct horse battery']);

    // Turned off: Ctrl+C copies nothing.
    await tester.runAsync(() => app.controller.setAllowPassphraseCopy(false));
    await tester.pump();
    copied.clear();
    await copyAll(tester, 'passphrase');
    expect(copied, isEmpty);
    final saved = jsonDecode((await tester.runAsync(() => File('${app.config.path}/settings.json').readAsString()))!) as Map<String, Object?>;
    expect(saved['allowPassphraseCopy'], isFalse);
  });

  testWidgets('Settings has the "Allow copying passphrases" switch, on by default', (tester) async {
    final app = await startApp(tester, unlocked: true);
    await tester.tap(find.byTooltip('Settings'));
    await settleUntil(tester, find.text('Allow copying passphrases'));
    expect(tester.widget<Switch>(find.byKey(const Key('allow-copy'))).value, isTrue);
    await tester.ensureVisible(find.byKey(const Key('allow-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allow-copy')));
    await settle(tester);
    expect(app.controller.allowPassphraseCopy, isFalse);
    expect(tester.widget<Switch>(find.byKey(const Key('allow-copy'))).value, isFalse);
  });

  testWidgets("Inside a Flatpak: storage defaults to the app's data folder", (tester) async {
    await startApp(tester, sandboxed: true);
    final data = Platform.environment['XDG_DATA_HOME'] ?? '${Platform.environment['HOME']}/.local/share';
    expect(find.text('$data/Portfolio Jockey'), findsOneWidget);
    expect(find.textContaining("The app's own folder"), findsOneWidget);
  });

  testWidgets('Inside a Flatpak: export needs a chosen location first', (tester) async {
    final app = await startApp(tester, unlocked: true, sandboxed: true);
    await tester.runAsync(() async {
      final id = await app.controller.projects.createProject(name: 'Kitchen Remodel');
      final file = File('${(await tempFolder()).path}/notes.md')..writeAsStringSync('# Plan');
      await app.controller.projects.addFiles(id, [file.path]);
    });
    app.controller.lock();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Kitchen Remodel'));
    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as ZIP…'));
    await settleUntil(tester, find.text('No location chosen yet'));
    expect(find.textContaining('/Documents/'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('export-confirm-button'))).onPressed, isNull);

    late String out;
    await tester.runAsync(() async => out = (await tempFolder()).path);
    app.picker.saveLocation = '$out/Kitchen Remodel.zip';
    await tester.tap(find.text('Choose…'));
    await settle(tester);
    expect(find.text('$out/Kitchen Remodel.zip'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('export-confirm-button'))).onPressed, isNotNull);
  });
}
