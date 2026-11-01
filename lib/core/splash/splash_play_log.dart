import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the day the full splash animation last played, so it plays in
/// full on the first launch of the day and short after that.
abstract interface class SplashPlayLog {
  /// Whether to play the full animation now; records today when it does.
  Future<bool> shouldPlayFull(DateTime now);
}

/// [SplashPlayLog] on the device (SharedPreferences): only a local date
/// (`yyyy-mm-dd`), nothing personal, never sent anywhere.
class SharedPrefsSplashPlayLog implements SplashPlayLog {
  const new([this._prefs]);

  final SharedPreferences? _prefs;

  static const key = 'splash_full_played_on';

  @override
  Future<bool> shouldPlayFull(DateTime now) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final today = _day(now);
    if (prefs.getString(key) == today) return false;
    await prefs.setString(key, today);
    return true;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
