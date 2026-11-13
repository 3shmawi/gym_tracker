import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/presentation/app_lifecycle.dart';

void main() {
  test('only really leaving the screen counts, not a dialog over it', () {
    expect(offScreen(AppLifecycleState.inactive), isFalse);
    expect(offScreen(AppLifecycleState.resumed), isFalse);
    expect(offScreen(AppLifecycleState.hidden), isTrue);
    expect(offScreen(AppLifecycleState.paused), isTrue);
    expect(offScreen(AppLifecycleState.detached), isTrue);
  });
}
