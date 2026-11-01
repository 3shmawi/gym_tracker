import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_exercise_history.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'progress_samples.dart';

Widget view(AsyncValue<ExerciseHistory?> state, {VoidCallback? onRetry}) =>
    ExerciseHistoryView(
      state: state,
      onRetry: onRetry ?? () {},
      now: () => progressNow,
    );

Finder plain(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066\u2069]'), '') == text,
);

void main() {
  group('ExerciseHistoryView', () {
    testWidgets('summary: since the first time, first → latest, best', (
      tester,
    ) async {
      await tester.pumpApp(
        view(AsyncData(exerciseHistory('wide_lat_pulldown'))),
      );
      expect(find.text('Wide Lat Pulldown'), findsOneWidget);
      expect(find.text('سحب عالي واسع'), findsOneWidget);
      expect(find.text('Since Tue, Oct 13'), findsOneWidget);
      expect(plain('45 kg → 52.5 kg'), findsOneWidget);
      expect(plain('↑ +7.5'), findsOneWidget);
      expect(plain('Best: 52.5×12 · 4 workouts'), findsOneWidget);
    });

    testWidgets('every time, newest first, with the change (design 3.3b)', (
      tester,
    ) async {
      await tester.pumpApp(
        view(AsyncData(exerciseHistory('wide_lat_pulldown'))),
      );
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(plain('52.5×12 · 52.5×12 · 52.5×12'), findsOneWidget);
      expect(find.text('Tue, Oct 27'), findsOneWidget);
      expect(plain('↑ +2.5'), findsNWidgets(3));
    });

    testWidgets('a lighter time shows ↓ and a same one "Same"', (tester) async {
      await tester.pumpApp(view(AsyncData(exerciseHistory('close_grip_row'))));
      expect(plain('↓ −2.5'), findsOneWidget);
      expect(find.text('Same'), findsNWidgets(2)); // summary + Oct 20
    });

    testWidgets('never done: empty state', (tester) async {
      final h = const GetExerciseHistory()(
        PlanTemplates.fiveDaySplit,
        const [],
        'pec_deck',
      );
      await tester.pumpApp(view(AsyncData(h)));
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Pec Deck'), findsOneWidget);
    });

    testWidgets('not in the plan (old or crafted link): empty state', (
      tester,
    ) async {
      await tester.pumpApp(view(const AsyncData(null)));
      expect(find.text("This exercise isn't in your plan."), findsOneWidget);
    });

    testWidgets('error: retry', (tester) async {
      var retried = 0;
      await tester.pumpApp(
        view(
          const AsyncError(NetworkFailure(), StackTrace.empty),
          onRetry: () => retried++,
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('Arabic dates keep Western digits', (tester) async {
      await tester.pumpApp(
        view(AsyncData(exerciseHistory('wide_lat_pulldown'))),
        locale: const Locale('ar'),
      );
      expect(find.text('النهارده'), findsOneWidget);
      expect(find.textContaining('27'), findsWidgets);
      expect(find.textContaining('٢٧'), findsNothing);
    });
  });

  screensUiTests({
    'exercise_history': () =>
        view(AsyncData(exerciseHistory('wide_lat_pulldown'))),
    'exercise_history_never_done': () => view(
      AsyncData(
        const GetExerciseHistory()(
          PlanTemplates.fiveDaySplit,
          const [],
          'pec_deck',
        ),
      ),
    ),
    'exercise_history_not_in_plan': () => view(const AsyncData(null)),
  });
}
