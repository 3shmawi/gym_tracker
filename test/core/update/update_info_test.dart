import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/update/app_version.dart';
import 'package:gym_tracker/core/update/update_info.dart';

void main() {
  final config = VersionConfig(
    latest: AppVersion.parse('1.5.0'),
    minSupported: AppVersion.parse('1.2.0'),
    storeUrl: 'https://example.com',
  );

  UpdateType evaluate(String current) =>
      evaluateUpdate(current: AppVersion.parse(current), config: config);

  group('evaluateUpdate', () {
    test('forces the update below the minimum supported version', () {
      expect(evaluate('1.1.9'), UpdateType.force);
    });

    test('offers the update between minimum and latest', () {
      expect(evaluate('1.2.0'), UpdateType.optional);
      expect(evaluate('1.4.9'), UpdateType.optional);
    });

    test('does nothing when up to date or newer', () {
      expect(evaluate('1.5.0'), UpdateType.none);
      expect(evaluate('1.6.0'), UpdateType.none);
    });
  });

  test('VersionConfig.fromJson reads a Supabase row', () {
    final parsed = VersionConfig.fromJson(const {
      'latest_version': '2.0.0',
      'min_supported_version': '1.0.0',
      'store_url': 'https://store',
      'changelog_en': 'New',
      'changelog_ar': null,
    });
    expect(parsed.latest, const AppVersion(2, 0, 0));
    expect(parsed.minSupported, const AppVersion(1, 0, 0));
    expect(parsed.changelogEn, 'New');
    expect(parsed.changelogAr, isEmpty);
  });
}
