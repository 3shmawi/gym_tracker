/// Every route path in one place. Each path is also a deep link:
/// `azm://<path>`; only `/join/...` also opens from
/// `https://azmm.pages.dev/join/...` (Universal Links / App Links). Document
/// new paths in docs/deep_links.md.
abstract final class AppRoutes {
  static const home = '/';
  static const settings = '/settings';

  /// Invite links: `https://azmm.pages.dev/join/<code>` and
  /// `azm://join/<code>`. They open the enter-code screen with the code filled
  /// in and never join by themselves (behind the `gym_join` flag; off, they
  /// open the home screen). A bare `/join` opens the same screen empty.
  static const join = '/join';

  /// "How do you want to start?": join a gym or train alone.
  static const welcome = '/welcome';

  /// The QR scanner (before `/join/:code`, so "scan" is never a code).
  static const joinScan = '/join/scan';

  /// "Welcome to {gym}" after a code was accepted.
  static const joined = '/join/joined';

  /// My account (signed-in people only).
  static const profile = '/profile';

  /// Delete account (signed-in people only).
  static const deleteAccount = '/profile/delete';

  /// The invite link path for a valid code (the code is encoded, so any
  /// text is safe).
  static String joinCode(String code) => '$join/${Uri.encodeComponent(code)}';

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
