import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/domain/usecases/search_exercises.dart';
import 'package:gym_tracker/features/library/presentation/library_view.dart';
import 'package:gym_tracker/features/library/presentation/widgets/add_exercise_sheet.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/plan_samples.dart';

class Calls {
  final queries = <String>[];
  final muscles = <MuscleGroup?>[];
  final equipment = <Equipment?>[];
  final opened = <String>[];
  final added = <String>[];
  final own = <String>[];
}

Widget view({
  String query = '',
  MuscleGroup? muscle,
  Equipment? equipment,
  Set<String> added = const {},
  Map<String, ImageProvider> covers = const {},
  Calls? calls,
}) {
  final c = calls ?? Calls();
  return LibraryView(
    exercises: const SearchExercises()(
      ExerciseCatalog.all,
      query: query,
      muscle: muscle,
      equipment: equipment,
    ),
    query: query,
    muscle: muscle,
    equipment: equipment,
    addedIds: added,
    dayName: 'Chest & Back',
    onQueryChanged: c.queries.add,
    onMuscle: c.muscles.add,
    onEquipment: c.equipment.add,
    onOpen: c.opened.add,
    onAdd: c.added.add,
    onWriteOwn: c.own.add,
    gymCovers: covers,
  );
}

/// The gym's first pictures, in tests: bundled drawings standing in.
const Map<String, ImageProvider> gymCovers = {
  'flat_db_press': AssetImage('assets/exercises/incline_machine_press.webp'),
  'incline_machine_press': AssetImage('assets/exercises/flat_db_press.webp'),
};

void main() {
  group('LibraryView', () {
    testWidgets("a gym's cover replaces the drawing and says so", (
      tester,
    ) async {
      await tester.pumpApp(view(muscle: MuscleGroup.chest, covers: gymCovers));
      expect(find.text('Pictures from your gym'), findsNWidgets(2));
      expect(find.byIcon(Icons.shield_outlined), findsNWidgets(2));
    });

    testWidgets('rows show both names, the muscle and the equipment', (
      tester,
    ) async {
      await tester.pumpApp(view(muscle: MuscleGroup.chest));
      expect(find.text('Exercise library'), findsOneWidget);
      expect(find.text('Flat Dumbbell Press'), findsOneWidget);
      expect(find.textContaining('دفع دمبل مستوي'), findsOneWidget);
      expect(find.textContaining('Dumbbells + Bench'), findsOneWidget);
      expect(find.text('3 exercises'), findsOneWidget);
    });

    testWidgets('Add, open and "Added"', (tester) async {
      final calls = Calls();
      await tester.pumpApp(
        view(muscle: MuscleGroup.chest, added: {'flat_db_press'}, calls: calls),
      );
      expect(find.text('Added'), findsOneWidget);
      expect(
        find.byKey(const Key('library_add_flat_db_press')),
        findsNothing,
        reason: 'an added exercise has no Add button',
      );
      await tester.tap(find.byKey(const Key('library_add_pec_deck')));
      expect(calls.added, ['pec_deck']);
      await tester.tap(find.byKey(const Key('library_row_pec_deck')));
      expect(calls.opened, ['pec_deck']);
    });

    testWidgets('search and clear report to the page', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(calls: calls));
      await tester.enterText(find.byKey(const Key('library_search')), 'pec');
      await tester.pump();
      expect(calls.queries, ['pec']);
      await tester.tap(find.byKey(const Key('library_clear')));
      await tester.pump();
      expect(calls.queries.last, '');
      expect(find.byKey(const Key('library_clear')), findsNothing);
    });

    testWidgets('muscle chips report to the page', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(calls: calls));
      await tester.ensureVisible(find.byKey(const Key('muscle_legs')));
      await tester.tap(find.byKey(const Key('muscle_legs')));
      await tester.ensureVisible(find.byKey(const Key('muscle_all')));
      await tester.tap(find.byKey(const Key('muscle_all')));
      expect(calls.muscles, [MuscleGroup.legs, null]);
    });

    testWidgets('the equipment filter lists every kind and "any"', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(calls: calls));
      await tester.tap(find.byKey(const Key('equipment_filter')));
      await tester.pumpAndSettle();
      for (final name in ['Any equipment', 'Dumbbells', 'Cable', 'Machine']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      await tester.tap(find.text('Cable').last);
      await tester.pumpAndSettle();
      expect(calls.equipment, [Equipment.cable]);
    });

    testWidgets('no result: say so, and offer to write it', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(query: 'bulgarian split', calls: calls));
      expect(find.text('No exercise with that name'), findsOneWidget);
      expect(find.byKey(const Key('library_write_own')), findsNothing);
      await tester.tap(find.byKey(const Key('library_write_query')));
      expect(calls.own, ['bulgarian split']);
    });

    testWidgets('"Can\'t find it?" is always there, with the query', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(query: 'pec', calls: calls));
      await tester.tap(find.byKey(const Key('library_write_own')));
      expect(calls.own, ['pec']);
    });

    testWidgets('a long query in the field does not break the layout', (
      tester,
    ) async {
      await tester.pumpApp(view(query: 'x' * 300));
      expect(tester.takeException(), isNull);
      expect(find.text('No exercise with that name'), findsOneWidget);
    });
  });

  group('AddExerciseSheet', () {
    testWidgets('two ways in; the library is the first', (tester) async {
      AddExerciseChoice? picked;
      await tester.pumpApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showAddExerciseSheet(
                context,
                dayName: 'Legs',
                exerciseCount: 8,
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add an exercise'), findsOneWidget);
      expect(find.text('Legs · 8 exercises'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add_from_library')));
      await tester.pumpAndSettle();
      expect(picked, AddExerciseChoice.library);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_custom')));
      await tester.pumpAndSettle();
      expect(picked, AddExerciseChoice.custom);
    });
  });

  screensUiTests({
    'library': view,
    'library_chest': () => view(muscle: MuscleGroup.chest),
    'library_added': () =>
        view(muscle: MuscleGroup.chest, added: {'flat_db_press', 'pec_deck'}),
    'library_cable': () => view(equipment: Equipment.cable),
    'library_gym_covers': () =>
        view(muscle: MuscleGroup.chest, covers: gymCovers),
    'library_no_results': () => view(query: 'bulgarian split squat'),
    'add_exercise_sheet': () => SheetHost(
      background: view(muscle: MuscleGroup.chest),
      open: (context) => showAddExerciseSheet(
        context,
        dayName: 'Chest & Back',
        exerciseCount: 7,
      ),
    ),
  });
}
