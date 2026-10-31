import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/update/app_version.dart';
import 'package:gym_tracker/core/update/update_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the `app_versions` row for this platform from Supabase and decides
/// whether to show an optional or a forced update. Control it from the
/// Supabase dashboard — no release needed.
abstract final class UpdateService {
  static const table = 'app_versions';

  /// Returns the update to show, or `null` when the app is up to date,
  /// offline, or Supabase isn't configured.
  static Future<UpdateInfo?> check() async {
    if (kIsWeb || !Backend.isConfigured) return null;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) return null;

    try {
      final row = await Backend.client
          .from(table)
          .select()
          .eq('platform', platform)
          .maybeSingle();
      if (row == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final current = AppVersion.parse(packageInfo.version);
      final config = VersionConfig.fromJson(row);
      final type = evaluateUpdate(current: current, config: config);
      if (type == UpdateType.none) return null;
      return UpdateInfo(type: type, current: current, config: config);
    } on Exception catch (error, stackTrace) {
      unawaited(Monitoring.captureException(error, stackTrace));
      return null;
    }
  }
}
