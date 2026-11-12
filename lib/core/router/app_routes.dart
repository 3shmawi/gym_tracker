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

  /// The exercise library. With `?day=<dayId>` it picks an exercise for that
  /// plan day (the "Add" buttons); without it, nothing can be added.
  static const library = '/library';

  /// The picker for one plan day. The id is encoded, so any id is safe.
  static String libraryFor(String dayId) =>
      '$library?day=${Uri.encodeQueryComponent(dayId)}';

  /// One library exercise (picture and steps). With [dayId] it also offers to
  /// add the exercise to that day. [exerciseId] and [dayId] are encoded.
  static String libraryExercise(String exerciseId, {String? dayId}) {
    final path = '$library/${Uri.encodeComponent(exerciseId)}';
    return dayId == null
        ? path
        : '$path?day=${Uri.encodeQueryComponent(dayId)}';
  }

  /// One exercise's history. [exerciseId] is encoded, so any id is safe.
  static String exerciseHistory(String exerciseId) =>
      '$progress/${Uri.encodeComponent(exerciseId)}';

  /// The pose check for testers (not in prod builds; `move_games_debug`
  /// flag). Opening it never starts the camera: that needs a tap.
  static const moveCheck = '/move/check';
}
