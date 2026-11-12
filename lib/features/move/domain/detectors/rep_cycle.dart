import 'package:gym_tracker/features/move/domain/detectors/one_euro_filter.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:meta/meta.dart';

/// The numbers of a rep cycle, in one place per exercise so tests and
/// tuning change one object (docs/designs/move_games.md §4.2).
@immutable
class RepTuning {
  const new({
    this.leaveTop = 0.25,
    this.reachBottom = 0.80,
    this.leaveBottom = 0.70,
    this.backAtTop = 0.20,
    this.halfRepMin = 0.40,
    this.minRep = const Duration(milliseconds: 700),
    this.lostAfter = const Duration(milliseconds: 1500),
    this.foundAfter = const Duration(milliseconds: 500),
    this.glitchJump = 0.5,
    this.minCutoff = 1.2,
    this.beta = 0.8,
  });

  /// Signal above this: the rep has started.
  final double leaveTop;

  /// Signal at or above this: full depth.
  final double reachBottom;

  /// After full depth, below this: on the way up.
  final double leaveBottom;

  /// At or below this: the top position (a rep ends here).
  final double backAtTop;

  /// A dip that peaks between this and [reachBottom] is a half rep;
  /// smaller ones (breathing, shifting) are ignored.
  final double halfRepMin;

  /// Top to top faster than this is not counted.
  final Duration minRep;

  /// Not visible for this long: the body is lost.
  final Duration lostAfter;

  /// Visible again for this long: the body is found.
  final Duration foundAfter;

  /// A single frame whose signal jumps further than this from the last one
  /// is a glitch and is dropped (a second one in a row is believed).
  final double glitchJump;

  /// The 1€ filter on the signal.
  final double minCutoff;
  final double beta;
}

/// The state machine every rep exercise shares: a signal that goes from
/// rest (0) to a full rep (1) and back. A detector turns joints into the
/// signal; this class turns the signal into reps, half reps, too-fast reps
/// and visibility.
class RepCycle {
  new([this.tuning = const RepTuning()])
    : _filter = OneEuroFilter(minCutoff: tuning.minCutoff, beta: tuning.beta);

  final RepTuning tuning;
  final OneEuroFilter _filter;

  RepPhase _phase = RepPhase.notVisible;
  int _reps = 0;
  double _depth = 0;

  /// The top has been seen since the body was found (a rep can start).
  bool _armed = false;

  /// The last time the signal was at the top: a rep is timed from here.
  Duration? _lastTopAt;
  double _peak = 0;

  Duration? _lastAt;
  Duration? _visibleSince;
  Duration? _lastVisibleAt;
  double? _lastRaw;
  bool _droppedLast = false;

  RepPhase get phase => _phase;
  int get reps => _reps;
  double get depth => _depth;

  /// Feeds one frame: [signal] is null when the joints the exercise needs
  /// are not visible. Frames older than the last one are ignored.
  List<RepEvent> onSignal(double? signal, Duration at) {
    final last = _lastAt;
    if (last != null && at <= last) return const [];
    _lastAt = at;

    final events = <RepEvent>[];
    final s = signal != null && signal.isFinite ? signal.clamp(0.0, 1.0) : null;

    if (s == null) {
      _visibleSince = null;
      final lastSeen = _lastVisibleAt;
      if (_phase != RepPhase.notVisible &&
          (lastSeen == null || at - lastSeen >= tuning.lostAfter)) {
        _lose();
        events.add(const BodyLost());
      }
      return events;
    }

    // A long gap between visible frames counts as having been away.
    final lastSeen = _lastVisibleAt;
    if (_phase != RepPhase.notVisible &&
        lastSeen != null &&
        at - lastSeen >= tuning.lostAfter) {
      _lose();
      events.add(const BodyLost());
    }

    if (_isGlitch(s)) return events;
    _lastVisibleAt = at;

    if (_phase == RepPhase.notVisible) {
      final since = _visibleSince ??= at;
      if (at - since < tuning.foundAfter) return events;
      _phase = RepPhase.ready;
      _armed = false;
      events.add(const BodyFound());
    }

    final value = _filter.filter(s, at.inMicroseconds / 1e6);
    _depth = value.clamp(0.0, 1.0);
    _step(value, at, events);
    return events;
  }

  void _step(double s, Duration at, List<RepEvent> events) {
    switch (_phase) {
      case RepPhase.notVisible:
        return;
      case RepPhase.ready:
        if (s <= tuning.backAtTop) {
          _armed = true;
          _lastTopAt = at;
        } else if (_armed && s > tuning.leaveTop) {
          _phase = RepPhase.goingDown;
          _peak = s;
        }
      case RepPhase.goingDown:
        if (s > _peak) _peak = s;
        if (s >= tuning.reachBottom) {
          _phase = RepPhase.bottom;
        } else if (s <= tuning.backAtTop) {
          if (_peak >= tuning.halfRepMin) events.add(HalfRep(depth: _peak));
          _backToTop(at);
        }
      case RepPhase.bottom:
        if (s > _peak) _peak = s;
        if (s < tuning.leaveBottom) _phase = RepPhase.goingUp;
      case RepPhase.goingUp:
        if (s >= tuning.reachBottom) {
          _phase = RepPhase.bottom;
          if (s > _peak) _peak = s;
        } else if (s <= tuning.backAtTop) {
          final took = at - (_lastTopAt ?? at);
          if (took < tuning.minRep) {
            events.add(TooFast(took: took));
          } else {
            _reps++;
            events.add(RepCounted(total: _reps, took: took, depth: _peak));
          }
          _backToTop(at);
        }
    }
  }

  void _backToTop(Duration at) {
    _phase = RepPhase.ready;
    _armed = true;
    _lastTopAt = at;
    _peak = 0;
  }

  /// One frame far from the last one is dropped; a second one in a row
  /// means the change is real.
  bool _isGlitch(double s) {
    final last = _lastRaw;
    _lastRaw = s;
    if (last == null || _phase == RepPhase.notVisible) {
      _droppedLast = false;
      return false;
    }
    if ((s - last).abs() > tuning.glitchJump && !_droppedLast) {
      _droppedLast = true;
      _lastRaw = last;
      return true;
    }
    _droppedLast = false;
    return false;
  }

  void _lose() {
    _phase = RepPhase.notVisible;
    _armed = false;
    _peak = 0;
    _lastTopAt = null;
    _visibleSince = null;
    _lastRaw = null;
    _depth = 0;
    _filter.reset();
  }

  /// Forgets the rep in progress but keeps the count (e.g. the view
  /// changed, so the signal's scale changed).
  void restartRep() {
    if (_phase == RepPhase.notVisible) return;
    _phase = RepPhase.ready;
    _armed = false;
    _peak = 0;
    _lastRaw = null;
    _filter.reset();
  }

  /// Back to the start: no reps, nothing visible.
  void reset() {
    _lose();
    _reps = 0;
    _lastAt = null;
    _lastVisibleAt = null;
  }
}
