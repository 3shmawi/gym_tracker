import 'package:flutter_test/flutter_test.dart';

/// True when recording a demo video (`--dart-define=DEMO=true`).
const isDemo = bool.fromEnvironment('DEMO');

/// A short pause between steps so a recorded demo is easy to follow.
/// Does nothing in normal test runs, so CI stays fast.
Future<void> beat(WidgetTester tester, [int milliseconds = 900]) async {
  if (!isDemo) return;
  await tester.pump(Duration(milliseconds: milliseconds));
  await Future<void>.delayed(Duration(milliseconds: milliseconds));
}
