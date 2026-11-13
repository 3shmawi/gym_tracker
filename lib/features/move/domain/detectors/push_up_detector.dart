import 'dart:collection';
import 'dart:math' as math;

import 'package:gym_tracker/features/move/domain/detectors/geometry.dart';
import 'package:gym_tracker/features/move/domain/detectors/hint_gate.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_cycle.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:meta/meta.dart';

/// The push-up's own numbers (starting values; tuned on recordings).
@immutable
class PushUpTuning {
  const new({
    this.cycle = const RepTuning(),
    this.minLikelihood = 0.5,
    this.sideRatio = 0.35,
    this.viewVotes = 10,
    this.viewWindow = 15,
    this.viewRecheck = const Duration(seconds: 2),
    this.straightArm = 165,
    this.fullDepthElbow = 90,
    this.frontDrop = 0.6,
    this.frontTopWindow = const Duration(seconds: 6),
    this.frontMinTop = 0.3,
    this.straightBodyMin = 150,
    this.smallBody = 0.25,
    this.edge = 0.03,
    this.darkLikelihood = 0.5,
  });

  final RepTuning cycle;

  /// A joint counts as seen at or above this likelihood.
  final double minLikelihood;

  /// shoulder width / torso length below this: side view.
  final double sideRatio;

  /// Frames classified before the view is decided.
  final int viewVotes;

  /// The view is the majority of the last this many classified frames.
  final int viewWindow;
  final Duration viewRecheck;

  /// Side view: elbow angle (degrees) at the top and at full depth.
  final double straightArm;
  final double fullDepthElbow;

  /// Front view: full depth when the shoulders' height above the wrists
  /// has dropped by this fraction of the top height.
  final double frontDrop;

  /// Front view: the top height is the highest one in this window.
  final Duration frontTopWindow;

  /// Front view: a top below this (in shoulder widths) is not a plank yet.
  final double frontMinTop;

  /// Side view: shoulder–hip–ankle angle below this for a while → hint.
  final double straightBodyMin;

  /// The body spans less than this fraction of the image → move closer.
  final double smallBody;

  /// A needed joint this close to an image edge → move back.
  final double edge;

  /// Mean likelihood of the joints present below this → more light.
  final double darkLikelihood;
}

/// Counts push-ups from the side (elbow angle; left or right side) or from
/// the front (shoulder height above the wrists). Thresholds and why:
/// docs/designs/move_games.md §4.3.
class PushUpDetector implements RepDetector {
  new({this.tuning = const PushUpTuning()}) : _cycle = RepCycle(tuning.cycle);

  final PushUpTuning tuning;
  final RepCycle _cycle;

  final Queue<PoseView> _votes = Queue();
  PoseView? _view;
  Duration? _viewCheckedAt;

  /// Front view: recent shoulder heights (time, height) for the top.
  final Queue<(Duration, double)> _frontHeights = Queue();

  final _straightBody = HintGate(hold: const Duration(seconds: 1));
  final _moveBack = HintGate();
  final _moveCloser = HintGate();
  final _moreLight = HintGate(hold: const Duration(seconds: 2));

  Duration? _lastAt;

  @override
  MoveExerciseId get exercise => MoveExerciseId.pushUps;

  RepState get _state => RepState(
    phase: _cycle.phase,
    depth: _cycle.depth,
    reps: _cycle.reps,
    view: _view,
  );

  @override
  RepUpdate onFrame(PoseFrame frame) {
    final last = _lastAt;
    if (last != null && frame.at <= last) return RepUpdate(_state);
    _lastAt = frame.at;

    final events = <RepEvent>[];
    _classifyView(frame, events);
    final signal = switch (_view) {
      PoseView.side => _sideSignal(frame),
      PoseView.front => _frontSignal(frame),
      null => _undecidedSignal(frame),
    };
    events
      ..addAll(_cycle.onSignal(signal, frame.at))
      ..addAll(_hints(frame));
    return RepUpdate(_state, events);
  }

  @override
  void reset() {
    _cycle.reset();
    _votes.clear();
    _view = null;
    _viewCheckedAt = null;
    _frontHeights.clear();
    _lastAt = null;
    for (final g in [_straightBody, _moveBack, _moveCloser, _moreLight]) {
      g.reset();
    }
  }

  // ---- View -------------------------------------------------------------

