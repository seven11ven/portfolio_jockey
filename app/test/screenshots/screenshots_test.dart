// Renders every phase 5 screen to PNG for the project manager to compare with
// the approved mockups. The container has no display, so this is how the UI
// can be seen. Skipped unless SCREENSHOT_DIR is set; the PNGs aren't committed.
//
//   SCREENSHOT_DIR=/some/folder flutter test test/screenshots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';

import '../ui/ui_helpers.dart';
import '../vault/test_helpers.dart';

final String? _outDir = Platform.environment['SCREENSHOT_DIR'];
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  final fonts = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter'}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async => ByteData.sublistView(await File('$fonts/$name').readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(font('Roboto-Regular.ttf'))
        ..addFont(font('Roboto-Medium.ttf'))
        ..addFont(font('Roboto-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(font('MaterialIcons-Regular.otf'))).load();
  // A real desktop resolves 'monospace' through fontconfig; the test renderer can't.
  await (FontLoader('monospace')..addFont(font('Roboto-Regular.ttf'))).load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_outDir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
}

Widget _wrap(Widget app) => RepaintBoundary(key: _boundary, child: app);

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (_outDir != null) {
      await Directory(_outDir!).create(recursive: true);
      await _loadFonts();
    }
  });

  for (final brightness in Brightness.values) {
    final theme = brightness.name;

    testWidgets('first run and unlock ($theme)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await startApp(tester, wrap: _wrap, size: const Size(1280, 1000));
      await tester.tap(find.text('Change…'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse battery');
      await tester.enterText(find.byKey(const Key('confirm')), 'correct horse battery');
      await tester.tap(find.byKey(const Key('understood')));
      await _shot(tester, '01-first-run-$theme');

      await tester.ensureVisible(find.text('Create vault'));
      await tester.tap(find.text('Create vault'));
      await settleUntil(tester, find.text('Projects'));
      await tester.tap(find.byTooltip('Lock'));
      await settle(tester);
      await _shot(tester, '02-unlock-$theme');

      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'wrong guess');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.textContaining("didn't unlock"));
      await _shot(tester, '03-unlock-wrong-$theme');
    }, skip: _outDir == null);

    testWidgets('home, project and tags ($theme)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = await startApp(tester, unlocked: true, wrap: _wrap);
      final service = app.controller.projects;
      late String kitchen;
      late String missingOriginal;
      await tester.runAsync(() async {
        final originals = await tempFolder();
        Future<String> make(String name, int size) async {
          final file = File('${originals.path}/$name');
          await file.writeAsBytes(List.filled(size, 7));
          return file.path;
        }

        for (final (name, description) in [
          ('Bike Restoration', 'Parts list and progress photos.'),
          ('Garden Planner', 'Bed layouts and seed receipts.'),
          ('Thesis Research', 'Papers, interview audio and chapter drafts.'),
          ('Album Artwork', 'Cover drafts and reference images for the EP.'),
        ]) {
          await service.createProject(name: name, description: description);
        }
        kitchen = await service.createProject(name: 'Kitchen Remodel', description: 'Contractor quotes, receipts and before/after photos.');
        await service.applyTagChanges(kitchen, TagChanges(added: ['Photos', 'Receipts', 'Plans', 'Inspiration']));
        final files = [
          ('countertop-before.jpg', ['Photos']),
          ('countertop-after.jpg', ['Photos', 'Inspiration']),
          ('contractor-quote.pdf', ['Receipts', 'Plans']),
          ('walkthrough.mp4', ['Photos']),
          ('plumber-voicemail.m4a', <String>[]),
          ('measurements.txt', ['Plans']),
        ];
        for (final (name, tags) in files) {
          final added = await service.addFiles(kitchen, [await make(name, 40000 + name.length * 1000)]);
          await service.setFileTags(kitchen, {added.added.single.id: tags});
          if (name == 'countertop-before.jpg') {
            missingOriginal = added.added.single.originalPath!;
          }
        }
        await File(missingOriginal).delete();
        app.picker.files = [await make('tile-samples.jpg', 4200000), await make('invoice-oct.pdf', 310000), await make('demo-day.mp4', 1860000)];
      });

      // Reload home so it shows the projects.
      app.controller.lock();
      await settle(tester);
      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.text('Kitchen Remodel'));
      await _shot(tester, '04-home-$theme');

      await tester.tap(find.text('New project').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('project-name')), 'Wedding Album');
      await _shot(tester, '05-new-project-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Project actions').first);
      await _shot(tester, '06-project-menu-$theme');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-name')), 'Kitchen & Dining Remodel');
      await _shot(tester, '07-rename-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Project actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete project…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('confirm-name')), 'Kitchen Remodel');
      await _shot(tester, '08-delete-project-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kitchen Remodel'));
      await settleUntil(tester, find.text('contractor-quote.pdf'));
      await _shot(tester, '09-project-$theme');

      await tester.tap(find.text('Add files'));
      await settleUntil(tester, find.text('Add 3 files to “Kitchen Remodel”?'));
      await settleUntil(tester, find.text('4.2 MB'));
      await tester.tap(find.text('Photos').last);
      await _shot(tester, '10-add-files-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('contractor-quote.pdf'), buttons: kSecondaryButton);
      await settleUntil(tester, find.text('Trash original, delete copy'));
      await tester.pumpAndSettle();
      await _shot(tester, '11-file-menu-$theme');
      for (final (label, name) in [('Move to Trash', '12a-trash-original'), ('Delete from project', '12b-delete-from-project'), ('Trash original, delete copy', '12c-trash-and-delete')]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        await _shot(tester, '$name-$theme');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        if (label != 'Trash original, delete copy') {
          await tester.tap(find.text('contractor-quote.pdf'), buttons: kSecondaryButton);
          await settleUntil(tester, find.text('Trash original, delete copy'));
          await tester.pumpAndSettle(); // Menus ignore taps until their opening animation ends.
        }
      }

      await tester.tap(find.text('countertop-before.jpg'), buttons: kSecondaryButton);
      await settleUntil(tester, find.text('Trash original, delete copy'));
      await _shot(tester, '13-original-missing-$theme');
      await _escape(tester);

      await tester.tap(find.text('Manage tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename').at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Receipts & Invoices');
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete tag').at(3));
      await tester.enterText(find.byKey(const Key('new-tag')), 'Permits');
      await tester.tap(find.text('Add'));
      await _shot(tester, '14-manage-tags-$theme');
      await tester.tap(find.text('Review changes…'));
      await _shot(tester, '15-review-tags-$theme');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('contractor-quote.pdf'), buttons: kSecondaryButton);
      await settleUntil(tester, find.text('Edit tags…'));
      await tester.tap(find.text('Edit tags…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos').last);
      await _shot(tester, '16-edit-tags-$theme');
    }, skip: _outDir == null);
  }
}
