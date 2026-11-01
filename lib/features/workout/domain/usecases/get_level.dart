import 'dart:math' as math;

import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Works out the member's level from their finished workouts, week by week.
///
/// - A week (Saturday → Friday, the gym week in Egypt) is **active** with
///   at least [workoutsPerWeek] finished workouts.
/// - **Up:** [intermediateWeeks] active weeks in a row make a beginner
///   intermediate (at least 12 workouts); [proWeeks] more make them pro
///   (about 3 months in all).
/// - **Down:** a break (one or more weeks in a row that aren't active) drops
///   one level: pro → intermediate → beginner. The week in progress never
///   counts as a break.
/// - **Comeback:** climbing back to a level reached before takes half the
///   weeks, rounded up (2 for intermediate, 4 for pro).
///
/// `best` is the highest level reached before (stored), so a comeback stays
/// fast even after old history is trimmed.
class GetLevel {
  const new({
    this.workoutsPerWeek = 3,
    this.intermediateWeeks = 4,
    this.proWeeks = 8,
  });

  final int workoutsPerWeek;

  /// Active weeks in a row from beginner to intermediate.
  final int intermediateWeeks;

  /// Further active weeks in a row from intermediate to pro.
  final int proWeeks;

  /// Active weeks in a row needed to reach [level] from the level below.
  int weeksFor(Level level, {required bool comeback}) {
    final full = switch (level) {
      Level.beginner => 0,
      Level.intermediate => intermediateWeeks,
      Level.pro => proWeeks,
    };
    return comeback ? (full / 2).ceil() : full;
  }

  LevelProgress call(
    List<WorkoutSession> history, {
    required DateTime now,
    Level best = Level.beginner,
  }) {
    final perWeek = <int, int>{};
    for (final s in history) {
      final week = _week(s.finishedAt.toLocal());
      perWeek[week] = (perWeek[week] ?? 0) + 1;
    }
    bool active(int week) => (perWeek[week] ?? 0) >= workoutsPerWeek;

    final thisWeek = _week(now.toLocal());
    var level = Level.beginner;
    var reached = best;
    var climb = 0; // active weeks in a row since the last level change
    var streak = 0;
    var inBreak = false;
    if (perWeek.isNotEmpty) {
      final first = perWeek.keys.reduce(math.min);
      for (var w = first; w <= thisWeek; w++) {
        if (active(w)) {
          inBreak = false;
          streak++;
          climb++;
          final next = level.next;
          if (next != null &&
              climb >= weeksFor(next, comeback: next.index <= reached.index)) {
            level = next;
            climb = 0;
            if (level.index > reached.index) reached = level;
          }
        } else if (w < thisWeek) {
          // A finished week that wasn't active: the first one of a break
          // drops a level; the rest of the same break don't.
          if (!inBreak) level = Level.values[math.max(0, level.index - 1)];
          inBreak = true;
          streak = 0;
          climb = 0;
        }
      }
    }

    final next = level.next;
    final comeback = next != null && next.index <= reached.index;
    return LevelProgress(
      level: level,
      streakWeeks: streak,
      weeksToNext: next == null
          ? null
          : math.max(1, weeksFor(next, comeback: comeback) - climb),
      comeback: comeback,
      best: reached,
    );
  }

  /// Weeks since a Saturday (1 Jan 2000), by calendar date (no DST drift).
  static int _week(DateTime t) {
    final days = DateTime.utc(
      t.year,
      t.month,
      t.day,
    ).difference(DateTime.utc(2000)).inDays;
    return (days / 7).floor();
  }
}
