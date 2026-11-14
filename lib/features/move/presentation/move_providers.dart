import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/screen_awake/screen_awake.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_sounds.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_voice.dart';
import 'package:gym_tracker/features/move/domain/usecases/save_move_round.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:meta/meta.dart';

/// Move games are on (the `move_games` flag). Override in tests.
final moveGamesEnabledProvider = FutureProvider<bool>(
  (ref) => FeatureFlags.isEnabled(Flags.moveGames),
);

final moveLocalRepositoryProvider = Provider<MoveLocalRepository>(
  (ref) => Dependencies.moveLocalRepository,
);

/// Makes the game's sounds for one round (silent in widget tests).
final moveSoundsFactoryProvider = Provider<MoveSounds Function()>(
  (ref) => Dependencies.moveSounds,
);

/// Makes the spoken count for one round (silent in widget tests).
final moveVoiceFactoryProvider = Provider<MoveVoice Function()>(
  (ref) => Dependencies.moveVoice,
);

final screenAwakeProvider = Provider<ScreenAwake>(
  (ref) => Dependencies.screenAwake,
);

/// Saves through the current workspace's repository (a gym's uploads the
/// round with the membership, like any workout).
final saveMoveRoundProvider = Provider<SaveMoveRound>(
  (ref) => SaveMoveRound(ref.watch(workoutRepositoryProvider)),
);

/// "Now" for rounds; tests move it by hand.
final moveClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Opens the camera round. Only the app makes one (from the setup screen):
/// a link cannot carry it, so a link never opens the camera.
@immutable
class MoveLaunch {
  const new(this.exercise, this.kind);

  final MoveExerciseId exercise;
  final RoundKind kind;

  @override
  bool operator ==(Object other) =>
      other is MoveLaunch && other.exercise == exercise && other.kind == kind;

  @override
  int get hashCode => Object.hash(exercise, kind);
}

/// Where Move was opened from, for `move_opened`. Anything else is a link.
enum MoveSource {
  card,
  menu,
  link;

  static MoveSource fromQuery(String? v) =>
      values.where((s) => s.name == v && s != link).firstOrNull ?? link;
}
