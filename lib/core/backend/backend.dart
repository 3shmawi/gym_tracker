import 'package:gym_tracker/core/config/env.dart';
import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:gym_tracker/features/gym/data/datasources/secure_local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase access. Skipped gracefully when the env file has no values yet.
abstract final class Backend {
  static bool get isConfigured =>
      Env.supabaseUrl.isNotEmpty && Env.supabasePublishableKey.isNotEmpty;

  static bool _ready = false;

  /// [init] finished: `client` can be used.
  static bool get isReady => _ready;

  /// Stored on the first launch after an install. Shared preferences go with
  /// the app; the iOS Keychain does not, so when this is missing an old
  /// session in the Keychain belongs to a previous install and is dropped.
  static const installMarkerKey = 'azm.install_marker';

  static Future<void> init() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // The session (and its refresh token) lives in the Keychain /
        // Keystore, not in plain shared preferences.
        localStorage: SecureLocalStorage(
          FlutterSecretStore(),
          isFreshInstall: _isFreshInstall,
        ),
      ),
    );
    _ready = true;
  }

  static Future<bool> _isFreshInstall() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(installMarkerKey)) return false;
    await prefs.setBool(installMarkerKey, true);
    return true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}
