import 'package:shared_preferences/shared_preferences.dart';

/// The app's legal pages (website/, deployed to azmm.pages.dev) and the
/// third-party ones the app must link (YouTube API Services Developer
/// Policies III.A, checked 2026-11-04).
abstract final class LegalLinks {
  static final Uri privacy = Uri.parse('https://azmm.pages.dev/privacy.html');
  static final Uri terms = Uri.parse('https://azmm.pages.dev/terms.html');
  static final Uri youTubeTerms = Uri.parse('https://www.youtube.com/t/terms');
  static final Uri googlePrivacy = Uri.parse(
    'https://www.google.com/policies/privacy',
  );
}

/// Whether the member agreed to the current Terms of Use and Privacy
/// Policy. YouTube's Developer Policies (III.A) require users to agree to
/// the privacy policy before using the app's features, and to agree again
/// when it starts using data in a new way: bump [current] then.
abstract interface class ConsentStore {
  /// The version the member agreed to, or null.
  String? accepted();
  Future<void> accept(String version);

  /// The policies' "Last updated" date; agreeing to an older one asks again.
  static const current = '2026-11-04';
}

/// On the phone (shared preferences).
class PrefsConsentStore implements ConsentStore {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'legal.accepted';

  @override
  String? accepted() => switch (_prefs.get(key)) {
    final String v => v,
    _ => null,
  };

  @override
  Future<void> accept(String version) => _prefs.setString(key, version);
}

/// Before start-up has run, and in widget tests: already agreed, so screens
/// under test aren't covered by the consent screen.
class AcceptedConsentStore implements ConsentStore {
  const new();

  @override
  String? accepted() => ConsentStore.current;

  @override
  Future<void> accept(String version) async {}
}
