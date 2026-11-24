import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/recorded_pose_source.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/presentation/game/stack_game_view.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';

import '../../test/features/move/helpers/plank_frames.dart';
import '../helpers/demo.dart';
import 'move_flow.dart' show wait, waitFor;

/// The plank the camera "sees" in the demo (docs/designs/plank_hold.md):
/// held while the phone is placed and through 3-2-1, then the hips sag for
/// 2 s, then straight again to the end. Joints only, made up (no person was
/// recorded): replayed at its own pace like a camera.
List<PoseFrame> demoPlank() => plankFrames([
  (const Duration(seconds: 26), 0),
  (const Duration(seconds: 2), 0.15),
  (const Duration(seconds: 20), 0),
]);

RecordedPoseSource demoPlankSource() => RecordedPoseSource(demoPlank());

/// Move games, a plank round: home → Move → Plank → 30 s → tip → why the
/// camera → placement → 3-2-1 → the seconds climb and the tower grows a
/// block every 5 s → the hips sag: the big "Keep your body in one line" →
/// straight again, the clock goes on → 0:30 held → Save → the history.
/// Starts on the home screen with a plan; the camera is [demoPlankSource].
Future<void> plankFlow(WidgetTester tester) async {
  Future<void> tap(Finder finder, [int pause = 900]) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable().first);
    await tester.pumpAndSettle();
    await beat(tester, pause);
  }

  await tap(find.byKey(const Key('home_menu_button')));
  await tap(find.byKey(const Key('home_move_button')), 1200);

  // Plank: the round lengths change to holds; 30 s is chosen.
  await tap(find.byKey(const Key('move_exercise_plank')), 1200);
  expect(find.byKey(const Key('move_round_hmax')), findsOneWidget);
  await tap(find.byKey(const Key('move_round_h30')));
  await tap(find.byKey(const Key('move_hub_camera')), 1500);

  // The plank's form tip the first time, then why the camera.
  for (
    var i = 0;
    i < 2 && find.byKey(const Key('move_setup_next')).evaluate().isNotEmpty;
    i++
  ) {
    await tap(find.byKey(const Key('move_setup_next')), 1500);
  }

  await waitFor(tester, find.byKey(const Key('move_countdown')));
  await waitFor(tester, find.byKey(const Key('move_reps')));
  // A block every 5 seconds held.
  await waitFor(
    tester,
    find.byWidgetPredicate(
      (w) => w is StackGameView && w.state.floors.length >= 2,
    ),
  );
  // The hips sag: the big hint, readable from the floor.
  await waitFor(tester, find.byKey(const Key('move_callout')));
  await wait(tester, const Duration(seconds: 1));
  // 30 seconds held end the round.
  await waitFor(tester, find.byKey(const Key('move_results_save')));
  await tester.pumpAndSettle();
  expect(find.text('0:30'), findsWidgets);
  await beat(tester, 2000);

  await tap(find.byKey(const Key('move_results_save')), 1500);
  expect(find.byKey(const Key('move_results_saved')), findsOneWidget);
  await tap(find.byKey(const Key('move_results_progress')), 2000);
  expect(find.byType(ExerciseHistoryView), findsOneWidget);
}
