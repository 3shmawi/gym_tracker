// How a rep range reads on Today and in the dock (docs/designs/rep_ranges.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/exercise_preview_row.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/log_panel.dart';

import '../../../../helpers/pump_app.dart';

const _bench = Exercise(
  id: 'flat_barbell_press',
  name: LocalizedName(ar: 'بار مستوي', en: 'Flat Barbell Bench Press'),
  targetSets: 2,
  targetReps: 6,
  repsTop: 10,
);

/// Text without the direction isolates WorkoutFormat.ltr adds.
String _plain(String s) => s.replaceAll(RegExp(r'[\u2066-\u2069]'), '');

Finder _textMatching(String plain) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && _plain(w.data!).contains(plain),
);

void main() {
  for (final (locale, aim) in [
    (const Locale('en'), 'Aim 6–10'),
    (const Locale('ar'), 'هدفك 6–10'),
  ]) {
    testWidgets('dock header: "$aim"', (tester) async {
      await tester.pumpApp(
        AppScaffold(
          body: LogPanel(
            setNumber: 1,
            totalSets: 2,
            targetReps: 6,
            repsTop: 10,
            weight: 35,
            reps: 8,
            weightStep: 2.5,
            onLog: (_, _) {},
          ),
        ),
        locale: locale,
      );
      expect(_textMatching(aim), findsOneWidget);
    });

    testWidgets('Today row: 2×6–10 (${locale.languageCode})', (tester) async {
      await tester.pumpApp(
        const AppScaffold(
          body: ExercisePreviewRow(
            number: 1,
            preview: ExercisePreview(
              exercise: _bench,
              lastSets: [
                LoggedSet(
                  exerciseId: 'flat_barbell_press',
                  weight: 35,
                  reps: 8,
                ),
                LoggedSet(
                  exerciseId: 'flat_barbell_press',
                  weight: 35,
                  reps: 6,
                ),
              ],
              suggestion: WeightSuggestion(weight: 35, trend: Trend.keep),
            ),
          ),
        ),
        locale: locale,
      );
      expect(_textMatching('2×6–10'), findsOneWidget);
    });
  }

  testWidgets('a fixed target still says "Target 12"', (tester) async {
    await tester.pumpApp(
      AppScaffold(
        body: LogPanel(
          setNumber: 1,
          totalSets: 3,
          targetReps: 12,
          weight: 20,
          reps: 12,
          weightStep: 2.5,
          onLog: (_, _) {},
        ),
      ),
    );
    expect(find.text('Target 12'), findsOneWidget);
  });
}
