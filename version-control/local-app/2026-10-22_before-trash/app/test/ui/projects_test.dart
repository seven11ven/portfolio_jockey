import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';

import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

void main() {
  /// Starts unlocked with one project, "Kitchen Remodel", and returns its ID.
  Future<(TestApp, String)> withProject(WidgetTester tester, {List<String> tags = const []}) async {
    final app = await startApp(tester, unlocked: true);
    late String id;
    await tester.runAsync(() async {
      id = await app.controller.projects.createProject(name: 'Kitchen Remodel', description: 'Quotes and photos.');
      if (tags.isNotEmpty) {
        await app.controller.projects.applyTagChanges(id, TagChanges(added: tags));
      }
    });
    // Reopen home so it lists the project.
    app.controller.lock();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Kitchen Remodel'));
    return (app, id);
  }

  Future<void> openProjectMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('Rename: Cancel writes nothing, Confirm renames', (tester) async {
    final (app, _) = await withProject(tester);
    final before = await snapshot(tester, app.storage);

    await openProjectMenu(tester);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(filledButton(tester, 'Confirm rename').onPressed, isNull);
    await tester.enterText(find.byKey(const Key('new-name')), 'Kitchen & Dining Remodel');
    await tester.pump();
    expect(find.textContaining('“Kitchen Remodel” ', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await openProjectMenu(tester);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-name')), 'Kitchen & Dining Remodel');
    await tester.pump();
    await tester.tap(find.text('Confirm rename'));
    await settleUntil(tester, find.text('Kitchen & Dining Remodel'));
    expect(find.text('Kitchen & Dining Remodel'), findsOneWidget);
  });

  testWidgets('Delete project stays disabled until the exact name is typed', (tester) async {
    final (app, id) = await withProject(tester);
    final before = await snapshot(tester, app.storage);

    await openProjectMenu(tester);
    await tester.tap(find.text('Delete project…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Kitchen Remodel”?'), findsOneWidget);
    bool canDelete() => filledButton(tester, 'Delete project').onPressed != null;
    expect(canDelete(), isFalse);

    await tester.enterText(find.byKey(const Key('confirm-name')), 'kitchen remodel');
    await tester.pump();
    expect(canDelete(), isFalse);
    await tester.enterText(find.byKey(const Key('confirm-name')), 'Kitchen Remodel');
    await tester.pump();
    expect(canDelete(), isTrue);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await openProjectMenu(tester);
    await tester.tap(find.text('Delete project…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('confirm-name')), 'Kitchen Remodel');
    await tester.pump();
    await tester.tap(find.text('Delete project'));
    await settleUntilGone(tester, find.text('Kitchen Remodel'));
    expect(find.text('Kitchen Remodel'), findsNothing);
    await tester.runAsync(() async => expect(await Directory('${app.storage.path}/$id').exists(), isFalse));
  });

  testWidgets('New project: Cancel writes nothing', (tester) async {
    final app = await startApp(tester, unlocked: true);
    final before = await snapshot(tester, app.storage);
    await tester.tap(find.text('New project').first);
    await tester.pumpAndSettle();
    expect(filledButton(tester, 'Create project').onPressed, isNull);
    await tester.enterText(find.byKey(const Key('project-name')), 'Wedding Album');
    await tester.pump();
    expect(filledButton(tester, 'Create project').onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);
  });

  testWidgets('Add files: Cancel writes nothing; Confirm encrypts the picked files', (tester) async {
    final (app, _) = await withProject(tester, tags: ['Photos', 'Receipts']);
    late Directory originals;
    await tester.runAsync(() async {
      originals = await tempFolder();
      await File('${originals.path}/tile-samples.jpg').writeAsString('jpg bytes');
      await File('${originals.path}/invoice-oct.pdf').writeAsString('pdf bytes');
    });
    app.picker.files = ['${originals.path}/tile-samples.jpg', '${originals.path}/invoice-oct.pdf'];

    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('Add files'));
    final before = await snapshot(tester, app.storage);

    await tester.tap(find.text('Add files'));
    await settleUntil(tester, find.text('Add 2 files to “Kitchen Remodel”?'));
    expect(find.text('tile-samples.jpg'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await tester.tap(find.text('Add files'));
    await settleUntil(tester, find.text('Add 2 files to “Kitchen Remodel”?'));
    await tester.tap(find.text('Photos').last);
    await tester.pump();
    await tester.tap(find.text('Encrypt and add 2 files'));
    await settleUntil(tester, find.text('All 2'));
    expect(find.text('tile-samples.jpg'), findsOneWidget);
    expect(find.text('Photos 2'), findsOneWidget);
    await tester.runAsync(() async => expect(await File('${originals.path}/tile-samples.jpg').exists(), isTrue));
  });

  testWidgets('Delete from device is greyed out when the original is gone', (tester) async {
    final (app, id) = await withProject(tester);
    late String path;
    await tester.runAsync(() async {
      final originals = await tempFolder();
      path = '${originals.path}/countertop-before.jpg';
      await File(path).writeAsString('photo');
      await app.controller.projects.addFiles(id, [path]);
      await File(path).delete();
    });

    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('countertop-before.jpg'));
    await tester.tap(find.text('countertop-before.jpg'), buttons: kSecondaryButton);
    await settleUntil(tester, find.text('Delete from project'));

    PopupMenuItem<Object?> item(String label) =>
        tester.widget<PopupMenuItem<Object?>>(find.ancestor(of: find.text(label), matching: find.byType(PopupMenuItem<VoidCallback>)));
    expect(item('Delete from device').enabled, isFalse);
    expect(item('Delete from both').enabled, isFalse);
    expect(item('Delete from project').enabled, isTrue);
    expect(find.text('The original is no longer at $path, so only the project copy can be deleted.'), findsOneWidget);
  });

  testWidgets('The tag review lists exactly the pending changes, and Back changes nothing', (tester) async {
    final (app, _) = await withProject(tester, tags: ['Photos', 'Receipts', 'Plans']);
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('Manage tags'));
    final before = await snapshot(tester, app.storage);

    await tester.tap(find.text('Manage tags'));
    await tester.pumpAndSettle();
    expect(filledButton(tester, 'Review changes…').onPressed, isNull);

    await tester.tap(find.byTooltip('Delete tag').at(2)); // Plans
    await tester.enterText(find.byKey(const Key('new-tag')), 'Permits');
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Review changes…'));
    await tester.pumpAndSettle();

    expect(find.text('Save these tag changes?'), findsOneWidget);
    expect(find.text('Add “Permits”'), findsOneWidget);
    expect(find.text('Remove “Plans”'), findsOneWidget);
    expect(find.textContaining('Rename'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);
  });
}
