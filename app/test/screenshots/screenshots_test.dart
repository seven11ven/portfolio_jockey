// Renders every phase 5 and 6 screen to PNG for the project manager to compare with
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
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/services/tag_changes.dart';

import '../ui/preview_test.dart' show sampleMarkdown;
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


/// A one-page PDF with a heading and a few lines of text (Helvetica).
List<int> _quotePdf() {
  const lines = ['Quote #2041', '', 'Countertops (quartz) ........ \$3,200', 'Labour ...................... \$1,450', 'Removal and disposal ........ \$380', '', 'Total ....................... \$5,030'];
  final text = StringBuffer('BT /F1 22 Tf 60 760 Td (ACME Renovations) Tj /F1 12 Tf 0 -34 Td 16 TL ');
  for (final line in lines) {
    text.write('($line) Tj T* ');
  }
  text.write('ET');
  final content = text.toString();
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toString().codeUnits;
}

/// A 1200 × 800 PNG: a countertop-like gradient with a few shapes.
Future<List<int>> _photoPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(1200, 800);
  canvas
    ..drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(1200, 800), [const Color(0xFFE7E1D6), const Color(0xFF9C8F7C)]))
    ..drawRect(const Rect.fromLTWH(0, 520, 1200, 280), Paint()..color = const Color(0xFF3F3A36))
    ..drawRect(const Rect.fromLTWH(0, 500, 1200, 30), Paint()..color = const Color(0xFFF4F1EC))
    ..drawCircle(const Offset(860, 250), 120, Paint()..color = const Color(0x55FFFFFF));
  final image = await recorder.endRecording().toImage(1200, 800);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
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

    testWidgets('preview and edit ($theme)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final launcher = FakeLauncher(
        apps: const [
          InstalledApp(id: 'org.gnome.TextEditor.desktop', name: 'Text Editor', isDefault: true),
          InstalledApp(id: 'libreoffice-writer.desktop', name: 'LibreOffice Writer', isDefault: false),
        ],
      );
      final app = await startApp(tester, unlocked: true, wrap: _wrap, launcher: launcher);
      final service = app.controller.projects;
      late String kitchen;
      await tester.runAsync(() async {
        final originals = await tempFolder();
        Future<String> make(String name, List<int> bytes) async {
          final file = File('${originals.path}/$name');
          await file.writeAsBytes(bytes);
          return file.path;
        }

        kitchen = await service.createProject(name: 'Kitchen Remodel', description: 'Contractor quotes, receipts and before/after photos.');
        await service.applyTagChanges(kitchen, TagChanges(added: ['Photos', 'Inspiration', 'Receipts', 'Plans']));
        for (final (name, bytes, tags) in [
          ('countertop-after.png', await _photoPng(), ['Photos', 'Inspiration']),
          ('contractor-quote.pdf', _quotePdf(), ['Receipts', 'Plans']),
          ('notes.md', sampleMarkdown.codeUnits, <String>[]),
          ('measurements.txt', 'Counter: 240 cm\nIsland: 180 x 90 cm\nSink cut-out: 76 cm\n'.codeUnits, ['Plans']),
        ]) {
          final added = await service.addFiles(kitchen, [await make(name, bytes)]);
          await service.setFileTags(kitchen, {added.added.single.id: tags});
        }
      });
      app.controller.lock();
      await settle(tester);
      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.text('Kitchen Remodel'));
      await tester.tap(find.text('Kitchen Remodel'));
      await settleUntil(tester, find.text('countertop-after.png'));

      await tester.tap(find.text('countertop-after.png'));
      await settleUntil(tester, find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview'));
      await settleUntil(tester, find.textContaining('1200 × 800'));
      await _shot(tester, '17-preview-image-$theme');
      await tester.tap(find.byTooltip('Next file'));
      await settleUntil(tester, find.text('Page 1 of 1'));
      await settle(tester);
      await _shot(tester, '18-preview-pdf-$theme');
      await tester.tap(find.byTooltip('Next file'));
      await settleUntil(tester, find.text('Kitchen plan'));
      await _shot(tester, '19-preview-markdown-$theme');
      await tester.tap(find.byTooltip('Next file'));
      await settleUntil(tester, find.textContaining('Island'));
      await _shot(tester, '20-preview-text-$theme');

      await tester.tap(find.text('Edit in another app…').last);
      await settleUntil(tester, find.text('LibreOffice Writer'));
      await _shot(tester, '21-edit-in-$theme');
      await tester.tap(find.text('Decrypt and open'));
      await settleUntil(tester, find.textContaining('Editing measurements.txt'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _shot(tester, '22-editing-banner-$theme');

      await tester.runAsync(() => File(launcher.opened.single.$1).writeAsString('Counter: 245 cm\nIsland: 180 x 90 cm\nSink cut-out: 76 cm\nHob: 60 cm\n'));
      await tester.tap(find.text('Save changes'));
      await settleUntil(tester, find.textContaining('is encrypted and replaces'));
      await _shot(tester, '23-save-changes-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await _shot(tester, '24-discard-$theme');
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      await _shot(tester, '25-lock-while-editing-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }, skip: _outDir == null);

    testWidgets('edit inside a Flatpak, leftovers and refusals ($theme)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      late PrivateFolders folders;
      late PrivateFolders disk;
      await tester.runAsync(() async {
        folders = await fakePrivateFolders();
        disk = await fakePrivateFolders(type: 'ext4');
      });
      final app = await startApp(tester, unlocked: true, wrap: _wrap, launcher: FakeLauncher(usesDesktopChooser: true), privateFolders: folders);
      final service = app.controller.projects;
      late String kitchen;
      await tester.runAsync(() async {
        kitchen = await service.createProject(name: 'Kitchen Remodel', description: 'Contractor quotes, receipts and before/after photos.');
        final file = File('${(await tempFolder()).path}/measurements.txt');
        await file.writeAsString('Counter: 240 cm');
        await service.addFiles(kitchen, [file.path]);
        final entry = (await service.readProject(kitchen)).files.single;
        // An edit left by a crash.
        final crashed = EditSessions(folders: folders, launcher: FakeLauncher());
        await (await crashed.start(service: service, projectId: kitchen, projectName: 'Kitchen Remodel', file: entry)).copy.writeAsString('edited');
        crashed.dispose();
      });
      app.controller.lock();
      await settle(tester);
      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.text("An edit wasn't finished"));
      await _shot(tester, '26-unfinished-edit-$theme');
      await tester.tap(find.text('Discard'));
      await settleUntil(tester, find.text('Discard changes'));
      await tester.tap(find.text('Discard changes'));
      await settleUntilGone(tester, find.textContaining('Discard your changes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kitchen Remodel'));
      await settleUntil(tester, find.text('measurements.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('measurements.txt'));
      await settleUntil(tester, find.text('Edit in another app…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit in another app…'));
      await settleUntil(tester, find.text('Decrypt and open'));
      await _shot(tester, '27-edit-in-flatpak-$theme');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No memory-only folder: a second app whose folders aren't tmpfs.
      await tester.pumpWidget(_wrap(const SizedBox()));
      final refusing = await startApp(tester, unlocked: true, wrap: _wrap, privateFolders: disk);
      late String id;
      await tester.runAsync(() async {
        id = await refusing.controller.projects.createProject(name: 'Kitchen Remodel');
        final file = File('${(await tempFolder()).path}/measurements.txt');
        await file.writeAsString('x');
        await refusing.controller.projects.addFiles(id, [file.path]);
      });
      refusing.controller.lock();
      await settle(tester);
      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.text('Kitchen Remodel'));
      await tester.tap(find.text('Kitchen Remodel'));
      await settleUntil(tester, find.text('measurements.txt'));
      await tester.tap(find.text('measurements.txt'));
      await settleUntil(tester, find.text('Edit in another app…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit in another app…'));
      await settleUntil(tester, find.text('Decrypt and open'));
      await tester.tap(find.text('Decrypt and open'));
      await settleUntil(tester, find.text("Can't open measurements.txt"));
      await _shot(tester, '28-no-private-folder-$theme');
    }, skip: _outDir == null);
  }
}
