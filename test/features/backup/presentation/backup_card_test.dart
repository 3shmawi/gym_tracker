import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/presentation/backup_card.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

Widget card(
  BackupStatus status, {
  VoidCallback? onOpen,
  VoidCallback? onRetry,
  VoidCallback? onTurnOff,
}) => Scaffold(
  body: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      BackupCardView(
        status: status,
        onOpen: onOpen ?? () {},
        onRetry: onRetry ?? () {},
        onTurnOff: onTurnOff ?? () {},
      ),
    ],
  ),
);

final _when = DateTime.utc(2026, 11, 12, 10, 30);

void main() {
  group(BackupCardView, () {
    testWidgets(
      'off: one row opens the sign-in, and says where the training is',
      (tester) async {
        var opened = 0;
        await tester.pumpApp(card(BackupStatus.off, onOpen: () => opened++));
        expect(find.text(l10nEn.backupStatusOff), findsOneWidget);
        await tester.tap(find.byKey(const Key('settings_backup')));
        expect(opened, 1);
      },
    );

    testWidgets('up to date: when, and that the phone keeps it too', (
      tester,
    ) async {
      await tester.pumpApp(
        card(BackupStatus(state: BackupState.upToDate, lastSyncedAt: _when)),
      );
      expect(find.text(l10nEn.backupStatusUpToDate), findsOneWidget);
      expect(find.textContaining('Nov 12, 2026'), findsOneWidget);
      expect(find.text(l10nEn.backupSafe), findsOneWidget);
    });

    testWidgets('waiting: how many, and a retry', (tester) async {
      var retried = 0;
      await tester.pumpApp(
        card(
          const BackupStatus(state: BackupState.waiting, pending: 3),
          onRetry: () => retried++,
        ),
      );
      expect(find.text(l10nEn.backupStatusWaiting(3)), findsOneWidget);
      await tester.tap(find.byKey(const Key('backup_retry')));
      expect(retried, 1);
    });

    testWidgets('failed: how many could not be backed up, safe on the phone', (
      tester,
    ) async {
      await tester.pumpApp(
        card(const BackupStatus(state: BackupState.failed, problems: 2)),
      );
      expect(find.text(l10nEn.backupStatusFailed(2)), findsOneWidget);
      expect(find.text(l10nEn.backupSafe), findsOneWidget);
    });

    testWidgets('the session ended: sign in again', (tester) async {
      var opened = 0;
      await tester.pumpApp(
        card(
          const BackupStatus(state: BackupState.signInAgain, pending: 1),
          onOpen: () => opened++,
        ),
      );
      await tester.tap(find.byKey(const Key('backup_sign_in_again')));
      expect(opened, 1);
    });

    testWidgets('the plan was changed on another phone: it says so', (
      tester,
    ) async {
      await tester.pumpApp(
        card(
          const BackupStatus(state: BackupState.upToDate, planConflict: true),
        ),
      );
      expect(find.byKey(const Key('backup_plan_conflict')), findsOneWidget);
    });

    testWidgets('turn off is always there once it is on', (tester) async {
      var off = 0;
      await tester.pumpApp(
        card(
          const BackupStatus(state: BackupState.upToDate),
          onTurnOff: () => off++,
        ),
      );
      await tester.tap(find.byKey(const Key('backup_turn_off')));
      expect(off, 1);
    });
  });

  screensUiTests({
    'backup_card_off': () => card(BackupStatus.off),
    'backup_card_up_to_date': () =>
        card(BackupStatus(state: BackupState.upToDate, lastSyncedAt: _when)),
    'backup_card_waiting': () => card(
      BackupStatus(state: BackupState.waiting, pending: 7, lastSyncedAt: _when),
    ),
    'backup_card_failed': () =>
        card(const BackupStatus(state: BackupState.failed, problems: 2)),
    'backup_card_sign_in': () =>
        card(const BackupStatus(state: BackupState.signInAgain, pending: 4)),
    'backup_card_plan_conflict': () => card(
      BackupStatus(
        state: BackupState.upToDate,
        lastSyncedAt: _when,
        planConflict: true,
      ),
    ),
  });
}
