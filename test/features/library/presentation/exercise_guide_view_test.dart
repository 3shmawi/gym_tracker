import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/media_cache.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../helpers/no_picture.dart';

LibraryExercise exercise(String id) =>
    ExerciseCatalog.all.firstWhere((e) => e.id == id);

class Calls {
  int adds = 0;
  int backs = 0;
}

Widget view({
  String id = 'flat_db_press',
  bool missing = false,
  bool withoutPicture = false,
  String? dayName,
  bool alreadyInDay = false,
  bool canAdd = true,
  List<ImageProvider> gymPictures = const [],
  bool movePair = false,
  bool offline = false,
  Calls? calls,
}) {
  final c = calls ?? Calls();
  return ExerciseGuideView(
    exercise: missing
        ? null
        : withoutPicture
        ? noPicture
        : exercise(id),
    onBack: () => c.backs++,
    dayName: dayName,
    alreadyInDay: alreadyInDay,
    onAdd: canAdd ? () => c.adds++ : null,
    gymPictures: gymPictures,
    movePair: movePair,
    offline: offline,
    onOpenCredits: () {},
  );
}

/// The gym's pictures in tests: bundled drawings standing in for Cloudinary.
ImageProvider picture(String id) => AssetImage('assets/exercises/$id.webp');

/// A picture that never loads (404, or offline with nothing cached).
ImageProvider broken(String name) => CachedMediaImage(
  Uri.parse('https://res.cloudinary.com/azm/$name.png'),
  fetch: (_) => Future.error(StateError('404')),
);

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
      await tester.pumpApp(view(withoutPicture: true));
      expect(find.text('Illustration coming soon'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets("the gym's pictures come first, then the steps", (
      tester,
    ) async {
      await tester.pumpApp(
        view(
          gymPictures: [picture('flat_db_press'), picture('pec_deck')],
          movePair: true,
        ),
      );
      expect(find.text('\u20661 / 2\u2069'), findsOneWidget);
      expect(find.byTooltip('Pause motion'), findsOneWidget);
      expect(find.text('Everkinetic · CC BY-SA 4.0'), findsOneWidget);
      for (final step in exercise('flat_db_press').steps) {
        expect(find.text(step.en), findsOneWidget);
      }
    });

    testWidgets('offline with nothing cached: bundled drawing, steps stay', (
      tester,
    ) async {
      await tester.pumpApp(view(gymPictures: [broken('a')], offline: true));
      await tester.pump();
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.text("· Your gym's pictures show when you're back online"),
        findsOneWidget,
      );
      expect(find.text(exercise('flat_db_press').steps.first.en), findsOne);
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
    'exercise_guide_no_picture': () => view(withoutPicture: true),
    'exercise_guide_gym_one_picture': () =>
        view(gymPictures: [picture('incline_machine_press')]),
    'exercise_guide_gym_move_pair': () => view(
      gymPictures: [picture('flat_db_press'), picture('incline_machine_press')],
      movePair: true,
    ),
    'exercise_guide_gym_four_pictures': () => view(
      gymPictures: [
        picture('incline_machine_press'),
        picture('flat_db_press'),
        picture('pec_deck'),
        picture('reverse_pec_deck'),
      ],
    ),
    'exercise_guide_gym_offline_nothing_cached': () =>
        view(gymPictures: [broken('a'), broken('b')], offline: true),
    'exercise_guide_not_found': () => view(missing: true),
  });
}
