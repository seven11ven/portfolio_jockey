import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as reference;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/project_service.dart';
import 'package:portfolio_jockey/ui/export/export_dialog.dart';
import 'package:portfolio_jockey/ui/home/home_screen.dart';

import '../vault/test_helpers.dart';
import 'ui_helpers.dart';

void main() {
  /// Unlocked, with "Kitchen Remodel" (2 files) and "Garden Planner" on Home.
  Future<(TestApp, Directory)> withProjects(WidgetTester tester) async {
    final app = await startApp(tester, unlocked: true);
    late Directory out;
    await tester.runAsync(() async {
      out = await tempFolder();
      final originals = await tempFolder();
      final kitchen = await app.controller.projects.createProject(name: 'Kitchen Remodel');
      final a = File('${originals.path}/measurements.txt')..writeAsStringSync('Counter: 240 cm');
      final b = File('${originals.path}/notes.md')..writeAsStringSync('# Plan');
      await app.controller.projects.addFiles(kitchen, [a.path, b.path]);
      await app.controller.projects.createProject(name: 'Garden Planner');
    });
    app.controller.lock();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Kitchen Remodel'));
    return (app, out);
  }

  Future<void> openExport(WidgetTester tester, String item) async {
    final card = find.ancestor(of: find.text('Kitchen Remodel'), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ProjectCard'));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('Project actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await settleUntil(tester, find.byKey(const Key('export-lock')));
  }

  FilledButton exportButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('export-confirm-button')));

  Future<void> chooseTarget(WidgetTester tester, TestApp app, String path) async {
    app.picker.saveLocation = path;
    await tester.tap(find.text('Change…'));
    await settle(tester);
  }

  testWidgets('Export dialog: the passphrase must be filled in and match; Cancel writes nothing', (tester) async {
    final (_, out) = await withProjects(tester);
    await openExport(tester, 'Export as ZIP…');
    expect(find.text('Export “Kitchen Remodel”'), findsOneWidget);
    expect(find.textContaining('not protected'), findsOneWidget);
    expect(find.text('ZIP'), findsOneWidget);
    expect(find.textContaining('Kitchen Remodel.zip'), findsOneWidget);
    expect(exportButton(tester).onPressed, isNotNull);
    expect(find.text('Export 2 files (21 B)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-lock')));
    await tester.pump();
    expect(find.text('ZIP'), findsNothing, reason: 'a locked export is always .pjx');
    expect(find.textContaining('Kitchen Remodel.pjx'), findsOneWidget);
    expect(find.textContaining("can't be recovered"), findsOneWidget);
    expect(exportButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('export-passphrase')), 'garage-sale');
    await tester.pump();
    expect(exportButton(tester).onPressed, isNull, reason: 'not confirmed yet');
    await tester.enterText(find.byKey(const Key('export-confirm')), 'garage-salf');
    await tester.pump();
    expect(find.text("The passphrases don't match."), findsOneWidget);
    expect(exportButton(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('export-confirm')), 'garage-sale');
    await tester.pump();
    expect(exportButton(tester).onPressed, isNotNull, reason: 'no strength rules');

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await tester.runAsync(() => out.list().toList()), isEmpty);
  });

  testWidgets('Unlocked TAR export is saved where chosen; an existing file is flagged', (tester) async {
    final (app, out) = await withProjects(tester);
    final target = File('${out.path}/kitchen.tar');
    await tester.runAsync(() => target.writeAsString('old'));
    await openExport(tester, 'Export as TAR…');
    await chooseTarget(tester, app, target.path);
    expect(find.textContaining('already exists there'), findsOneWidget);
    expect(find.textContaining('free)'), findsOneWidget, reason: 'free space is shown');

    await tester.tap(find.byKey(const Key('export-confirm-button')));
    await settleUntil(tester, find.textContaining('Exported to'));
    final archive = reference.TarDecoder().decodeBytes((await tester.runAsync(target.readAsBytes))!);
    final files = {for (final f in archive.files) f.name: utf8.decode(f.content)};
    expect(files['Kitchen Remodel/files/measurements.txt'], 'Counter: 240 cm');
    expect(files['Kitchen Remodel/files/notes.md'], '# Plan');
  });

  testWidgets('Locked export, then import: wrong passphrase refused, clash renamed, projects added', (tester) async {
    final (app, out) = await withProjects(tester);
    final target = '${out.path}/backup.pjx';
    await openExport(tester, 'Export as ZIP…');
    await tester.tap(find.byKey(const Key('export-lock')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('export-passphrase')), 'garage-sale');
    await tester.enterText(find.byKey(const Key('export-confirm')), 'garage-sale');
    await tester.pump();
    await chooseTarget(tester, app, target);
    await tester.tap(find.byKey(const Key('export-confirm-button')));
    await settleUntil(tester, find.textContaining('Exported to'));
    expect(await tester.runAsync(() => File(target).exists()), isTrue);

    // Import: Cancel at the passphrase step writes nothing.
    app.picker.exportFile = target;
    await tester.tap(find.byTooltip('Import a locked export'));
    await settleUntil(tester, find.text('Open this export'));
    await tester.enterText(find.byKey(const Key('import-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Open'));
    await settleUntil(tester, find.textContaining("doesn't open this export"));
    expect(find.textContaining("doesn't open this export"), findsOneWidget, reason: 'the vault passphrase is not the export passphrase');

    await tester.enterText(find.byKey(const Key('import-passphrase')), 'garage-sale');
    await tester.pump();
    await tester.tap(find.text('Open'));
    await settleUntil(tester, find.text('Import projects?'));
    expect(find.textContaining('imported as “Kitchen Remodel (2)”'), findsOneWidget);
    await tester.tap(find.text('Import 1 project'));
    await settleUntil(tester, find.text('Kitchen Remodel (2)'));
    expect(find.text('Imported 1 project'), findsOneWidget);
    expect(find.text('Kitchen Remodel (2)'), findsOneWidget);
  });

  testWidgets('Bulk export: projects can be chosen, and none chosen disables Export', (tester) async {
    final (app, _) = await withProjects(tester);
    late List<ProjectSummary> projects;
    await tester.runAsync(() async => projects = (await app.controller.projects.listProjects()).projects);
    unawaited(
      showDialog<bool>(
        context: tester.element(find.byType(HomeScreen)),
        builder: (_) => ExportDialog(projects: projects, bulk: true),
      ),
    );
    await settleUntil(tester, find.text('Export projects'));
    expect(find.text('All projects (2)'), findsOneWidget);
    expect(find.text('Export 2 projects'), findsOneWidget);
    await tester.tap(find.text('All projects (2)'));
    await tester.pump();
    expect(find.text('Choose at least one project.'), findsOneWidget);
    expect(exportButton(tester).onPressed, isNull);
    await tester.tap(find.textContaining('Garden Planner ·'));
    await tester.pump();
    expect(find.text('Export 1 project'), findsOneWidget);
    expect(find.textContaining('Portfolio Jockey projects'), findsOneWidget);
  });

  testWidgets('Export a readable copy: from the file menu and the preview menu; Cancel writes nothing', (tester) async {
    final (app, out) = await withProjects(tester);
    await tester.tap(find.text('Kitchen Remodel'));
    await settleUntil(tester, find.text('measurements.txt'));
    await tester.tap(find.text('measurements.txt'));
    await settleUntil(tester, find.text('Export a readable copy…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export a readable copy…'));
    await settleUntil(tester, find.text('Save a readable copy of measurements.txt?'));
    expect(find.textContaining('The copy is not protected'), findsOneWidget);
    expect(find.textContaining('Lock with'), findsNothing, reason: 'no lock option');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await tester.runAsync(() => out.list().toList()), isEmpty);

    final target = File('${out.path}/measurements.txt');
    await tester.runAsync(() => target.writeAsString('old'));
    await tester.tap(find.text('measurements.txt'));
    await settleUntil(tester, find.text('Export a readable copy…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export a readable copy…'));
    await settleUntil(tester, find.text('Save readable copy'));
    await chooseTarget(tester, app, target.path);
    expect(find.textContaining('already exists there. Saving replaces it.'), findsOneWidget);
    await tester.tap(find.text('Save readable copy'));
    await settleUntil(tester, find.textContaining('Saved a readable copy to'));
    expect(await tester.runAsync(target.readAsString), 'Counter: 240 cm');

    // From the preview's "…" menu.
    await tester.tap(find.text('notes.md'));
    await settleUntil(tester, find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await settleUntil(tester, find.text('Plan'));
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Export a readable copy…'));
    await settleUntil(tester, find.text('Save a readable copy of notes.md?'));
    await chooseTarget(tester, app, '${out.path}/notes.md');
    await tester.tap(find.text('Save readable copy'));
    await settleUntil(tester, find.text('Saved a readable copy to ${out.path}/notes.md'));
    expect(await tester.runAsync(() => File('${out.path}/notes.md').readAsString()), '# Plan');
  });
}