  void _classifyView(PoseFrame frame, List<RepEvent> events) {
    final vote = _voteFor(frame);
    if (vote == null) return;
    _votes.addLast(vote);
    while (_votes.length > tuning.viewWindow) {
      _votes.removeFirst();
    }
    if (_votes.length < tuning.viewVotes) return;
    final checked = _viewCheckedAt;
    if (_view != null &&
        checked != null &&
        frame.at - checked < tuning.viewRecheck) {
      return;
    }
    _viewCheckedAt = frame.at;
    final sides = _votes.where((v) => v == PoseView.side).length;
    final majority = sides * 2 > _votes.length ? PoseView.side : PoseView.front;
    if (majority != _view) {
      // The signal's scale changes with the view: a rep half-seen with the
      // old one must not finish with the new one.
      _cycle.restartRep();
      _view = majority;
      _frontHeights.clear();
    }
  }

  PoseView? _voteFor(PoseFrame f) {
    const min = 0.3;
    final ls = f.seen(PoseJoint.leftShoulder, minLikelihood: min);
    final rs = f.seen(PoseJoint.rightShoulder, minLikelihood: min);
    if (ls == null || rs == null) return null;
    final a = f.aspect;
    final width = distance(ptOf(ls, a), ptOf(rs, a));
    final lh = f.seen(PoseJoint.leftHip, minLikelihood: min);
    final rh = f.seen(PoseJoint.rightHip, minLikelihood: min);
    final hip = switch ((lh, rh)) {
      (final l?, final r?) => midpoint(ptOf(l, a), ptOf(r, a)),
      (final l?, null) => ptOf(l, a),
      (null, final r?) => ptOf(r, a),
      (null, null) => null,
    };
    // Hips hidden behind the shoulders: the camera is in front of the head.
    if (hip == null) return PoseView.front;
    final torso = distance(midpoint(ptOf(ls, a), ptOf(rs, a)), hip);
    if (torso < 1e-3) return PoseView.front;
    return width / torso < tuning.sideRatio ? PoseView.side : PoseView.front;
  }

  // ---- Signals ----------------------------------------------------------

  /// Before the view is known, the elbow angle is used when one arm is
  /// clearly visible; nothing counts until the view is decided anyway
  /// (`RepCycle` needs the top first).
  double? _undecidedSignal(PoseFrame f) => _sideSignal(f);

  /// The arm the camera sees best (both shoulder, elbow and wrist seen).
  ({Landmark shoulder, Landmark elbow, Landmark wrist})? _nearArm(PoseFrame f) {
    ({Landmark shoulder, Landmark elbow, Landmark wrist})? arm(
      PoseJoint s,
      PoseJoint e,
      PoseJoint w,
    ) {
      final m = tuning.minLikelihood;
      final shoulder = f.seen(s, minLikelihood: m);
      final elbow = f.seen(e, minLikelihood: m);
      final wrist = f.seen(w, minLikelihood: m);
      if (shoulder == null || elbow == null || wrist == null) return null;
      return (shoulder: shoulder, elbow: elbow, wrist: wrist);
    }

    final left = arm(
      PoseJoint.leftShoulder,
      PoseJoint.leftElbow,
      PoseJoint.leftWrist,
    );
    final right = arm(
      PoseJoint.rightShoulder,
      PoseJoint.rightElbow,
      PoseJoint.rightWrist,
    );
    if (left == null) return right;
    if (right == null) return left;
    double mean(({Landmark shoulder, Landmark elbow, Landmark wrist}) a) =>
        a.shoulder.likelihood + a.elbow.likelihood + a.wrist.likelihood;
    return mean(left) >= mean(right) ? left : right;
  }

  double? _sideSignal(PoseFrame f) {
    final arm = _nearArm(f);
    if (arm == null) return null;
    final a = f.aspect;
    final angle = angleAt(
      ptOf(arm.shoulder, a),
      ptOf(arm.elbow, a),
      ptOf(arm.wrist, a),
    );
    if (angle == null) return null;
    final range = tuning.straightArm - tuning.fullDepthElbow;
    return ((tuning.straightArm - angle) / range).clamp(0.0, 1.0);
  }

  double? _frontSignal(PoseFrame f) {
    final m = tuning.minLikelihood;
    final ls = f.seen(PoseJoint.leftShoulder, minLikelihood: m);
    final rs = f.seen(PoseJoint.rightShoulder, minLikelihood: m);
    final le = f.seen(PoseJoint.leftElbow, minLikelihood: m);
    final re = f.seen(PoseJoint.rightElbow, minLikelihood: m);
    final lw = f.seen(PoseJoint.leftWrist, minLikelihood: m);
    final rw = f.seen(PoseJoint.rightWrist, minLikelihood: m);
    if (ls == null ||
        rs == null ||
        le == null ||
        re == null ||
        lw == null ||
        rw == null) {
      return null;
    }
    final a = f.aspect;
    final width = distance(ptOf(ls, a), ptOf(rs, a));
    if (width < 1e-3) return null;
    final h = ((lw.y + rw.y) / 2 - (ls.y + rs.y) / 2) / width;

    _frontHeights.addLast((f.at, h));
    while (_frontHeights.isNotEmpty &&
        f.at - _frontHeights.first.$1 > tuning.frontTopWindow) {
      _frontHeights.removeFirst();
    }
    final top = _frontHeights.map((e) => e.$2).reduce(math.max);
    if (top < tuning.frontMinTop) return null;
    return ((top - h) / (tuning.frontDrop * top)).clamp(0.0, 1.0);
  }

