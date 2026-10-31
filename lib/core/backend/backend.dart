import 'package:gym_tracker/core/config/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase access. Skipped gracefully when the env file has no values yet.
abstract final class Backend {
  static bool get isConfigured =>
      Env.supabaseUrl.isNotEmpty && Env.supabasePublishableKey.isNotEmpty;

  static Future<void> init() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
