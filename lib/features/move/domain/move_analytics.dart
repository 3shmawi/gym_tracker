import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';

/// Analytics for Move games use buckets, never exact numbers, and never
/// images, landmarks or personal data (docs/designs/move_games.md §11).
abstract final class MoveAnalytics {
  static String repsBucket(int reps) => switch (reps) {
    <= 0 => '0',
    <= 5 => '1_5',
    <= 10 => '6_10',
    <= 20 => '11_20',
    <= 40 => '21_40',
    _ => '41_plus',
  };

  static String durationBucket(Duration d) => switch (d.inSeconds) {
    < 30 => 'lt_30s',
    <= 60 => '30_60s',
    <= 120 => '60_120s',
    _ => 'gt_120s',
  };

  /// Null when not measured (manual rounds).
  static String? fpsBucket(double? fps) => switch (fps) {
    null => null,
    < 8 => 'lt_8',
    < 15 => '8_15',
    _ => '15_plus',
  };

  /// Finer than [fpsBucket] for the "too slow" case; null when unknown.
  static String? fpsBand(double? fps) => switch (fps) {
    null => null,
    final f when f.isNaN => null,
    < 2 => '0_2',
    < 4 => '2_4',
    < 6 => '4_6',
    < 8 => '6_8',
    _ => '8_plus',
  };

  /// The game played: the exercise's game with the camera, `none` when
  /// counting by hand (no game is shown).
  static String game(MoveExerciseId exercise, RoundMode mode) => switch (mode) {
    RoundMode.camera => MoveExercises.gameFor(exercise).id.id,
    RoundMode.manual => 'none',
  };
}
