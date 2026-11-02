import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/features/gym/presentation/join_view.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/join_outcome_sheet.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/plan_samples.dart' show SheetHost;

Widget host(JoinOutcome outcome) => SheetHost(
  background: JoinView(initialCode: 'K7M2QX', onSubmit: (_) {}),
  open: (context) => showJoinOutcomeSheet(context, outcome: outcome),
);

void main() {
  group('JoinOutcome.of', () {
    test('every refusal maps to its own message', () {
      expect(
        JoinOutcome.of(const InviteFailure(InviteProblem.invalid)),
        JoinOutcome.invalid,
      );
      expect(
        JoinOutcome.of(const InviteFailure(InviteProblem.expired)),
        JoinOutcome.expired,
      );
      expect(
        JoinOutcome.of(const InviteFailure(InviteProblem.used)),
        JoinOutcome.used,
      );
      expect(
        JoinOutcome.of(const InviteFailure(InviteProblem.conflict)),
        JoinOutcome.conflict,
      );
      expect(
        JoinOutcome.of(const InviteFailure(InviteProblem.throttled)),
        JoinOutcome.throttled,
      );
      expect(JoinOutcome.of(const NetworkFailure()), JoinOutcome.offline);
      expect(JoinOutcome.of(const ServerFailure()), JoinOutcome.error);
      expect(JoinOutcome.of(const TimeoutFailure()), JoinOutcome.error);
      expect(JoinOutcome.of(const UnknownFailure()), JoinOutcome.error);
    });
  });

  group(JoinOutcomeSheet, () {
    Future<JoinOutcomeAction?> open(
      WidgetTester tester,
      JoinOutcome outcome,
      Future<void> Function() act,
    ) async {
      JoinOutcomeAction? result;
      await tester.pumpApp(
        SheetHost(
          background: const SizedBox(),
          open: (context) async {
            result = await showJoinOutcomeSheet(context, outcome: outcome);
          },
        ),
      );
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a wrong code can be scanned again or typed', (tester) async {
      final result = await open(tester, JoinOutcome.invalid, () async {
        expect(find.text(l10nEn.joinInvalidTitle), findsOneWidget);
        expect(find.text(l10nEn.joinScanAgain), findsOneWidget);
        await tester.tap(find.byKey(const Key('join_outcome_secondary')));
      });
      expect(result, JoinOutcomeAction.secondary);
    });

    for (final (outcome, title) in [
      (JoinOutcome.expired, l10nEn.joinExpiredTitle),
      (JoinOutcome.used, l10nEn.joinUsedTitle),
      (JoinOutcome.conflict, l10nEn.joinConflictTitle),
    ]) {
      testWidgets('$outcome says what to do next, and can be closed', (
        tester,
      ) async {
        final result = await open(tester, outcome, () async {
          expect(find.text(title), findsOneWidget);
          expect(find.text(l10nEn.commonOk), findsOneWidget);
          expect(find.text(l10nEn.joinTypeOtherCode), findsOneWidget);
          await tester.tap(find.byKey(const Key('join_outcome_primary')));
        });
        expect(result, JoinOutcomeAction.primary);
      });
    }

    testWidgets('too many tries only says to wait', (tester) async {
      await open(tester, JoinOutcome.throttled, () async {
        expect(find.text(l10nEn.joinThrottledBody), findsOneWidget);
        expect(find.byKey(const Key('join_outcome_secondary')), findsNothing);
      });
    });

    for (final outcome in [JoinOutcome.offline, JoinOutcome.error]) {
      testWidgets('$outcome offers to try again', (tester) async {
        final result = await open(tester, outcome, () async {
          expect(find.text(l10nEn.retry), findsOneWidget);
          expect(find.text(l10nEn.joinTypeCode), findsOneWidget);
          await tester.tap(find.byKey(const Key('join_outcome_primary')));
        });
        expect(result, JoinOutcomeAction.primary);
      });
    }

    testWidgets('no message says whether a code ever existed', (tester) async {
      final all = [
        l10nEn.joinInvalidBody,
        l10nEn.joinExpiredBody,
        l10nEn.joinUsedBody,
        l10nEn.joinConflictBody,
        l10nEn.joinThrottledBody,
        l10nEn.joinInvalidInline,
      ].join(' ').toLowerCase();
      expect(all, isNot(contains('does not exist')));
      expect(all, isNot(contains("doesn't exist")));
      expect(all, isNot(contains('unknown code')));
    });
  });

  screensUiTests({
    for (final outcome in JoinOutcome.values)
      'join_outcome_${outcome.name}': () => host(outcome),
  });
}
