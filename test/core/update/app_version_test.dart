import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/update/app_version.dart';

void main() {
  group(AppVersion, () {
    test('parses full, short, build and pre-release versions', () {
      expect(AppVersion.parse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.2'), const AppVersion(1, 2, 0));
      expect(AppVersion.parse('1.2.3+45'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.2.3-beta'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('oops'), const AppVersion(0, 0, 0));
    });

    test('compares numerically, not alphabetically', () {
      expect(AppVersion.parse('1.10.0') > AppVersion.parse('1.9.9'), isTrue);
      expect(AppVersion.parse('2.0.0') > AppVersion.parse('1.99.99'), isTrue);
      expect(AppVersion.parse('1.0.1') < AppVersion.parse('1.0.2'), isTrue);
    });

    test('toString prints major.minor.patch', () {
      expect(AppVersion.parse('3.4.5+6').toString(), '3.4.5');
    });
  });
}
