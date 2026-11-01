import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'init can run more than once (the app restarts in one process)',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Dependencies.init();
      final first = Dependencies.workoutRepository;
      await Dependencies.init();
      expect(Dependencies.workoutRepository, isNot(same(first)));
    },
  );
}
