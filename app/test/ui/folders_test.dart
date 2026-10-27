import 'dart:io';

import 'package:archive/archive.dart' as reference;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/vault/project_index.dart';

import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

void main() {
  testWidgets('raster and SVG type labels are centered in the image cover', (tester) async {
    for (final (name, label) in [('photo.jpg', 'JPG'), ('drawing.svg', 'SVG')]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 120, height: 90, child: TypeBadge(fileName: name))))));
      final cover = tester.getRect(find.byKey(const Key('image-type-badge-cover')));
      final text = tester.getRect(find.text(label));
      expect(text.center.dx, closeTo(cover.center.dx, 0.1));
      expect(text.center.dy, closeTo(cover.center.dy, 0.1));
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    }
  });

  /// Starts unlocked with a project, "Kitchen Remodel", set up by [setup],
  /// and opens it. Its name then shows up three times: on the home screen
  /// underneath, in the path (see [crumb]), and as the app bar's title.
  Future<(TestApp, String)> openProject(WidgetTester tester, Future<void> Function(ProjectService service, String id) setup) async {
    final app = await startApp(tester, unlocked: true);
    late String id;
    await tester.runAsync(() async {
      id = await app.controller.projects.createProject(name: 'Kitchen Remodel');
      await setup(app.controller.projects, id);
    });
    app.controller.lock();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Kitchen Remodel'));
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('New folder'));
    return (app, id);
  }

  /// A part of the path above the files, on the screen that's showing.
  Finder crumb(String name) => find.descendant(of: find.byType(Scaffold).last, matching: find.text(name)).first;

  Future<String> source(String name, String text) async {
    final file = File('${(await tempFolder()).path}/$name')..writeAsStringSync(text);
    return file.path;
  }

  Future<void> addFile(ProjectService s, String id, String name, String text, {String? folderId, List<String> tags = const []}) async {
    await s.addFiles(id, [await source(name, text)], folderId: folderId, tags: tags, newTags: tags);
  }

  /// The names in the order the screen shows them: top to bottom, then left to right.
  List<String> order(WidgetTester tester, List<String> names) {
    final spot = {for (final n in names) n: tester.getTopLeft(find.text(n))};
    return names.toList()..sort((a, b) => spot[a]!.dy.round() != spot[b]!.dy.round() ? spot[a]!.dy.compareTo(spot[b]!.dy) : spot[a]!.dx.compareTo(spot[b]!.dx));
  }

  Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
    // Measured first: once dragging, the drag feedback is a second copy of the text.
    final start = tester.getCenter(from);
    final end = tester.getCenter(to);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, String text, String menuItem) async {
    await tester.tap(find.text(text).first, buttons: kSecondaryButton);
    await settleUntil(tester, find.text(menuItem));
    await tester.pumpAndSettle();
  }

  Future<ProjectIndex> readIndex(WidgetTester tester, TestApp app, String id) async {
    late ProjectIndex index;
    await tester.runAsync(() async => index = await app.controller.projects.readProject(id));
    return index;
  }

  testWidgets('New folder: Cancel writes nothing; names are checked as you type; Create adds it where the files are', (tester) async {
    final (app, id) = await openProject(tester, (s, id) async => s.createFolder(id, name: 'Invoices'));
    final before = await snapshot(tester, app.storage);

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    expect(find.text('It will be created in Kitchen Remodel.'), findsOneWidget);
    expect(filledButton(tester, 'Create folder').onPressed, isNull);
    await tester.enterText(find.byKey(const Key('folder-name')), 'invoices');
    await tester.pump();
    expect(find.textContaining('already exists here'), findsOneWidget);
    expect(filledButton(tester, 'Create folder').onPressed, isNull);
    await tester.enterText(find.byKey(const Key('folder-name')), 'a/b');
    await tester.pump();
    expect(find.text("A folder name can't contain a slash."), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder-name')), '  Plans ');
    await tester.pump();
    await tester.tap(find.text('Create folder'));
    await settleUntil(tester, find.text('Plans'));
    expect(find.text('Plans'), findsOneWidget);
    expect(find.text('0 files · 0 B'), findsNWidgets(2));
    expect((await readIndex(tester, app, id)).folders.map((f) => f.name), ['Invoices', 'Plans']);
  });

  testWidgets('Opening a folder: the path shows, files are added there, and the parent shows the totals', (tester) async {
    final (app, id) = await openProject(tester, (s, id) async => s.createFolder(id, name: 'Invoices'));
    await tester.tap(find.text('Invoices'));
    await settleUntil(tester, find.text('Add files here'));
    expect(find.text('This folder is empty'), findsOneWidget);

    final picked = await tester.runAsync(() => source('a.txt', 'hello'));
    app.picker.files = [picked!];
    await tester.tap(find.text('Add files here'));
    await settleUntil(tester, find.text('Add 1 file to “Kitchen Remodel / Invoices”?'));
    await tester.tap(find.text('Encrypt and add 1 file'));
    await settleUntilGone(tester, find.text('This folder is empty'));
    expect(find.text('a.txt'), findsOneWidget);
    expect((await readIndex(tester, app, id)).filesIn((await readIndex(tester, app, id)).folders.single.id).single.name, 'a.txt');

    await tester.tap(crumb('Kitchen Remodel'));
    await settleUntil(tester, find.text('Invoices'));
    expect(find.text('a.txt'), findsNothing, reason: 'the file is in the folder, not at the top');
    expect(find.text('1 file · 5 B'), findsOneWidget);
  });

  testWidgets('Search and tag chips look through the whole project, with each result\'s path', (tester) async {
    await openProject(tester, (s, id) async {
      final invoices = await s.createFolder(id, name: 'Invoices');
      await addFile(s, id, 'quote-tile.txt', 'tile', folderId: invoices.id, tags: ['Docs']);
      await addFile(s, id, 'notes.txt', 'notes');
    });
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('quote-tile.txt'), findsNothing, reason: 'it is inside a folder');

    await tester.enterText(find.byKey(const Key('project-search')), 'QUOTE');
    await tester.pump();
    expect(find.text('1 result for “QUOTE” in the whole project'), findsOneWidget);
    expect(find.text('quote-tile.txt'), findsOneWidget);
    expect(find.text('Kitchen Remodel / Invoices'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('notes.txt'), findsOneWidget);

    await tester.tap(find.text('Docs 1'));
    await tester.pump();
    expect(find.text('1 file tagged “Docs” in the whole project'), findsOneWidget);
    expect(find.text('quote-tile.txt'), findsOneWidget);
    expect(find.text('Invoices'), findsNothing, reason: 'folders are not tagged, so a tag filter lists only files');
  });

  testWidgets('Sorting by name, size and date, in both directions; folders stay first; the list view has the same order', (tester) async {
    await openProject(tester, (s, id) async {
      await s.createFolder(id, name: 'Alpha');
      final zeta = await s.createFolder(id, name: 'Zeta');
      await addFile(s, id, 'z.txt', 'z' * 50, folderId: zeta.id);
      await addFile(s, id, 'b.txt', 'b');
      await addFile(s, id, 'a.txt', 'a' * 200);
    });
    const names = ['Alpha', 'Zeta', 'a.txt', 'b.txt'];
    expect(order(tester, names), ['Alpha', 'Zeta', 'a.txt', 'b.txt']);

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(order(tester, names), ['Alpha', 'Zeta', 'b.txt', 'a.txt'], reason: 'smallest first; an empty folder is smallest');

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descending'));
    await tester.pumpAndSettle();
    expect(order(tester, names), ['Zeta', 'Alpha', 'a.txt', 'b.txt'], reason: 'folders are always above files');

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.text('Date added'), findsOneWidget);
    expect(find.text('200 B'), findsOneWidget);
    expect(find.text('50 B'), findsOneWidget, reason: 'a folder shows its total size');
    expect(order(tester, names), ['Zeta', 'Alpha', 'a.txt', 'b.txt']);

    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(order(tester, names), ['Alpha', 'Zeta', 'a.txt', 'b.txt'], reason: 'a new column sorts ascending');
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(order(tester, names), ['Zeta', 'Alpha', 'b.txt', 'a.txt'], reason: 'the same column again flips it');
  });

  testWidgets('Drag a file onto a folder: it asks first, Cancel changes nothing, Confirm moves it', (tester) async {
    late String invoices;
    final (app, id) = await openProject(tester, (s, id) async {
      invoices = (await s.createFolder(id, name: 'Invoices')).id;
      await addFile(s, id, 'a.txt', 'hello');
    });
    final before = await snapshot(tester, app.storage);

    await drag(tester, find.text('a.txt'), find.text('Invoices'));
    await settleUntil(tester, find.text('Move “a.txt” to “Invoices”?'));
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await drag(tester, find.text('a.txt'), find.text('Invoices'));
    await settleUntil(tester, find.text('Move “a.txt” to “Invoices”?'));
    await tester.tap(find.text('Move 1 item'));
    await settleUntilGone(tester, find.text('a.txt'));
    expect(find.text('a.txt'), findsNothing);
    expect(find.text('Moved 1 item to Invoices'), findsOneWidget);
    expect((await readIndex(tester, app, id)).files.single.folderId, invoices);
  });

  testWidgets('Dragging several selected items moves them all; a folder cannot be dropped on itself', (tester) async {
    late String alpha;
    final (app, id) = await openProject(tester, (s, id) async {
      alpha = (await s.createFolder(id, name: 'Alpha')).id;
      await s.createFolder(id, name: 'Beta');
      await addFile(s, id, 'one.txt', '1');
      await addFile(s, id, 'two.txt', '2');
    });
    await tester.tap(find.text('Select'));
    await tester.pump();
    await tester.tap(find.text('one.txt'));
    await tester.tap(find.text('two.txt'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await drag(tester, find.text('one.txt'), find.text('Alpha'));
    await settleUntil(tester, find.text('Move 2 files to “Alpha”?'));
    await tester.tap(find.text('Move 2 items'));
    await settleUntilGone(tester, find.text('one.txt'));
    expect((await readIndex(tester, app, id)).filesIn(alpha).map((f) => f.name), unorderedEquals(['one.txt', 'two.txt']));

    await drag(tester, find.text('Alpha'), find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Move “Alpha”'), findsNothing, reason: 'nothing happens on a drop onto itself');
  });

  testWidgets('A folder can be dragged onto the path to move it up a level', (tester) async {
    late String inner;
    final (app, id) = await openProject(tester, (s, id) async {
      final outer = await s.createFolder(id, name: 'Outer');
      inner = (await s.createFolder(id, name: 'Inner', parentId: outer.id)).id;
    });
    await tester.tap(find.text('Outer'));
    await settleUntil(tester, find.text('Inner'));
    await drag(tester, find.text('Inner'), crumb('Kitchen Remodel'));
    await settleUntil(tester, find.text('Move “Inner” to “Kitchen Remodel”?'));
    await tester.tap(find.text('Move 1 item'));
    await settleUntilGone(tester, find.text('Inner'));
    expect((await readIndex(tester, app, id)).folderById(inner)!.parentId, isNull);
  });

  testWidgets('Rename folder, and Move to… with a folder list that blocks a folder\'s own contents', (tester) async {
    late String year;
    final (app, id) = await openProject(tester, (s, id) async {
      final invoices = await s.createFolder(id, name: 'Invoices');
      year = (await s.createFolder(id, name: '2026', parentId: invoices.id)).id;
      await s.createFolder(id, name: 'Plans');
      await addFile(s, id, 'a.txt', 'x');
    });

    await rightClick(tester, 'Plans', 'Rename…');
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder-name')), 'Blueprints');
    await tester.pump();
    await tester.tap(find.text('Confirm rename'));
    await settleUntilGone(tester, find.text('Plans'));
    expect(find.text('Blueprints'), findsOneWidget);
    expect(find.text('Plans'), findsNothing);

    await rightClick(tester, 'Invoices', 'Move to…');
    await tester.tap(find.text('Move to…'));
    await settleUntil(tester, find.text('Move “Invoices” to…'));
    expect(tester.widget<InkWell>(find.byKey(const Key('move-target-top'))).onTap, isNotNull);
    expect(tester.widget<InkWell>(find.byKey(Key('move-target-$year'))).onTap, isNull, reason: 'inside the folder being moved');
    expect(filledButton(tester, 'Move here').onPressed, isNull, reason: 'it is already at the top level');
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    await rightClick(tester, 'a.txt', 'Move to…');
    await tester.tap(find.text('Move to…'));
    await settleUntil(tester, find.text('Move “a.txt” to…'));
    await tester.tap(find.byKey(Key('move-target-$year')));
    await tester.pump();
    await tester.tap(find.text('Move here'));
    await settleUntilGone(tester, find.text('a.txt'));
    expect((await readIndex(tester, app, id)).files.single.folderId, year);
  });

  testWidgets('Delete folder: the confirmation counts everything inside; Cancel writes nothing; Confirm deletes it all', (tester) async {
    final (app, id) = await openProject(tester, (s, id) async {
      final a = await s.createFolder(id, name: 'Old stuff');
      final b = await s.createFolder(id, name: 'Deeper', parentId: a.id);
      await addFile(s, id, 'x.txt', 'xxxxx', folderId: a.id);
      await addFile(s, id, 'y.txt', 'yy', folderId: b.id);
      await addFile(s, id, 'keep.txt', 'keep');
    });
    final before = await snapshot(tester, app.storage);

    await rightClick(tester, 'Old stuff', 'Delete folder…');
    await tester.tap(find.text('Delete folder…'));
    await settleUntil(tester, find.text('Delete the folder “Old stuff”?'));
    expect(find.text('Files inside'), findsOneWidget);
    expect(find.text('Folders inside'), findsOneWidget);
    expect(find.text('7 B'), findsOneWidget);
    expect(find.text('Delete folder and 2 files'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await snapshot(tester, app.storage), before);

    await rightClick(tester, 'Old stuff', 'Delete folder…');
    await tester.tap(find.text('Delete folder…'));
    await settleUntil(tester, find.text('Delete folder and 2 files'));
    await tester.tap(find.text('Delete folder and 2 files'));
    await settleUntilGone(tester, find.text('Old stuff'));
    expect(find.text('“Old stuff” deleted, with 2 files'), findsOneWidget);
    final index = await readIndex(tester, app, id);
    expect(index.folders, isEmpty);
    expect(index.files.map((f) => f.name), ['keep.txt']);
  });

  testWidgets('Export a readable copy of a folder: no lock option, the ZIP keeps the folder tree; an empty folder has nothing to export', (tester) async {
    final (app, _) = await openProject(tester, (s, id) async {
      final invoices = await s.createFolder(id, name: 'Invoices');
      final year = await s.createFolder(id, name: '2026', parentId: invoices.id);
      await s.createFolder(id, name: 'Empty');
      await addFile(s, id, 'a.txt', 'in invoices', folderId: invoices.id);
      await addFile(s, id, 'b.txt', 'in 2026', folderId: year.id);
      await addFile(s, id, 'top.txt', 'top');
    });
    final out = await tester.runAsync(tempFolder);

    await rightClick(tester, 'Empty', 'Export a readable copy…');
    await tester.tap(find.text('Export a readable copy…'));
    await settleUntil(tester, find.text('Export the folder “Empty”'));
    expect(find.text('This folder has no files to export.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('export-confirm-button'))).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    await rightClick(tester, 'Invoices', 'Export a readable copy…');
    await tester.tap(find.text('Export a readable copy…'));
    await settleUntil(tester, find.text('Export the folder “Invoices”'));
    expect(find.byKey(const Key('export-lock')), findsNothing, reason: 'a readable copy has no lock option');
    expect(find.textContaining('not protected'), findsOneWidget);
    expect(find.text('Export 2 files (18 B)'), findsOneWidget);
    app.picker.saveLocation = '${out!.path}/Invoices.zip';
    await tester.tap(find.text('Change…'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('export-confirm-button')));
    await settleUntil(tester, find.textContaining('Exported to'));
    final bytes = await tester.runAsync(File('${out.path}/Invoices.zip').readAsBytes);
    final archive = reference.ZipDecoder().decodeBytes(bytes!);
    expect(archive.files.map((f) => f.name), unorderedEquals(['Invoices/a.txt', 'Invoices/2026/b.txt']));
  });

  testWidgets('Sort and view choices carry over to the next project', (tester) async {
    await openProject(tester, (s, id) async => addFile(s, id, 'a.txt', 'a'));
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.text('Date added'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settleUntil(tester, find.text('Kitchen Remodel'));
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('Date added'));
    expect(find.text('Date added'), findsOneWidget);
  });
}
