import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in for the trial: an anonymous Supabase user, created silently the
/// first time the app is online. The account stays on the device (its
/// session is persisted), so the member keeps their history.
///
/// Later: link an email to the anonymous user (`updateUser`) so the account
/// survives reinstalling the app.
abstract final class AppAuth {
  static SupabaseClient? get _client =>
      Backend.isConfigured ? Backend.client : null;

  static bool get isSignedIn => _client?.auth.currentUser != null;

  /// True when there is a signed-in user (signing in anonymously if needed).
  /// False when the backend isn't configured or the device is offline.
  static Future<bool> ensureSignedIn() async {
    final client = _client;
    if (client == null) return false;
    if (client.auth.currentUser != null) return true;
    final result = await guard(client.auth.signInAnonymously, retries: 0);
    return result is Success;
  }
}
