import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_controller.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_sheet.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/plan_samples.dart' show SheetHost;

Widget sheet(SoloImportState state, {int count = 42}) => SheetHost(
  background: JoinedView(joined: joinedGym(), onStart: () {}),
  open: (context) => showAppSheet<void>(
    context: context,
    builder: (_) => SoloImportSheet(
      count: count,
      state: state,
      onConfirm: (_) {},
      onClose: () {},
    ),
  ),
);

void main() {
  Future<List<SoloImportChoice>> pump(
    WidgetTester tester, {
    SoloImportState state = const SoloIdle(),
    int count = 42,
  }) async {
    final answers = <SoloImportChoice>[];
    await tester.pumpApp(
      Material(
        child: SoloImportSheet(
          count: count,
          state: state,
          onConfirm: answers.add,
          onClose: () => answers.add(SoloImportChoice.undecided),
        ),
      ),
    );
    return answers;
  }

  group(SoloImportSheet, () {
    testWidgets('"keep" is the default answer', (tester) async {
      final answers = await pump(tester);
      expect(find.text(l10nEn.soloBody(42)), findsOneWidget);
      await tester.tap(find.byKey(const Key('solo_confirm')));
      expect(answers, [SoloImportChoice.keep]);
    });

    testWidgets('add to my account, and skip, are one tap and a confirm', (
      tester,
    ) async {
      final answers = await pump(tester);
      await tester.tap(find.byKey(const Key('solo_copying')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('solo_confirm')));
      await tester.tap(find.byKey(const Key('solo_skip')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('solo_confirm')));
      expect(answers, [SoloImportChoice.copying, SoloImportChoice.skip]);
    });

    testWidgets('says the captain cannot see the copied history', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10nEn.soloAddDetail), findsOneWidget);
      expect(find.text(l10nEn.soloKeepDetail), findsOneWidget);
    });

    testWidgets('only a plan: a different question', (tester) async {
      await pump(tester, count: 0);
      expect(find.text(l10nEn.soloBodyPlanOnly), findsOneWidget);
    });

    testWidgets('progress, failure with retry, and done', (tester) async {
      await pump(tester, state: const SoloRunning(50, 120));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l10nEn.soloCopying(50, 120)), findsOneWidget);

      final answers = await pump(
        tester,
        state: const SoloFailed(NetworkFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('solo_failed')), findsOneWidget);
      await tester.tap(find.byKey(const Key('solo_retry')));
      await tester.tap(find.byKey(const Key('solo_later')));
      expect(answers, [SoloImportChoice.copying, SoloImportChoice.undecided]);

      await pump(tester, state: const SoloDone());
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.soloDoneBody), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await pump(tester);
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'solo_import_ask': () => sheet(const SoloIdle()),
    'solo_import_plan_only': () => sheet(const SoloIdle(), count: 0),
    'solo_import_failed': () => sheet(const SoloFailed(NetworkFailure())),
    'solo_import_done': () => sheet(const SoloDone()),
  });
}
