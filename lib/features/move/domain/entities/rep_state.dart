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
    this.issues = const {},
  });

  final RepPhase phase;

  /// 0 = top, 1 = full depth (smoothed).
  final double depth;

  /// Counted reps.
  final int reps;

  /// Null until the detector knows.
  final PoseView? view;

  /// The problems seen in this frame (too far, out of the picture, too
  /// dark…), unlike [FormHint]s, which are given once in a while. The
  /// placement guide keeps a check red while its problem lasts.
  final Set<FormHintKind> issues;

  RepState copyWith({
    RepPhase? phase,
    double? depth,
    int? reps,
    PoseView? Function()? view,
    Set<FormHintKind>? issues,
  }) => RepState(
    phase: phase ?? this.phase,
    depth: depth ?? this.depth,
    reps: reps ?? this.reps,
    view: view == null ? this.view : view(),
    issues: issues ?? this.issues,
  );

  @override
  bool operator ==(Object other) =>
      other is RepState &&
      other.phase == phase &&
      other.depth == depth &&
      other.reps == reps &&
      other.view == view &&
      other.issues.length == issues.length &&
      other.issues.containsAll(issues);

  @override
  int get hashCode =>
      Object.hash(phase, depth, reps, view, Object.hashAllUnordered(issues));

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
