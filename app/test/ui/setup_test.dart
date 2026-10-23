import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/vault/journal.dart';
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

    // 11 characters, box ticked: too short, so the confirm field isn't shown
    // yet (it appears at Fair or better, PM decision 2026-10-22).
    expect(find.byKey(const Key('confirm')), findsNothing);
    await tester.enterText(find.byKey(const Key('passphrase')), 'elevenchars');
    await tester.tap(find.byKey(const Key('understood')));
    await tester.pump();
    expect(find.byKey(const Key('confirm')), findsNothing);
    expect(canCreate(), isFalse);

    // Long enough: the confirm field appears; not matching yet.
    await tester.enterText(find.byKey(const Key('passphrase')), 'correct horse battery');
    await tester.pump();
    expect(find.byKey(const Key('confirm')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('confirm')), 'elevenchars');
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

  testWidgets('After a crash, unlocking tidies up and puts a notice in the inbox', (tester) async {
    final app = await startApp(tester, unlocked: true);
    final temp = File('${app.storage.parent.path}/.Kitchen.zip.tmp-crash');
    final temp2 = File('${app.storage.parent.path}/.Garden.zip.tmp-crash');
    // What a crash mid-export leaves: the temp file, and its journal entry.
    // Written straight to the vault, as the test's real-time section can't
    // wait on the service's queue, which runs on the test's simulated clock.
    Future<void> crashedExport(File file, String id) => tester.runAsync(() async {
      await file.writeAsString('readable export content');
      final vault = app.controller.projects.vault;
      await vault.writeJournal([...await vault.readJournal(), ExportStarted(id, tempPath: file.path)]);
    });
    Future<void> lockAndUnlock() async {
      await tester.tap(find.byTooltip('Lock'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('unlock-passphrase')), 'test passphrase');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await settleUntil(tester, find.text('Projects'));
    }

    expect(find.byTooltip('Inbox'), findsOneWidget, reason: 'no number when nothing is unread');
    await crashedExport(temp, 'e1');
    await lockAndUnlock();
    await settleUntil(tester, find.byTooltip('Inbox (1 unread)'));
    expect(find.byTooltip('Inbox (1 unread)'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'the badge');
    expect(find.byType(SnackBar), findsNothing, reason: 'no pop-ups');
    expect(await tester.runAsync(temp.exists), isFalse);

    await tester.tap(find.byTooltip('Inbox (1 unread)'));
    await settleUntil(tester, find.text('Export cleaned up'));
    expect(find.text('An export was interrupted. Its unfinished file was removed.'), findsOneWidget);
    for (var i = 0; i < 50 && app.controller.unreadCount > 0; i++) {
      await settle(tester, rounds: 1);
    }
    expect(app.controller.unreadCount, 0, reason: 'opening the inbox marks it read');

    // Kept across lock and unlock until dismissed.
    await tester.pageBack();
    await settle(tester);
    expect(find.byTooltip('Inbox'), findsOneWidget);
    await lockAndUnlock();
    await tester.tap(find.byTooltip('Inbox'));
    await settleUntil(tester, find.text('Export cleaned up'));
    await tester.tap(find.byTooltip('Dismiss'));
    await settleUntil(tester, find.textContaining('No notices.'));
    expect(app.controller.inbox, isEmpty);

    // Clear all asks first.
    await tester.pageBack();
    await settle(tester);
    await crashedExport(temp, 'e2');
    await crashedExport(temp2, 'e3');
    await lockAndUnlock();
    await settleUntil(tester, find.byTooltip('Inbox (2 unread)'));
    await tester.tap(find.byTooltip('Inbox (2 unread)'));
    await settleUntil(tester, find.text('Clear all'));
    await tester.tap(find.text('Clear all'));
    await settleUntil(tester, find.text('Clear all notices?'));
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(app.controller.inbox, hasLength(2));
    await tester.tap(find.text('Clear all'));
    await settleUntil(tester, find.text('Clear all notices?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await settleUntil(tester, find.textContaining('No notices.'));
    expect(app.controller.inbox, isEmpty);
  });
}