  // ---- Hints ------------------------------------------------------------

  List<RepEvent> _hints(PoseFrame f) {
    final at = f.at;
    final hints = <RepEvent>[];
    void hint(HintGate gate, FormHintKind kind, {required bool when}) {
      if (gate.update(condition: when, at: at)) hints.add(FormHint(kind));
    }

    final present = [
      for (final j in PoseJoint.values)
        if (f.raw(j) case final l? when l.isInFrame) l,
    ];
    final meanLikelihood = present.isEmpty
        ? 1.0
        : present.map((l) => l.likelihood).reduce((a, b) => a + b) /
              present.length;
    hint(
      _moreLight,
      FormHintKind.moreLight,
      when: present.length >= 6 && meanLikelihood < tuning.darkLikelihood,
    );

    final seen = [
      for (final j in PoseJoint.values)
        ?f.seen(j, minLikelihood: tuning.minLikelihood),
    ];
    if (seen.length >= 4) {
      final xs = seen.map((l) => l.x);
      final ys = seen.map((l) => l.y);
      final spanX = xs.reduce(math.max) - xs.reduce(math.min);
      final spanY = ys.reduce(math.max) - ys.reduce(math.min);
      hint(
        _moveCloser,
        FormHintKind.moveCloser,
        when: math.max(spanX, spanY) < tuning.smallBody,
      );
    } else {
      hint(_moveCloser, FormHintKind.moveCloser, when: false);
    }

    hint(_moveBack, FormHintKind.moveBack, when: _partlyOutOfView(f));
    hint(
      _straightBody,
      FormHintKind.straightBody,
      when: _view == PoseView.side && _bodyBent(f),
    );
    return hints;
  }

  /// Some of the body is visible but a joint the view needs is at the edge
  /// or outside the picture.
  bool _partlyOutOfView(PoseFrame f) {
    final needed = switch (_view) {
      PoseView.front => const [
        PoseJoint.leftShoulder,
        PoseJoint.rightShoulder,
        PoseJoint.leftWrist,
        PoseJoint.rightWrist,
      ],
      _ => const [
        PoseJoint.nose,
        PoseJoint.leftShoulder,
        PoseJoint.rightShoulder,
        PoseJoint.leftHip,
        PoseJoint.rightHip,
        PoseJoint.leftAnkle,
        PoseJoint.rightAnkle,
      ],
    };
    final visible = [
      for (final j in PoseJoint.values)
        if (f.seen(j, minLikelihood: tuning.minLikelihood) != null) j,
    ];
    if (visible.length < 4) return false;
    for (final j in needed) {
      final l = f.raw(j);
      if (l == null) continue;
      final e = tuning.edge;
      final outside =
          l.x < e || l.x > 1 - e || l.y < e || l.y > 1 - e || !l.isInFrame;
      // Hidden far-side joints (low likelihood, inside the image) are fine.
      if (outside) return true;
    }
    return false;
  }

  /// Side view: the shoulder–hip–ankle line is bent (sagging or piked).
  bool _bodyBent(PoseFrame f) {
    final m = tuning.minLikelihood;
    double? lineAngle(PoseJoint s, PoseJoint h, PoseJoint an) {
      final shoulder = f.seen(s, minLikelihood: m);
      final hip = f.seen(h, minLikelihood: m);
      final ankle = f.seen(an, minLikelihood: m);
      if (shoulder == null || hip == null || ankle == null) return null;
      final a = f.aspect;
      return angleAt(ptOf(shoulder, a), ptOf(hip, a), ptOf(ankle, a));
    }

    final angle =
        lineAngle(
          PoseJoint.leftShoulder,
          PoseJoint.leftHip,
          PoseJoint.leftAnkle,
        ) ??
        lineAngle(
          PoseJoint.rightShoulder,
          PoseJoint.rightHip,
          PoseJoint.rightAnkle,
        );
    return angle != null && angle < tuning.straightBodyMin;
  }
}
