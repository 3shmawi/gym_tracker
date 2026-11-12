import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:meta/meta.dart';

/// Where the member is in a rep.
enum RepPhase {
  /// The body is not visible (or not yet found).
  notVisible,

  /// Visible, at the top or waiting to get there.
  ready,

  /// On the way down.
  goingDown,

  /// At full depth.
  bottom,

  /// On the way back up after full depth.
  goingUp,
}

/// Where the camera sees the member from.
enum PoseView { side, front }

/// The live state of a detector, for the screen.
@immutable
class RepState {
  const new({
    this.phase = RepPhase.notVisible,
    this.depth = 0,
    this.reps = 0,
    this.view,
  });

  final RepPhase phase;

  /// 0 = top, 1 = full depth (smoothed).
  final double depth;

  /// Counted reps.
  final int reps;

  /// Null until the detector knows.
  final PoseView? view;

  RepState copyWith({
    RepPhase? phase,
    double? depth,
    int? reps,
    PoseView? Function()? view,
  }) => RepState(
    phase: phase ?? this.phase,
    depth: depth ?? this.depth,
    reps: reps ?? this.reps,
    view: view == null ? this.view : view(),
  );

  @override
  bool operator ==(Object other) =>
      other is RepState &&
      other.phase == phase &&
      other.depth == depth &&
      other.reps == reps &&
      other.view == view;

  @override
  int get hashCode => Object.hash(phase, depth, reps, view);

  @override
  String toString() => 'RepState(${phase.name}, $depth, $reps, ${view?.name})';
}

/// What one frame changed.
@immutable
class RepUpdate {
  const new(this.state, [this.events = const []]);

  final RepState state;
  final List<RepEvent> events;
}
