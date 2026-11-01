import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/presentation/progress_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'progress_samples.dart';

Widget view(
  AsyncValue<List<ExerciseProgress>?> state, {
  ValueChanged<String>? onOpen,
  VoidCallback? onRetry,
}) => ProgressView(
  state: state,
  onRetry: onRetry ?? () {},
  onOpen: onOpen ?? (_) {},
);

/// Finds text ignoring the LTR isolates around numbers.
Finder plain(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066\u2069]'), '') == text,
);

void main() {
  group('ProgressView', () {
    testWidgets('first → latest heaviest, workouts and the gain', (
      tester,
    ) async {
      await tester.pumpApp(view(AsyncData(progressOverview())));
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Flat Dumbbell Press'), findsOneWidget);
      expect(plain('20 kg → 22.5 kg · 4 workouts'), findsOneWidget);
      expect(plain('↑ +2.5'), findsOneWidget);
      expect(plain('↑ +7.5'), findsOneWidget);
      // Row: 50 → 50 = same.
      expect(find.text('Same'), findsOneWidget);
      expect(find.text('Not done yet'), findsWidgets);
    });

    testWidgets('tapping an exercise opens its history', (tester) async {
      String? opened;
      await tester.pumpApp(
        view(AsyncData(progressOverview()), onOpen: (id) => opened = id),
      );
      await tester.tap(find.text('Wide Lat Pulldown'));
      expect(opened, 'wide_lat_pulldown');
    });

    testWidgets('no workouts yet: empty state', (tester) async {
      await tester.pumpApp(view(AsyncData(progressOverview(const []))));
      expect(
        find.text('Finish a workout to see your progress here.'),
        findsOneWidget,
      );
    });

    testWidgets('no plan: empty state', (tester) async {
      await tester.pumpApp(view(const AsyncData(null)));
      expect(find.byType(EmptyView), findsOneWidget);
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

    testWidgets('loading', (tester) async {
      await tester.pumpApp(view(const AsyncLoading()));
      expect(find.byType(LoadingView), findsOneWidget);
    });

    testWidgets('Arabic: arrow points to the latest', (tester) async {
      await tester.pumpApp(
        view(AsyncData(progressOverview())),
        locale: const Locale('ar'),
      );
      expect(find.text('تقدّمك'), findsOneWidget);
      expect(plain('20 كجم ← 22.5 كجم · 4 تمارين'), findsOneWidget);
    });

    testWidgets('accessible: rows are buttons with a hint', (tester) async {
      await tester.pumpApp(view(AsyncData(progressOverview())));
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.byKey(const Key('progress_flat_db_press')),
      );
      expect(node.hint, 'Shows every time you did it');
      handle.dispose();
    });
  });

  screensUiTests({
    'progress': () => view(AsyncData(progressOverview())),
    'progress_empty': () => view(AsyncData(progressOverview(const []))),
    'progress_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
  });
}
