import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session (refresh token included) in the platform's
/// secure storage instead of `shared_preferences`, which is plain text on
/// Android. Plugged in through `FlutterAuthClientOptions.localStorage`.
///
/// A store that cannot be read is "no session" (the person joins again with a
/// new code), never a crash. It is reported to monitoring without the value.
///
/// On iOS the Keychain survives an uninstall. [isFreshInstall] tells when the
/// app has no other data (shared preferences are gone with the app), and then
/// an old session is dropped: a reinstall is a new phone for the server
/// (docs/decisions/gym_accounts.md §12), and the old session would only be a
/// stranded login that nothing in the app can sign out of.
class SecureLocalStorage extends LocalStorage {
  const new(this._store, {this.isFreshInstall = _never, this.key = sessionKey});

  static const sessionKey = 'azm.supabase.session';

  final SecretStore _store;
  final Future<bool> Function() isFreshInstall;
  final String key;

  static Future<bool> _never() async => false;

  @override
  Future<void> initialize() async {
    if (await isFreshInstall()) await removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    try {
      final value = await _store.read(key);
      return value == null || value.isEmpty ? null : value;
    } on Object catch (error, stackTrace) {
      await Monitoring.captureException(error, stackTrace);
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _store.write(key, persistSessionString);
    } on Object catch (error, stackTrace) {
      await Monitoring.captureException(error, stackTrace);
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _store.delete(key);
    } on Object catch (error, stackTrace) {
      await Monitoring.captureException(error, stackTrace);
    }
  }
}
