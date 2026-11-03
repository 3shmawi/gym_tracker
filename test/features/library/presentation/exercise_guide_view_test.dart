import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

LibraryExercise exercise(String id) =>
    ExerciseCatalog.all.firstWhere((e) => e.id == id);

class Calls {
  int adds = 0;
  int backs = 0;
}

Widget view({
  String id = 'flat_db_press',
  bool missing = false,
  String? dayName,
  bool alreadyInDay = false,
  bool canAdd = true,
  Calls? calls,
}) {
  final c = calls ?? Calls();
  return ExerciseGuideView(
    exercise: missing ? null : exercise(id),
    onBack: () => c.backs++,
    dayName: dayName,
    alreadyInDay: alreadyInDay,
    onAdd: canAdd ? () => c.adds++ : null,
  );
}

void main() {
  group('ExerciseGuideView', () {
    testWidgets('names, muscle, equipment, the steps in order', (tester) async {
      await tester.pumpApp(view());
      expect(find.text('Flat Dumbbell Press'), findsOneWidget);
      expect(find.text('دفع دمبل مستوي'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Dumbbells + Bench'), findsOneWidget);
      expect(find.text('How to do it'), findsOneWidget);
      for (final step in exercise('flat_db_press').steps) {
        expect(find.text(step.en), findsOneWidget);
      }
      // The picture: no placeholder, and the screen reader gets a label.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Illustration coming soon'), findsNothing);
      expect(
        find.bySemanticsLabel('Illustration of Flat Dumbbell Press'),
        findsOneWidget,
      );
    });

    testWidgets('an exercise with no picture shows the placeholder', (
      tester,
    ) async {
      await tester.pumpApp(view(id: 'reverse_pec_deck'));
      expect(find.text('Illustration coming soon'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('reading only: no add button', (tester) async {
      await tester.pumpApp(view());
      expect(find.byKey(const Key('guide_add')), findsNothing);
    });

    testWidgets('from the picker: add to the day, with the starting targets', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(dayName: 'Chest & Back', calls: calls));
      expect(find.text('Add to Chest & Back'), findsOneWidget);
      expect(
        find.textContaining('3 sets · 12 reps · 90 s rest'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('guide_add')));
      expect(calls.adds, 1);
    });

    testWidgets('already in the day: the button says so and is off', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(
        view(dayName: 'Legs', alreadyInDay: true, canAdd: false, calls: calls),
      );
      expect(find.text('Already in Legs'), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide_add')), warnIfMissed: false);
      expect(calls.adds, 0);
    });

    testWidgets('an unknown exercise says so and goes back to the library', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(missing: true, calls: calls));
      expect(find.text("This exercise isn't in the library."), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide_back')));
      expect(calls.backs, 1);
    });
  });

  screensUiTests({
    'exercise_guide': view,
    'exercise_guide_superset_targets': () =>
        view(id: 'barbell_squat', dayName: 'Legs'),
    'exercise_guide_add': () => view(dayName: 'Chest & Back'),
    'exercise_guide_added': () =>
        view(dayName: 'Chest & Back', alreadyInDay: true, canAdd: false),
    'exercise_guide_long_steps': () => view(id: 'machine_calf_raise'),
    'exercise_guide_no_picture': () => view(id: 'reverse_pec_deck'),
    'exercise_guide_not_found': () => view(missing: true),
  });
}
