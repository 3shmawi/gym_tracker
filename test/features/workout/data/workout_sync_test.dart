import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/workout_sync.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements WorkoutRepository;

void main() {
  test('syncs each time the device comes back online', () async {
    final repo = _MockRepository();
    when(repo.sync).thenAnswer((_) async => const Success(0));
    final online = StreamController<bool>();
    final sync = WorkoutSync(repo, onlineChanges: online.stream)..start();

    online
      ..add(true)
      ..add(false)
      ..add(true);
    await pumpEventQueue();

    verify(repo.sync).called(2);
    await sync.stop();
    await online.close();
  });
}
