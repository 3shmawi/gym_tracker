import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:meta/meta.dart';

/// How long a round lasts: a time, or a number of reps (docs/designs/
/// move_games.md §3). The [id] is stored (best scores, analytics).
enum RoundKind {
  s30('s30', time: Duration(seconds: 30)),
  s60('s60', time: Duration(seconds: 60)),
  r10('r10', target: 10),
  r20('r20', target: 20);

  new(this.id, {this.time, this.target});

  final String id;

  /// A timed round ends at this time.
  final Duration? time;

  /// A target round ends at this many reps (or at [maxRound]).
  final int? target;

  /// No round lasts longer, whatever its kind: no pressure to keep going.
  static const maxRound = Duration(minutes: 2);

  static const RoundKind fallback = RoundKind.s60;

  static RoundKind fromId(String? id) =>
      values.where((k) => k.id == id).firstOrNull ?? fallback;
}

/// Counted by the camera, or by the member tapping.
enum RoundMode { camera, manual }

enum RoundPhase {
  /// Not started yet (the camera is finding the member, or waiting for a
  /// tap on Start).
  ready,

  /// 3, 2, 1.
  countdown,
  running,
  paused,
  finished,
}

/// Why a round is paused.
enum PauseReason { tap, bodyLost, background }

/// One round, frame by frame. Pure: time is passed in, so tests are exact
/// and nothing depends on a clock.
@immutable
class RoundState {
  const new({
    required this.exercise,
    required this.kind,
    required this.mode,
    this.phase = RoundPhase.ready,
    this.reps = 0,
    this.steady = 0,
    this.halfReps = 0,
    this.tooFast = 0,
    this.banked = Duration.zero,
    this.runningSince,
    this.countdownEnds,
    this.startedAt,
    this.endedAt,
    this.pauseReason,
  });

  final MoveExerciseId exercise;
  final RoundKind kind;
  final RoundMode mode;
  final RoundPhase phase;
  final int reps;

  /// Reps of [steadyRep] or more (the game's bonus; not saved).
  final int steady;
  final int halfReps;
  final int tooFast;

  /// Running time before the last pause.
  final Duration banked;

  /// When the current running stretch began; null when not running.
  final DateTime? runningSince;

  /// When 3-2-1 ends.
  final DateTime? countdownEnds;

  /// When the round first started running, and when it finished.
  final DateTime? startedAt;
  final DateTime? endedAt;

  final PauseReason? pauseReason;

  static const countdown = Duration(seconds: 3);

  /// A rep this slow (top to top) or slower is steady.
  static const steadyRep = Duration(milliseconds: 1400);

  /// Running time so far.
  Duration elapsed(DateTime now) {
    final since = runningSince;
    if (since == null) return banked;
    final more = now.difference(since);
    return banked + (more.isNegative ? Duration.zero : more);
  }

