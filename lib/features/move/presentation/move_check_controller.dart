import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:meta/meta.dart';

/// The pose check (diagnostic screen) is for testers: never in the store
/// app, and only with the `move_games_debug` flag on.
Future<bool> moveCheckAllowed({AppFlavor? flavor}) async =>
    !(flavor ?? AppFlavor.current).isProd &&
    await FeatureFlags.isEnabled(Flags.moveGamesDebug);

final moveCheckAllowedProvider = FutureProvider<bool>(
  (ref) => moveCheckAllowed(),
);

/// A fresh pose source per screen (the camera and model in the app, a
/// recording in tests).
final poseSourceFactoryProvider = Provider<PoseSource Function()>(
  (ref) => Dependencies.poseSource,
);

/// What the pose check shows.
@immutable
class MoveCheckState {
  const new({
    this.status = PoseSourceStatus.idle,
    this.rep = const RepState(),
    this.frame,
    this.lastEvent,
    this.frames = 0,
  });

  final PoseSourceStatus status;
  final RepState rep;

  /// The latest frame, to draw the body.
  final PoseFrame? frame;

  /// The latest event the detector reported (rep, half rep, hint…).
  final RepEvent? lastEvent;

  /// Frames processed since the camera started.
  final int frames;

  MoveCheckState copyWith({
    PoseSourceStatus? status,
    RepState? rep,
    PoseFrame? frame,
    RepEvent? lastEvent,
    int? frames,
  }) => MoveCheckState(
    status: status ?? this.status,
    rep: rep ?? this.rep,
    frame: frame ?? this.frame,
    lastEvent: lastEvent ?? this.lastEvent,
    frames: frames ?? this.frames,
  );
}

final NotifierProvider<MoveCheckController, MoveCheckState>
moveCheckControllerProvider =
    NotifierProvider.autoDispose<MoveCheckController, MoveCheckState>(
      MoveCheckController.new,
    );

/// Runs the push-up detector on the live pose source and shows what it
/// sees. Nothing is stored: frames are drawn once and dropped.
class MoveCheckController extends Notifier<MoveCheckState> {
  PoseSource? _source;
  RepDetector? _detector;
  // Both are cancelled in _release (through local copies, which the lint
  // does not follow): the camera is stopped first.
  // ignore: cancel_subscriptions
  StreamSubscription<PoseFrame>? _frames;
  // Cancelled in _release too.
  // ignore: cancel_subscriptions
  StreamSubscription<PoseSourceStatus>? _status;

  @override
  MoveCheckState build() {
    ref.onDispose(_release);
    return const MoveCheckState();
  }

  /// Starts the camera (asks for it the first time). Only on a tap.
  Future<void> start() async {
    if (_source != null) return;
    final source = ref.read(poseSourceFactoryProvider)();
    final detector = MoveExercises.detectorFor(MoveExerciseId.pushUps);
    _source = source;
    _detector = detector;
    _status = source.status.listen((s) {
      if (ref.mounted) state = state.copyWith(status: s);
    });
    _frames = source.frames.listen((frame) {
      if (!ref.mounted) return;
      final update = detector.onFrame(frame);
      state = state.copyWith(
        rep: update.state,
        frame: frame,
        lastEvent: update.events.isEmpty ? null : update.events.last,
        frames: state.frames + 1,
      );
    });
    await source.start();
    if (!ref.mounted) return;
    state = state.copyWith(status: source.currentStatus);
    if (source.currentStatus.state == PoseSourceState.failed) {
      final failed = source.currentStatus;
      await _release();
      if (ref.mounted) state = state.copyWith(status: failed);
    }
  }

  /// Releases the camera and the model (also when the app goes to the
  /// background); the count stays on screen.
  Future<void> stop() async {
    await _release();
    if (ref.mounted) state = state.copyWith(status: PoseSourceStatus.idle);
  }

  void resetCount() {
    _detector?.reset();
    state = MoveCheckState(status: state.status);
  }

  /// The camera goes off first; the listeners are dropped after.
  Future<void> _release() async {
    final source = _source;
    final frames = _frames;
    final status = _status;
    _source = null;
    _detector = null;
    _frames = null;
    _status = null;
    await source?.stop();
    await frames?.cancel();
    await status?.cancel();
  }
}
