import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/services/storage_move.dart';

import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

void main() {
  Future<TestApp> withProject(WidgetTester tester) async {
    final app = await startApp(tester, unlocked: true);
    await tester.runAsync(() async {
      final id = await app.controller.projects.createProject(name: 'Kitchen Remodel');
      final file = File('${(await tempFolder()).path}/measurements.txt')..writeAsStringSync('Counter: 240 cm');
      await app.controller.projects.addFiles(id, [file.path]);
    });
    app.controller.lock();
    await settle(tester);
    await unlock(tester, 'test passphrase');
    return app;
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await settleUntil(tester, find.textContaining('1 project ·'));
  }

  Map<String, Object?> savedSettings(TestApp app) => jsonDecode(File('${app.config.path}/settings.json').readAsStringSync()) as Map<String, Object?>;

  testWidgets('Color scheme: mode and accent apply at once and are saved', (tester) async {
    final app = await withProject(tester);
    await openSettings(tester);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('None. This app never connects to the internet.'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    await tester.tap(find.byKey(const Key('accent-teal')));
    await settle(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme.primary, PjAccent.teal.light);
    final saved = (await tester.runAsync(() async => savedSettings(app)))!;
    expect(saved['themeMode'], 'dark');
    expect(saved['accent'], 'teal');
    expect(saved['storagePath'], app.storage.path, reason: 'the storage path is kept');
  });

  testWidgets('Video playback: hardware decoding is saved and survives a restart', (tester) async {
    final app = await withProject(tester);
    expect(app.controller.hardwareDecoding, isTrue, reason: 'on by default');
    await openSettings(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('hwdec')), 200);
    await settle(tester);
    await tester.tap(find.byKey(const Key('hwdec')));
    await settle(tester);
    expect(app.controller.hardwareDecoding, isFalse);
    final saved = (await tester.runAsync(() async => savedSettings(app)))!;
    expect(saved['hardwareDecoding'], false);
    final reloaded = (await tester.runAsync(() => app.controller.settingsStore.load()))!;
    expect(reloaded.hardwareDecoding, isFalse);
  });

  test('Hardware decoding: a missing or unknown value falls back to on', () {
    expect(AppSettings.fromJson({}).hardwareDecoding, isTrue);
    expect(AppSettings.fromJson({'hardwareDecoding': 'yes'}).hardwareDecoding, isTrue);
    expect(AppSettings.fromJson(const AppSettings(hardwareDecoding: false).toJson()).hardwareDecoding, isFalse);
  });

  testWidgets('Change passphrase: a wrong current one changes nothing; the new one unlocks', (tester) async {
    final app = await withProject(tester);
    await openSettings(tester);
    await tester.ensureVisible(find.text('Change…'));
    await settle(tester);
    await tester.tap(find.text('Change…'));
    await settleUntil(tester, find.text('Change passphrase'));
    await tester.enterText(find.byKey(const Key('current-passphrase')), 'not it');
    expect(find.byKey(const Key('confirm-new-passphrase')), findsNothing, reason: 'shown once the new passphrase is Fair');
    await tester.enterText(find.byKey(const Key('new-passphrase')), 'a much longer new passphrase');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('confirm-new-passphrase')), 'a much longer new passphrase');
    await tester.pump();
    final before = await snapshot(tester, app.storage);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm new passphrase'));
    await settleUntil(tester, find.textContaining('current passphrase is wrong'));
    expect(await snapshot(tester, app.storage), before);

    await tester.enterText(find.byKey(const Key('current-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm new passphrase'));
    await settleUntil(tester, find.text('Passphrase changed'));

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Lock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Lock'));
    await settleUntil(tester, find.byKey(const Key('unlock-passphrase')));
    await unlock(tester, 'test passphrase');
    expect(find.text('Kitchen Remodel'), findsNothing, reason: 'the old passphrase no longer works');
    await unlock(tester, 'a much longer new passphrase');
    expect(find.text('Kitchen Remodel'), findsOneWidget);
  });

  testWidgets('Move storage: Cancel writes nothing; Move copies, checks, switches and removes the old folder', (tester) async {
    final app = await withProject(tester);
    late Directory destination;
    await tester.runAsync(() async => destination = await tempFolder());
    app.picker.folder = destination.path;
    await openSettings(tester);

    await tester.tap(find.text('Move…'));
    await settleUntil(tester, find.text('Move all projects?'));
    expect(find.text(destination.path), findsOneWidget, reason: 'an empty folder is used as it is');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await tester.runAsync(() => destination.list().toList()), isEmpty);

    await tester.tap(find.text('Move…'));
    await settleUntil(tester, find.text('Move 1 project'));
    await tester.tap(find.text('Move 1 project'));
    // Copying, checking and syncing every folder takes a few rounds of real I/O.
    for (var i = 0; i < 3 && find.textContaining('Moved to').evaluate().isEmpty; i++) {
      await settleUntil(tester, find.textContaining('Moved to'));
    }
    expect(app.controller.storagePath, (await tester.runAsync(destination.resolveSymbolicLinks))!);
    expect(await tester.runAsync(app.storage.exists), isFalse);
    expect((await tester.runAsync(() async => savedSettings(app)))!['storagePath'], app.controller.storagePath);

    // The vault works from the new place, now and after locking.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('measurements.txt'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lock'));
    await settleUntil(tester, find.byKey(const Key('unlock-passphrase')));
    await unlock(tester, 'test passphrase');
    expect(find.text('Kitchen Remodel'), findsOneWidget);
  });

  testWidgets('Move storage into its own folder is refused', (tester) async {
    final app = await withProject(tester);
    final inside = Directory('${app.storage.path}/inside');
    await tester.runAsync(inside.create);
    app.picker.folder = inside.path;
    await openSettings(tester);
    await tester.tap(find.text('Move…'));
    await settleUntil(tester, find.textContaining("Can't move there"));
    expect(find.textContaining("Can't move there"), findsOneWidget);
  });

  test('a copy that fails part-way is removed, and the old folder is untouched', () async {
    final source = await tempFolder();
    await File('${source.path}/a.enc').writeAsString('one');
    final locked = File('${source.path}/b/c.enc');
    await locked.create(recursive: true);
    await locked.writeAsString('two');
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['644', locked.path]));
    final picked = await tempFolder();
    await File('${picked.path}/someone-else.txt').writeAsString('not ours');

    final move = await StorageMove.plan(source, picked);
    expect(move.target.path, endsWith('/Portfolio Jockey'), reason: 'a non-empty folder gets a new subfolder');
    await expectLater(move.copyAndVerify(), throwsA(isA<FileSystemException>()));
    expect(await move.target.exists(), isFalse);
    expect(await File('${picked.path}/someone-else.txt').readAsString(), 'not ours');
    expect(await File('${source.path}/a.enc').readAsString(), 'one');
  });
  testWidgets('Temporary files: Clear asks first, then clears', (tester) async {
    final app = await startApp(tester, unlocked: true);
    late File media;
    await tester.runAsync(() async {
      final folder = await app.controller.edits.folders.create('view');
      media = File('${folder.path}/clip.mp4');
      await media.writeAsString('readable');
    });
    await tester.tap(find.byTooltip('Settings'));
    await settleUntil(tester, find.text('Temporary files'));
    await tester.ensureVisible(find.text('Clear…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear…'));
    await settleUntil(tester, find.text('Clear temporary files?'));
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await tester.runAsync(media.exists), isTrue);

    await tester.tap(find.text('Clear…'));
    await settleUntil(tester, find.text('Clear temporary files?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await settleUntil(tester, find.text('Temporary files cleared.'));
    expect(await tester.runAsync(media.exists), isFalse);
  });

  testWidgets('Closing the window clears temporary files, but waits for an open edit', (tester) async {
    final app = await startApp(tester, unlocked: true);
    late File media;
    await tester.runAsync(() async {
      final folder = await app.controller.edits.folders.create('view');
      media = File('${folder.path}/clip.mp4');
      await media.writeAsString('readable');
    });
    expect(await tester.runAsync(app.controller.prepareToExit), isTrue);
    expect(await tester.runAsync(media.exists), isFalse);
  });
}

Future<void> unlock(WidgetTester tester, String passphrase) async {
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('unlock-passphrase')), passphrase);
  await tester.pump();
  await tester.tap(find.text('Unlock'));
  await settleUntil(tester, find.text('Kitchen Remodel'));
}