  /// What the round's clock shows: the time left for a timed round, the
  /// time so far for a target round.
  Duration clock(DateTime now) {
    final time = kind.time;
    if (time == null) return elapsed(now);
    final left = time - elapsed(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Seconds left in 3-2-1 (3, 2 or 1), or null.
  int? countdownLeft(DateTime now) {
    final ends = countdownEnds;
    if (phase != RoundPhase.countdown || ends == null) return null;
    final ms = ends.difference(now).inMilliseconds;
    return ms <= 0 ? null : (ms / 1000).ceil();
  }

  /// Score shown by the game: reps plus steady bonuses.
  int get score => reps + steady;

  RoundState _copy({
    RoundPhase? phase,
    int? reps,
    int? steady,
    int? halfReps,
    int? tooFast,
    Duration? banked,
    DateTime? Function()? runningSince,
    DateTime? Function()? countdownEnds,
    DateTime? Function()? startedAt,
    DateTime? Function()? endedAt,
    PauseReason? Function()? pauseReason,
  }) => RoundState(
    exercise: exercise,
    kind: kind,
    mode: mode,
    phase: phase ?? this.phase,
    reps: reps ?? this.reps,
    steady: steady ?? this.steady,
    halfReps: halfReps ?? this.halfReps,
    tooFast: tooFast ?? this.tooFast,
    banked: banked ?? this.banked,
    runningSince: runningSince == null ? this.runningSince : runningSince(),
    countdownEnds: countdownEnds == null ? this.countdownEnds : countdownEnds(),
    startedAt: startedAt == null ? this.startedAt : startedAt(),
    endedAt: endedAt == null ? this.endedAt : endedAt(),
    pauseReason: pauseReason == null ? this.pauseReason : pauseReason(),
  );

  /// 3-2-1, from ready or paused.
  RoundState startCountdown(DateTime now) {
    if (phase != RoundPhase.ready && phase != RoundPhase.paused) return this;
    return _copy(
      phase: RoundPhase.countdown,
      countdownEnds: () => now.add(countdown),
      pauseReason: () => null,
    );
  }

  /// Moves time on: the countdown ends, the round ends on time.
  RoundState tick(DateTime now) {
    switch (phase) {
      case RoundPhase.countdown:
        final ends = countdownEnds;
        if (ends == null || now.isBefore(ends)) return this;
        return _copy(
          phase: RoundPhase.running,
          runningSince: () => ends,
          countdownEnds: () => null,
          startedAt: () => startedAt ?? ends,
        );
      case RoundPhase.running:
        final time = kind.time ?? RoundKind.maxRound;
        if (elapsed(now) >= time) {
          final since = runningSince;
          return _finish(since == null ? now : since.add(time - banked));
        }
        return this;
      case RoundPhase.ready || RoundPhase.paused || RoundPhase.finished:
        return this;
    }
  }

  /// What the detector reported. Only reps while running count.
  RoundState onEvent(RepEvent event, DateTime now) {
    if (phase != RoundPhase.running) return this;
    return switch (event) {
      RepCounted(:final took) => _rep(now, steady: took >= steadyRep),
      HalfRep() => _copy(halfReps: halfReps + 1),
      TooFast() => _copy(tooFast: tooFast + 1),
      BodyLost() => pause(PauseReason.bodyLost, now),
      BodyFound() || FormHint() => this,
    };
  }

  /// A tap on the manual counter.
  RoundState addRep(DateTime now) =>
      phase == RoundPhase.running ? _rep(now, steady: false) : this;

  /// The manual counter's −1 (never below 0).
  RoundState removeRep() =>
      phase == RoundPhase.running && reps > 0 ? _copy(reps: reps - 1) : this;

  RoundState _rep(DateTime now, {required bool steady}) {
    final next = _copy(reps: reps + 1, steady: this.steady + (steady ? 1 : 0));
    final target = kind.target;
    return target != null && next.reps >= target ? next._finish(now) : next;
  }

  RoundState pause(PauseReason reason, DateTime now) {
    if (phase == RoundPhase.countdown) {
      return _copy(
        phase: RoundPhase.paused,
        countdownEnds: () => null,
        pauseReason: () => reason,
      );
    }
    if (phase != RoundPhase.running) return this;
    return _copy(
      phase: RoundPhase.paused,
      banked: elapsed(now),
      runningSince: () => null,
      pauseReason: () => reason,
    );
  }

  /// "End round" (from running or paused): finishes with what was done.
  RoundState end(DateTime now) => switch (phase) {
    RoundPhase.running ||
    RoundPhase.paused ||
    RoundPhase.countdown => _finish(now),
    RoundPhase.ready || RoundPhase.finished => this,
  };

  RoundState _finish(DateTime at) => _copy(
    phase: RoundPhase.finished,
    banked: elapsed(at),
    runningSince: () => null,
    countdownEnds: () => null,
    endedAt: () => at,
    pauseReason: () => null,
  );
}

/// A finished round, as the results screen shows it and as it is saved.
@immutable
class RoundResult {
  const new({
    required this.exercise,
    required this.kind,
    required this.mode,
    required this.reps,
    required this.steady,
    required this.halfReps,
    required this.duration,
    required this.startedAt,
    required this.finishedAt,
  });

  /// Null when the round never started running (nothing to show).
  static RoundResult? of(RoundState s) {
    final started = s.startedAt;
    final ended = s.endedAt;
    if (s.phase != RoundPhase.finished || started == null || ended == null) {
      return null;
    }
    return RoundResult(
      exercise: s.exercise,
      kind: s.kind,
      mode: s.mode,
      reps: s.reps,
      steady: s.steady,
      halfReps: s.halfReps,
      duration: s.banked,
      startedAt: started,
      finishedAt: ended,
    );
  }

  final MoveExerciseId exercise;
  final RoundKind kind;
  final RoundMode mode;
  final int reps;
  final int steady;
  final int halfReps;
  final Duration duration;
  final DateTime startedAt;
  final DateTime finishedAt;
}
