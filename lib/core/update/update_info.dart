import 'package:flutter/foundation.dart';
import 'package:gym_tracker/core/update/app_version.dart';

enum UpdateType { none, optional, force }

/// One row of the `app_versions` table in Supabase (one row per platform).
@immutable
class VersionConfig {
  const new({
    required this.latest,
    required this.minSupported,
    required this.storeUrl,
    this.changelogEn = '',
    this.changelogAr = '',
  });

  factory fromJson(Map<String, dynamic> json) => VersionConfig(
    latest: AppVersion.parse(json['latest_version'] as String),
    minSupported: AppVersion.parse(json['min_supported_version'] as String),
    storeUrl: json['store_url'] as String,
    changelogEn: json['changelog_en'] as String? ?? '',
    changelogAr: json['changelog_ar'] as String? ?? '',
  );

  final AppVersion latest;
  final AppVersion minSupported;
  final String storeUrl;
  final String changelogEn;
  final String changelogAr;
}

/// An update the user should see.
@immutable
class UpdateInfo {
  const new({required this.type, required this.current, required this.config});

  final UpdateType type;
  final AppVersion current;
  final VersionConfig config;

  bool get isForce => type == UpdateType.force;
}

/// Below `min_supported_version`: force. Below `latest_version`: optional.
UpdateType evaluateUpdate({
  required AppVersion current,
  required VersionConfig config,
}) {
  if (current < config.minSupported) return UpdateType.force;
  if (current < config.latest) return UpdateType.optional;
  return UpdateType.none;
}
