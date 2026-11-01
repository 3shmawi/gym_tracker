import 'package:meta/meta.dart';

/// The member's level. It rises with active weeks in a row, drops one step
/// after a break, and comes back faster to a level already reached
/// (docs/features/workout.md → Levels).
enum Level {
  beginner,
  intermediate,
  pro;

  /// The level above, or null at [pro].
  Level? get next => index + 1 < values.length ? values[index + 1] : null;

  /// Stored by name; unknown or missing values are [beginner].
  static Level fromName(String? name) =>
      values.where((l) => l.name == name).firstOrNull ?? beginner;
}

/// The level and how far the member is from the next one.
@immutable
class LevelProgress {
  const new({
    required this.level,
    required this.streakWeeks,
    this.weeksToNext,
    this.comeback = false,
    this.best = Level.beginner,
  });

  /// No history yet.
  static const start = LevelProgress(
    level: Level.beginner,
    streakWeeks: 0,
    weeksToNext: 4,
  );

  final Level level;

  /// Active weeks in a row up to now (the week in progress counts once it
  /// is active, and doesn't break the streak before that).
  final int streakWeeks;

  /// More active weeks needed for the next level; null at [Level.pro].
  final int? weeksToNext;

  /// The next level was reached before, so it comes back faster.
  final bool comeback;

  /// The highest level ever reached.
  final Level best;

  Level? get next => level.next;

  @override
  bool operator ==(Object other) =>
      other is LevelProgress &&
      other.level == level &&
      other.streakWeeks == streakWeeks &&
      other.weeksToNext == weeksToNext &&
      other.comeback == comeback &&
      other.best == best;

  @override
  int get hashCode =>
      Object.hash(level, streakWeeks, weeksToNext, comeback, best);

  @override
  String toString() =>
      'LevelProgress($level, streak $streakWeeks, to next $weeksToNext, '
      'comeback $comeback, best $best)';
}
