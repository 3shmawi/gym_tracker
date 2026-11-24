import 'package:gym_tracker/features/move/domain/detectors/geometry.dart';
import 'package:gym_tracker/features/move/domain/detectors/hint_gate.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:meta/meta.dart';

/// The plank's own numbers (starting values; tuned on recordings, Move spec
/// decision 9).
@immutable
class PlankTuning {
  const new({
    this.straightMin = 160,
    this.raisedMin = 0.25,
    this.breakAfter = const Duration(milliseconds: 500),
    this.maxGap = const Duration(milliseconds: 500),
  });

  /// Shoulder–hip–ankle angle (degrees) at or above this: a straight body.
  final double straightMin;

  /// The shoulder at least this far (in torso lengths) above the elbow: on
  /// forearms or hands, not lying flat.
  final double raisedMin;

  /// Out of position this long: "Straighten your body".
  final Duration breakAfter;

  /// A gap between frames longer than this adds nothing (a stalled camera
  /// must not add seconds).
  final Duration maxGap;
}

/// Counts seconds held in a plank, from the side
/// (docs/designs/plank_hold.md §3).
///
/// It reuses [PushUpDetector] for what both exercises share (the view, the
/// body lost and found, too far, too close, too dark) and decides only
/// whether the member is holding. Held time adds up in microseconds, never
/// reset by a break, and every whole second is reported as the existing
/// [RepCounted] (`took` 1 s, `depth` 1): the round counts one per event
/// while it runs, so seconds held during placement and 3-2-1 don't count.
class PlankDetector implements RepDetector {
  new({this.tuning = const PlankTuning()});

  final PlankTuning tuning;
  final PushUpDetector _shared = PushUpDetector();

  late final HintGate _broken = HintGate(
    hold: tuning.breakAfter,
    cooldown: const Duration(seconds: 3),
  );

  Duration? _lastAt;
  bool _holding = false;
  Duration _held = Duration.zero;
  int _seconds = 0;
  RepState _state = const RepState();

  @override
  MoveExerciseId get exercise => MoveExerciseId.plank;

  /// Holding a straight plank in the last frame.
  bool get holding => _holding;

  @override
  RepUpdate onFrame(PoseFrame frame) {
    final last = _lastAt;
    if (last != null && frame.at <= last) return RepUpdate(_state);
    _lastAt = frame.at;

    final shared = _shared.onFrame(frame);
    final events = <RepEvent>[
      for (final e in shared.events)
        // Push-up reps and its softer straight-body hint are not ours.
        if (e is BodyLost ||
            e is BodyFound ||
            (e is FormHint && e.kind != FormHintKind.straightBody))
          e,
    ];
    final s = shared.state;
    final visible = s.phase != RepPhase.notVisible;
    final side = s.view == PoseView.side;
    final wasHolding = _holding;
    _holding = visible && side && _inPlank(frame);

    // Time held since the last frame, only if held in both.
    if (wasHolding && _holding && last != null) {
      final dt = frame.at - last;
      if (dt <= tuning.maxGap) _held += dt;
    }
    while (_held.inSeconds > _seconds) {
      _seconds++;
      events.add(
        RepCounted(total: _seconds, took: const Duration(seconds: 1), depth: 1),
      );
    }

    final bent = visible && side && !_holding;
    if (_broken.update(condition: bent, at: frame.at)) {
      events.add(const FormHint(FormHintKind.straightBody));
    }
    _state = RepState(
      phase: !visible
          ? RepPhase.notVisible
          : _holding
          ? RepPhase.ready
          : RepPhase.goingDown,
      depth: _holding || !visible ? 0 : 1,
      reps: _seconds,
      view: s.view,
      issues: {
        for (final i in s.issues)
          if (i != FormHintKind.straightBody) i,
        if (bent) FormHintKind.straightBody,
      },
    );
    return RepUpdate(_state, events);
  }

  /// A straight line from shoulder to ankle, raised on forearms or hands.
  bool _inPlank(PoseFrame f) {
    final m = _shared.tuning.minLikelihood;
    final a = f.aspect;
    bool side(PoseJoint s, PoseJoint e, PoseJoint h, PoseJoint an) {
      final shoulder = f.seen(s, minLikelihood: m);
      final elbow = f.seen(e, minLikelihood: m);
      final hip = f.seen(h, minLikelihood: m);
      final ankle = f.seen(an, minLikelihood: m);
      if (shoulder == null || elbow == null || hip == null || ankle == null) {
        return false;
      }
      final angle = angleAt(ptOf(shoulder, a), ptOf(hip, a), ptOf(ankle, a));
      if (angle == null || angle < tuning.straightMin) return false;
      final torso = distance(ptOf(shoulder, a), ptOf(hip, a));
      if (torso < 1e-3) return false;
      // Image y grows downwards: the shoulder is above the elbow.
      return (elbow.y - shoulder.y) / torso >= tuning.raisedMin;
    }

    return side(
          PoseJoint.leftShoulder,
          PoseJoint.leftElbow,
          PoseJoint.leftHip,
          PoseJoint.leftAnkle,
        ) ||
        side(
          PoseJoint.rightShoulder,
          PoseJoint.rightElbow,
          PoseJoint.rightHip,
          PoseJoint.rightAnkle,
        );
  }

  @override
  void reset() {
    _shared.reset();
    _broken.reset();
    _lastAt = null;
    _holding = false;
    _held = Duration.zero;
    _seconds = 0;
    _state = const RepState();
  }
}
