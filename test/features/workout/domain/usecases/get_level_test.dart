import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_level.dart';

/// Saturday 6 Jan 2024: the start of week 0 in these tests.
final _week0 = DateTime(2024, 1, 6, 18);

/// [workouts] sessions in week [week] (Sat, Sun, Mon, …).
List<WorkoutSession> _week(int week, [int workouts = 3]) => [
  for (var d = 0; d < workouts; d++)
    WorkoutSession(
      dayIndex: d % 5,
      finishedAt: _week0.add(Duration(days: week * 7 + d)),
      sets: const [],
    ),
];

/// Active weeks [from]..[to] (inclusive).
List<WorkoutSession> _weeks(int from, int to) => [
  for (var w = from; w <= to; w++) ..._week(w),
];

/// "Now": Friday evening of [week], the last day of that week.
DateTime _endOf(int week) => _week0.add(Duration(days: week * 7 + 6));

/// "Now": Saturday of [week], before any workout that week.
DateTime _startOf(int week) => _week0.add(Duration(days: week * 7));

void main() {
  const getLevel = GetLevel();

  test('no history: beginner, 4 weeks to intermediate', () {
    expect(getLevel(const [], now: _week0), LevelProgress.start);
  });

  test('a week needs 3 workouts to count', () {
    final two = getLevel(_week(0, 2), now: _endOf(0));
    expect(two.streakWeeks, 0);
    final three = getLevel(_week(0), now: _endOf(0));
    expect(three.streakWeeks, 1);
    expect(three.weeksToNext, 3);
  });

  test('4 active weeks in a row: intermediate, then 8 more to pro', () {
    final p = getLevel(_weeks(0, 3), now: _endOf(3));
    expect(p.level, Level.intermediate);
    expect(p.streakWeeks, 4);
    expect(p.weeksToNext, 8);
    expect(p.comeback, isFalse);
    expect(p.best, Level.intermediate);
  });

  test('12 active weeks in a row: pro', () {
    final p = getLevel(_weeks(0, 11), now: _endOf(11));
    expect(p.level, Level.pro);
    expect(p.weeksToNext, isNull);
    expect(p.next, isNull);
  });

  test('the week in progress does not break the streak yet', () {
    final p = getLevel(_weeks(0, 3), now: _startOf(4));
    expect(p.level, Level.intermediate);
    expect(p.streakWeeks, 4);
  });

  test('a break drops one level: pro → intermediate', () {
    // Pro after week 11, nothing in week 12, now in week 13.
    final p = getLevel(_weeks(0, 11), now: _startOf(13));
    expect(p.level, Level.intermediate);
    expect(p.streakWeeks, 0);
    expect(p.best, Level.pro);
  });

  test('a long break is still one drop', () {
    final p = getLevel(_weeks(0, 11), now: _startOf(20));
    expect(p.level, Level.intermediate);
  });

  test('two breaks drop two levels: pro → beginner', () {
    final history = [..._weeks(0, 11), ..._week(13)];
    final p = getLevel(history, now: _startOf(15));
    expect(p.level, Level.beginner);
    expect(p.best, Level.pro);
  });

  test('a break drops intermediate to beginner', () {
    final p = getLevel(_weeks(0, 3), now: _startOf(5));
    expect(p.level, Level.beginner);
    expect(p.comeback, isTrue);
    expect(p.weeksToNext, 2);
  });

  test('comeback is twice as fast: 4 weeks back to pro, not 8', () {
    // Pro, a break (week 12) → intermediate; weeks 13-15 active.
    final three = getLevel([
      ..._weeks(0, 11),
      ..._weeks(13, 15),
    ], now: _endOf(15));
    expect(three.level, Level.intermediate);
    expect(three.comeback, isTrue);
    expect(three.weeksToNext, 1);
    final four = getLevel([
      ..._weeks(0, 11),
      ..._weeks(13, 16),
    ], now: _endOf(16));
    expect(four.level, Level.pro);
  });

  test('comeback from beginner: 2 weeks to intermediate, 4 more to pro', () {
    final base = [..._weeks(0, 11), ..._week(13)];
    // Two breaks (12, 14) → beginner; then weeks 15-16 → intermediate.
    final back = getLevel([...base, ..._weeks(15, 16)], now: _endOf(16));
    expect(back.level, Level.intermediate);
    expect(back.weeksToNext, 4);
    final pro = getLevel([...base, ..._weeks(15, 20)], now: _endOf(20));
    expect(pro.level, Level.pro);
  });

  test('the stored best level keeps the comeback fast after trimming', () {
    final p = getLevel(_week(0), now: _endOf(0), best: Level.pro);
    expect(p.level, Level.beginner);
    expect(p.comeback, isTrue);
    expect(p.weeksToNext, 1);
    expect(p.best, Level.pro);
  });

  test('a level never reached takes the full weeks', () {
    // Back to intermediate in 2 weeks (reached before), but pro is new.
    final p = getLevel(_weeks(0, 1), now: _endOf(1), best: Level.intermediate);
    expect(p.level, Level.intermediate);
    expect(p.comeback, isFalse);
    expect(p.weeksToNext, 8);
  });

  test('order of the history does not matter', () {
    final history = _weeks(0, 3).reversed.toList();
    expect(getLevel(history, now: _endOf(3)).level, Level.intermediate);
  });

  test('many workouts in one week still count as one week', () {
    final p = getLevel(_week(0, 7), now: _endOf(0));
    expect(p.streakWeeks, 1);
    expect(p.level, Level.beginner);
  });

  test('weeks start on Saturday', () {
    // Fri, Sat, Sun: Friday closes one week, Sat and Sun open the next.
    final history = [
      for (final day in [6, 7, 8])
        WorkoutSession(
          dayIndex: 0,
          finishedAt: _week0.add(Duration(days: day)),
          sets: const [],
        ),
    ];
    expect(getLevel(history, now: _endOf(1)).streakWeeks, 0);
  });

  test('UTC timestamps are read in local time', () {
    final utc = [
      for (final s in _weeks(0, 3))
        WorkoutSession(
          dayIndex: s.dayIndex,
          finishedAt: s.finishedAt.toUtc(),
          sets: s.sets,
        ),
    ];
    expect(getLevel(utc, now: _endOf(3)).level, Level.intermediate);
  });

  test('Level.fromName ignores unknown or hostile values', () {
    expect(Level.fromName('pro'), Level.pro);
    expect(Level.fromName(null), Level.beginner);
    expect(Level.fromName(''), Level.beginner);
    expect(Level.fromName("pro'; DROP TABLE x;--"), Level.beginner);
    expect(Level.fromName('PRO'), Level.beginner);
  });
}
