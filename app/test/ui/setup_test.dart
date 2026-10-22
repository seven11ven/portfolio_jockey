import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/vault/vault.dart';

import 'ui_helpers.dart';

void main() {
  testWidgets('Create vault stays disabled until all three conditions are met', (tester) async {
    final app = await startApp(tester);
    expect(find.text('Welcome to Portfolio Jockey'), findsOneWidget);

    await tester.tap(find.text('Change…'));
    await settle(tester);
    expect(find.text(app.storage.path), findsOneWidget);

    bool canCreate() => filledButton(tester, 'Create vault').onPressed != null;
    expect(canCreate(), isFalse);

    // 11 characters, matching, box ticked: too short.
    await tester.enterText(find.byKey(const Key('passphrase')), 'elevenchars');
    await tester.enterText(find.byKey(const Key('confirm')), 'elevenchars');
    await tester.tap(find.byKey(const Key('understood')));
    await tester.pump();
    expect(canCreate(), isFalse);

    // Long enough but not matching.
    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse battery');
    await tester.pump();
    expect(canCreate(), isFalse);
    expect(find.text("The passphrases don't match."), findsOneWidget);

    // Matching, but the box unticked.
    await tester.enterText(find.byKey(const Key('confirm')), 'correct horse battery');
    await tester.tap(find.byKey(const Key('understood')));
    await tester.pump();
    expect(canCreate(), isFalse);

    // Nothing has been written yet.
    expect(await snapshot(tester, app.storage), isEmpty);
    expect(await snapshot(tester, app.config), isEmpty);

    await tester.tap(find.byKey(const Key('understood')));
    await tester.pump();
    expect(canCreate(), isTrue);

    await tester.ensureVisible(find.text('Create vault'));
    await tester.tap(find.text('Create vault'));
    await settleUntil(tester, find.text('Projects'));
    expect(find.text('Projects'), findsOneWidget);
    expect(app.controller.stage, AppStage.unlocked);
    await tester.runAsync(() async {
      expect(await Vault.exists(app.storage), isTrue);
      expect(await File('${app.config.path}/settings.json').readAsString(), contains(app.storage.path));
    });
  });

  testWidgets('Lock, a wrong passphrase with its delay, then unlock', (tester) async {
    final app = await startApp(tester, unlocked: true);
    await tester.tap(find.byTooltip('Lock'));
    await settle(tester);
    expect(find.text('Portfolio Jockey is locked'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'wrong guess');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.textContaining("didn't unlock"));
    expect(find.text("That passphrase didn't unlock the vault. Check it and try again."), findsOneWidget);
    expect(find.textContaining('Try again in'), findsOneWidget);
    expect(app.controller.backoff.failures, 1);

    // Wait out the 1-second delay in real time, then unlock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1100)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
    await tester.pump();
    await tester.tap(find.text('Unlock'));
    await settleUntil(tester, find.text('Projects'));
    expect(find.text('Projects'), findsOneWidget);
    expect(app.controller.backoff.failures, 0);
  });
}
