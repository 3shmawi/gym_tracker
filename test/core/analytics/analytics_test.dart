import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';

void main() {
  group('Analytics.configProblem', () {
    const eu = 'https://eu.i.posthog.com';

    test('accepts a project key with an ingestion host', () {
      expect(Analytics.configProblem('phc_abc123', eu), isNull);
      expect(
        Analytics.configProblem('phc_abc123', 'https://us.i.posthog.com'),
        isNull,
      );
      expect(
        Analytics.configProblem('phc_abc123', 'https://ph.example.com'),
        isNull,
      );
    });

    test('an empty key turns analytics off', () {
      expect(Analytics.configProblem('', eu), contains('empty'));
    });

    test('a personal API key is refused', () {
      expect(Analytics.configProblem('phx_personal', eu), contains('phc_'));
    });

    test('the dashboard address is not an ingestion host', () {
      for (final host in [
        'https://eu.posthog.com',
        'https://us.posthog.com/',
        'https://app.posthog.com',
      ]) {
        expect(Analytics.configProblem('phc_abc', host), contains('i.posthog'));
      }
    });

    test('a non-https host is refused', () {
      expect(
        Analytics.configProblem('phc_abc', 'http://eu.i.posthog.com'),
        contains('https'),
      );
    });

    test('the message never contains the key', () {
      expect(
        Analytics.configProblem('phx_secret_value', eu),
        isNot(contains('secret_value')),
      );
    });
  });
}
