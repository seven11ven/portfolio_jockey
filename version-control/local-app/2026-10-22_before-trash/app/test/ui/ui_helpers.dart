import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/main.dart';
import 'package:portfolio_jockey/services/file_picker.dart';

import '../vault/test_helpers.dart';

/// Answers the file dialogs with prepared paths.
class FakeFilePicker implements FilePicker {
  List<String> files = [];
  String? image;
  String? folder;

  @override
  Future<List<String>> pickFiles() async => files;

  @override
  Future<String?> pickImage() async => image;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async => folder;
}

/// A running app with its own config and storage folders.
class TestApp {
  TestApp(this.controller, this.picker, this.storage, this.config);

  final AppController controller;
  final FakeFilePicker picker;
  final Directory storage;
  final Directory config;
}

/// Starts the app in temporary folders. With [unlocked], a vault already
/// exists and is open, so tests can start on the home screen.
Future<TestApp> startApp(WidgetTester tester, {bool unlocked = false, Widget Function(Widget app)? wrap, Size size = const Size(1280, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late TestApp app;
  await tester.runAsync(() async {
    final storage = await tempFolder();
    final config = await tempFolder();
    final picker = FakeFilePicker()..folder = storage.path;
    final controller = AppController(
      settingsStore: SettingsStore(File('${config.path}/settings.json')),
      filePicker: picker,
      kdf: fastKdf,
    );
    if (unlocked) {
      await controller.createVault(storage.path, 'test passphrase');
    } else {
      await controller.start();
    }
    app = TestApp(controller, picker, storage, config);
  });
  addTearDown(app.controller.dispose);
  final widget = PortfolioJockeyApp(controller: app.controller);
  await tester.pumpWidget(wrap == null ? widget : wrap(widget));
  await settle(tester);
  return app;
}

/// Lets real file and crypto work finish, then rebuilds. Widget tests run on
/// a fake clock, so real asynchronous work needs runAsync.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Settles until [finder] finds something, for up to about 5 seconds.
Future<void> settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  await settle(tester, rounds: 2);
}

/// Settles until [finder] finds nothing, for up to about 5 seconds.
Future<void> settleUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isNotEmpty; i++) {
    await settle(tester, rounds: 1);
  }
}

/// Every file under [folder] with its size and modification time, to prove
/// that a cancelled dialog wrote nothing.
Future<Map<String, String>> snapshot(WidgetTester tester, Directory folder) async {
  final result = <String, String>{};
  await tester.runAsync(() async {
    await for (final entry in folder.list(recursive: true)) {
      final stat = await entry.stat();
      result[entry.path] = '${stat.type} ${stat.size} ${stat.modified.microsecondsSinceEpoch}';
    }
  });
  return result;
}

/// The FilledButton whose label is [label].
FilledButton filledButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton)));
