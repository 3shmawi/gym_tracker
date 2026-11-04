import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';

void main() {
  // Regression: bootstrap called WidgetsFlutterBinding.ensureInitialized(),
  // so Sentry's frame tracking switched itself off and no slow or frozen
  // frames from real phones reached Sentry (docs/performance.md).
  test('start-up uses Sentry binding, not the plain one', () {
    final source = File('lib/bootstrap.dart').readAsStringSync();
    expect(source, contains('Monitoring.ensureBinding()'));
    expect(
      source,
      isNot(contains('WidgetsFlutterBinding.ensureInitialized()')),
    );
  });

  testWidgets('keeps an existing binding (tests)', (tester) async {
    expect(Monitoring.ensureBinding(), same(tester.binding));
  });
}
