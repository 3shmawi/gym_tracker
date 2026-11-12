import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/recorded_pose_source.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';

import '../../test/features/move/helpers/synthetic_pose.dart';
import '../helpers/demo.dart';

/// The push-up set the camera "sees" in the demo: the plank held while the
/// phone is placed, then 10 steady reps. Joints only, made up (no person
/// was recorded): replayed at its own pace like a camera.
List<PoseFrame> demoPushUps() => SynthSet(
  lead: const Duration(seconds: 9),
  reps: List.filled(
    10,
    const RepSpec(
      duration: Duration(milliseconds: 1700),
      restAfter: Duration(milliseconds: 300),
    ),
  ),
  noise: 0.002,
).frames();

RecordedPoseSource demoPoseSource() => RecordedPoseSource(demoPushUps());

/// Lets time pass: on a device it really waits (the replay runs on the
/// clock), in a widget test it moves the fake clock.
Future<void> wait(WidgetTester tester, Duration d) async {
  if (tester.binding is LiveTestWidgetsFlutterBinding) {
    await Future<void>.delayed(d);
    await tester.pump();
  } else {
    await tester.pump(d);
  }
}

/// Pumps until [finder] shows, at most [max].
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration max = const Duration(seconds: 60),
}) async {
  var waited = Duration.zero;
  const step = Duration(milliseconds: 100);
  while (finder.evaluate().isEmpty && waited < max) {
    await wait(tester, step);
    waited += step;
  }
  expect(finder, findsWidgets, reason: 'waited $waited');
}

/// Move games, the camera round (docs/features/move_games.md → Demo):
/// home → Move → 10 reps → tip → why the camera → placement turns green →
/// 3-2-1 → ten push-ups → results → Save → the exercise's history. Starts on
/// the home screen with a plan; the camera is [demoPoseSource].
Future<void> moveFlow(WidgetTester tester) async {
  Future<void> tap(Finder finder, [int pause = 900]) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable().first);
    await tester.pumpAndSettle();
    await beat(tester, pause);
  }

  await tap(find.byKey(const Key('home_menu_button')));
  await tap(find.byKey(const Key('home_move_button')), 1200);

  // A round that ends at 10 reps.
  await tap(find.byKey(const Key('move_round_r10')));
  await tap(find.byKey(const Key('move_hub_camera')), 1500);

  // The form tip the first time, then why the camera.
  await tap(find.byKey(const Key('move_setup_next')), 1500);
  await tap(find.byKey(const Key('move_setup_next')));

  // Placement: the checks turn green, 3-2-1 starts by itself.
  await waitFor(tester, find.byKey(const Key('move_countdown')));
  await waitFor(tester, find.byKey(const Key('move_reps')));
  // Ten push-ups end the round.
  await waitFor(tester, find.byKey(const Key('move_results_save')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('move_results_reps')), findsOneWidget);
  expect(find.text('10'), findsWidgets);
  await beat(tester, 2000);

  await tap(find.byKey(const Key('move_results_save')), 1500);
  expect(find.byKey(const Key('move_results_saved')), findsOneWidget);
  await tap(find.byKey(const Key('move_results_progress')), 2000);
  expect(find.byType(ExerciseHistoryView), findsOneWidget);
}
