import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// The working sets of one exercise in one session: the sets with reps at
/// the heaviest weight, in the order they were logged. Lighter warm-ups
/// before them and lighter back-off sets after them are not working sets.
/// Used by `SuggestWeight` and by the dock's pre-fill (`WorkoutFlow`), so
/// both agree on what "set 2 last time" means.
List<LoggedSet> workingSets(List<LoggedSet> sets) {
  final done = [
    for (final s in sets)
      if (s.reps > 0) s,
  ];
  if (done.isEmpty) return const [];
  final heaviest = done.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
  return [
    for (final s in done)
      if (s.weight == heaviest) s,
  ];
}
