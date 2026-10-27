import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/edit_session.dart';
import 'package:portfolio_jockey/services/private_folder.dart';
import 'package:portfolio_jockey/ui/preview/preview_views.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

import '../services/poppler_test.dart' show samplePdf;
import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

/// A 2 × 1 PNG.
final List<int> samplePng = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII=');

const String sampleMarkdown = '''
# Kitchen plan

Order quartz by **Nov 3**. See [the quote](https://example.com/quote).

![tiles](https://example.com/tiles.png)
![local](/etc/hostname)
''';

void main() {
  /// Starts unlocked with "Kitchen Remodel" holding [files] (name → bytes),
  /// and opens the project.
  Future<(TestApp, String)> withFiles(
    WidgetTester tester,
    Map<String, List<int>> files, {
    FakeLauncher? launcher,
    PrivateFolders? privateFolders,
  }) async {
    late PrivateFolders folders;
    await tester.runAsync(() async => folders = privateFolders ?? await fakePrivateFolders());
    final app = await startApp(tester, unlocked: true, launcher: launcher, privateFolders: folders);
    late String id;
    await tester.runAsync(() async {
      id = await app.controller.projects.createProject(name: 'Kitchen Remodel');
      final originals = await tempFolder();
      final paths = <String>[];
      for (final MapEntry(:key, :value) in files.entries) {
        final file = File('${originals.path}/$key');
        await file.writeAsBytes(value);
        paths.add(file.path);
      }
      await app.controller.projects.addFiles(id, paths);
    });
    app.controller.lock();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Kitchen Remodel'));
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text(files.keys.first));
    return (app, id);
  }

  Future<void> fileMenu(WidgetTester tester, String name, String item) async {
    await tester.tap(find.text(name).first, buttons: kSecondaryButton);
    await settleUntil(tester, find.text(item));
    await tester.tap(find.text(item));
    await settle(tester);
  }

  Future<FileEntry> entry(WidgetTester tester, TestApp app, String id, String name) async {
    late FileEntry file;
    await tester.runAsync(() async => file = (await app.controller.projects.readProject(id)).files.firstWhere((f) => f.name == name));
    return file;
  }

  testWidgets('Preview shows text and Markdown, with previous/next and details', (tester) async {
    await withFiles(tester, {'measurements.txt': utf8.encode('Counter: 240 cm'), 'notes.md': utf8.encode(sampleMarkdown)});

    await fileMenu(tester, 'measurements.txt', 'Preview');
    await settleUntil(tester, find.text('Counter: 240 cm'));
    expect(find.text('Counter: 240 cm'), findsOneWidget);
    expect(find.text('15 B'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed, isNull);

    await tester.tap(find.byTooltip('Next file'));
    await settleUntil(tester, find.text('Kitchen plan'));
    expect(find.text('Kitchen plan'), findsOneWidget);
    // Both images are replaced by the placeholder; no image is ever loaded.
    expect(find.text('Image not loaded: images in Markdown files are never fetched.'), findsNWidgets(2));
    expect(find.byWidgetPredicate((w) => w is Image), findsNothing);
    await tester.tap(find.textContaining('the quote', findRichText: true));
    await settle(tester);
    expect(find.text('Kitchen plan'), findsOneWidget, reason: 'links do nothing');
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
  });

  testWidgets('A single click on a file opens its preview at once; right-click opens the menu', (tester) async {
    final (_, _) = await withFiles(tester, {'notes.txt': utf8.encode('Hello')});
    await tester.tap(find.text('notes.txt').first);
    await settleUntil(tester, find.text('Hello'));
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Rename…'), findsNothing, reason: 'no menu on a left click');
  });

  testWidgets('Preview renders an image and a PDF from memory', (tester) async {
    await withFiles(tester, {'swatch.png': samplePng, 'quote.pdf': samplePdf(pages: 2)});

    await fileMenu(tester, 'swatch.png', 'Preview');
    await settleUntil(tester, find.textContaining('2 × 1'));
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.textContaining('2 × 1'), findsOneWidget);

    // The screen lists files by name, so quote.pdf comes before swatch.png.
    await tester.tap(find.byTooltip('Previous file'));
    await settleUntil(tester, find.text('Page 1 of 2'));
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settleUntil(tester, find.text('Page 2 of 2'));
    await tester.tap(find.byTooltip('Zoom in'));
    await settle(tester);
    expect(find.text('125%'), findsOneWidget);
  });

  testWidgets('Preview refuses files over the limit and unknown types', (tester) async {
    await withFiles(tester, {'archive.zip': [1, 2, 3]});
    await fileMenu(tester, 'archive.zip', 'Preview');
    await settleUntil(tester, find.textContaining("can't be previewed"));
    expect(find.textContaining("can't be previewed"), findsOneWidget);
  });

  testWidgets('Edit in another app: Cancel opens nothing; save after a change re-encrypts', (tester) async {
    final launcher = FakeLauncher();
    final (app, id) = await withFiles(tester, {'measurements.txt': utf8.encode('Counter: 240 cm')}, launcher: launcher);
    final before = await snapshot(tester, app.storage);

    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Text Editor'));
    expect(find.text('Edit measurements.txt in another app?'), findsOneWidget);
    expect(find.text('Default for this file type'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(launcher.opened, isEmpty);
    expect(await snapshot(tester, app.storage), before);

    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Text Editor'));
    await tester.tap(find.text('Decrypt and open'));
    await settleUntil(tester, find.textContaining('Editing measurements.txt in Text Editor.'));
    expect(launcher.opened.single.$2, 'org.example.Editor.desktop');
    expect(find.textContaining("couldn't open or save the file, choose Discard"), findsOneWidget);
    final copy = File(launcher.opened.single.$1);

    // Unchanged: nothing to save.
    await tester.tap(find.text('Save changes'));
    await settleUntil(tester, find.text('No changes to measurements.txt'));
    expect(find.textContaining('it may have saved to a different place'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.textContaining('Editing measurements.txt'), findsOneWidget);

    await tester.runAsync(() => copy.writeAsString('Counter: 245 cm, sink 60 cm'));
    await tester.tap(find.text('Save changes'));
    await settleUntil(tester, find.textContaining('is encrypted and replaces'));
    expect(find.text('Save your changes to measurements.txt?'), findsOneWidget);
    expect(find.textContaining('Close the file in the other app first.'), findsOneWidget);
    await tester.tap(find.text('Encrypt and replace'));
    await settleUntilGone(tester, find.textContaining('Editing measurements.txt'));
    expect(find.textContaining('Editing measurements.txt'), findsNothing);
    expect(await tester.runAsync(() => copy.parent.parent.exists()), isFalse);
    final saved = await entry(tester, app, id, 'measurements.txt');
    expect(saved.size, 27);
  });

  testWidgets('An empty edited copy is only saved after a second, explicit confirmation', (tester) async {
    final launcher = FakeLauncher();
    final (app, id) = await withFiles(tester, {'measurements.txt': utf8.encode('Counter: 240 cm')}, launcher: launcher);
    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Text Editor'));
    await tester.tap(find.text('Decrypt and open'));
    await settleUntil(tester, find.textContaining('Editing measurements.txt'));
    await tester.runAsync(() => File(launcher.opened.single.$1).writeAsString(''));

    await tester.tap(find.text('Save changes'));
    await settleUntil(tester, find.textContaining('is encrypted and replaces'));
    await tester.tap(find.text('Encrypt and replace'));
    await settleUntil(tester, find.text('Save the empty file'));
    expect(find.text('Save the empty file'), findsOneWidget);
    expect(find.textContaining('The edited copy is empty.', findRichText: true), findsOneWidget);
    expect((await entry(tester, app, id, 'measurements.txt')).size, 15, reason: 'nothing written yet');

    await tester.tap(find.text('Save the empty file'));
    await settleUntilGone(tester, find.textContaining('Editing measurements.txt'));
    expect((await entry(tester, app, id, 'measurements.txt')).size, 0);
  });

  testWidgets('Discard asks first; locking waits for the edit to finish', (tester) async {
    final (app, _) = await withFiles(tester, {'measurements.txt': utf8.encode('Counter: 240 cm')});
    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Text Editor'));
    await tester.tap(find.text('Decrypt and open'));
    await settleUntil(tester, find.textContaining('Editing measurements.txt'));

    await tester.tap(find.text('Discard'));
    await settleUntil(tester, find.text('Keep editing'));
    expect(find.text('Discard your changes to measurements.txt?'), findsOneWidget);
    expect(find.textContaining('Close the file in the other app first.'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(app.controller.edits.active, isNotNull);

    // Back home, the banner is still there, and Lock asks first.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settleUntil(tester, find.byTooltip('Lock'));
    expect(find.textContaining('Editing measurements.txt'), findsOneWidget);
    await tester.tap(find.byTooltip('Lock'));
    await settleUntil(tester, find.text('Finish editing before locking'));
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.byTooltip('Lock'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await settleUntil(tester, find.text('Discard…'));
    await tester.tap(find.text('Discard…'));
    await settleUntil(tester, find.text('Discard changes'));
    await tester.tap(find.text('Discard changes'));
    await settleUntil(tester, find.byKey(const Key('unlock-passphrase')));
    expect(app.controller.edits.active, isNull);
    expect(find.byKey(const Key('unlock-passphrase')), findsOneWidget);
  });

  testWidgets('An edit left by a crash is offered at unlock', (tester) async {
    late PrivateFolders folders;
    await tester.runAsync(() async => folders = await fakePrivateFolders());
    final (app, id) = await withFiles(tester, {'measurements.txt': utf8.encode('Counter: 240 cm')}, privateFolders: folders);
    final file = await entry(tester, app, id, 'measurements.txt');
    // A session from an earlier run that crashed: started, edited, never finished.
    await tester.runAsync(() async {
      final crashed = EditSessions(folders: folders, launcher: FakeLauncher());
      final session = await crashed.start(service: app.controller.projects, projectId: id, projectName: 'Kitchen Remodel', file: file);
      await session.copy.writeAsString('edited before the crash');
      crashed.dispose();
    });
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lock'));
    await settleUntil(tester, find.byKey(const Key('unlock-passphrase')));
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text("An edit wasn't finished"));
    expect(find.textContaining('in Kitchen Remodel'), findsOneWidget);

    await tester.tap(find.text('Save into project…'));
    await settleUntil(tester, find.textContaining('is encrypted and replaces'));
    await tester.tap(find.text('Encrypt and replace'));
    await settleUntilGone(tester, find.text('Save your changes to measurements.txt?'));
    expect(find.text("An edit wasn't finished"), findsNothing);
    final saved = await entry(tester, app, id, 'measurements.txt');
    late String text;
    await tester.runAsync(() async => text = utf8.decode(await app.controller.projects.readFile(id, saved, maxBytes: 100)));
    expect(text, 'edited before the crash');
    expect(await tester.runAsync(() => folders.existing('edit')), isEmpty);
  });

  testWidgets('No memory-only folder: the edit is refused and nothing is opened', (tester) async {
    late PrivateFolders disk;
    await tester.runAsync(() async => disk = await fakePrivateFolders(type: 'ext4'));
    final launcher = FakeLauncher();
    await withFiles(tester, {'measurements.txt': utf8.encode('x')}, launcher: launcher, privateFolders: disk);
    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Text Editor'));
    await tester.tap(find.text('Decrypt and open'));
    await settleUntil(tester, find.text("Can't open measurements.txt"));
    expect(find.textContaining("isn't in memory"), findsOneWidget);
    expect(launcher.opened, isEmpty);
    await tester.tap(find.text('OK'));
    await settle(tester);
  });

  testWidgets("Inside a Flatpak, the desktop's chooser picks the app", (tester) async {
    final launcher = FakeLauncher(usesDesktopChooser: true);
    await withFiles(tester, {'measurements.txt': utf8.encode('x')}, launcher: launcher);
    await fileMenu(tester, 'measurements.txt', 'Edit in another app…');
    await settleUntil(tester, find.text('Your desktop will ask which app to open it with.'));
    expect(find.textContaining('may keep its own history'), findsOneWidget);
    await tester.tap(find.text('Decrypt and open'));
    await settleUntil(tester, find.textContaining('Editing measurements.txt.'));
    expect(launcher.opened.single.$2, isNull);
  });

  group("Audio and video play in the desktop's player", () {
    List<Directory> viewFolders(PrivateFolders folders) {
      final root = Directory('${folders.runtimeDir}/${PrivateFolders.appFolderName}');
      return root.existsSync() ? [for (final e in root.listSync()) if (e is Directory && e.path.split('/').last.startsWith('view-')) e] : [];
    }

    testWidgets('nothing is decrypted before Play; Play hands a copy over; closing wipes it', (tester) async {
      final launcher = FakeLauncher();
      final folders = (await tester.runAsync(fakePrivateFolders))!;
      await withFiles(tester, {'walkthrough.mp4': List.filled(4000, 7)}, launcher: launcher, privateFolders: folders);
      await tester.tap(find.text('walkthrough.mp4').first);
      await settleUntil(tester, find.text("Plays in your desktop's video player."));
      expect(find.text('While it plays, other apps can read the readable copy. Closing this preview deletes it and stops playback.'), findsOneWidget);
      expect(viewFolders(folders), isEmpty, reason: 'no readable copy until Play');

      await tester.tap(find.byKey(const Key('media-play')));
      await settleUntil(tester, find.text('Play again'));
      expect(find.text("Playing in your desktop's video player."), findsOneWidget);
      final copy = File(launcher.viewed.single);
      expect(copy.readAsBytesSync(), List.filled(4000, 7));
      expect(viewFolders(folders), hasLength(1));

      await tester.tap(find.byKey(const Key('media-play')));
      await settleUntil(tester, find.text('Play again'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(launcher.viewed, [copy.path, copy.path], reason: 'Play again reuses the same copy');
      expect(viewFolders(folders), hasLength(1));

      await tester.tap(find.byTooltip('Back'));
      // The wipe runs as the preview is disposed, after the route's exit animation.
      for (var i = 0; i < 20 && copy.existsSync(); i++) {
        await settle(tester);
      }
      expect(find.text("Plays in your desktop's video player."), findsNothing, reason: 'the preview closed');
      expect(copy.existsSync(), isFalse);
      expect(viewFolders(folders), isEmpty, reason: 'closing the preview wipes the copy');
    });

    testWidgets('audio says audio player; a player that fails to open is reported', (tester) async {
      final launcher = FakeLauncher()..viewError = const FileSystemException("Couldn't open your desktop's player: no app for audio/mpeg");
      await withFiles(tester, {'voice-memo.mp3': List.filled(100, 1)}, launcher: launcher);
      await tester.tap(find.text('voice-memo.mp3').first);
      await settleUntil(tester, find.text("Plays in your desktop's audio player."));
      expect(find.descendant(of: find.byType(MediaHandoff), matching: find.byIcon(Icons.music_note_outlined)), findsOneWidget);
      await tester.tap(find.byKey(const Key('media-play')));
      await settleUntil(tester, find.textContaining('no app for audio/mpeg'));
      expect(find.text("Couldn't open your desktop's player: no app for audio/mpeg"), findsOneWidget);
    });
  });
}
