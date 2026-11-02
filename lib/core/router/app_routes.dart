/// Every route path in one place. Each path is also a deep link:
/// `gymtracker://<path>` and, once the domain is verified,
/// `https://example.com<path>`. Document new paths in
/// docs/deep_links.md.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';

  /// The workout in progress (logging sets).
  static const workout = '/workout';

  /// Every exercise with its progress since the first time.
  static const progress = '/progress';

  /// The plan editor: days in order.
  static const plan = '/plan';

  /// One plan day's exercises. Ids are encoded, so any id is safe.
  static String planDay(String dayId) => '$plan/${Uri.encodeComponent(dayId)}';

  /// One exercise's names and targets in a plan day.
  static String planExercise(String dayId, String exerciseId) =>
      '${planDay(dayId)}/${Uri.encodeComponent(exerciseId)}';

  /// One exercise's history. [exerciseId] is encoded, so any id is safe.
  static String exerciseHistory(String exerciseId) =>
      '$progress/${Uri.encodeComponent(exerciseId)}';
}
