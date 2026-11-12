import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/features/move/data/datasources/recorded_pose_source.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';

import '../helpers/fake_pose_source.dart';
import '../helpers/synthetic_pose.dart';

void main() {
  ProviderContainer containerWith(PoseSource Function() factory) {
    final c = ProviderContainer(
      overrides: [poseSourceFactoryProvider.overrideWithValue(factory)],
    );
    addTearDown(c.dispose);
    // Keep the auto-dispose controller alive for the test.
    c.listen(moveCheckControllerProvider, (_, _) {});
    return c;
  }

  test('nothing starts until start(): no camera on open', () {
    var made = 0;
    final c = containerWith(() {
      made++;
      return FakePoseSource();
    });
    expect(c.read(moveCheckControllerProvider), isA<MoveCheckState>());
    expect(made, 0);
  });

  test('counts a recorded set and shows the latest frame', () async {
    final c = containerWith(
      () => RecordedPoseSource(SynthSet.reps(3).frames(), realTime: false),
    );
    await c.read(moveCheckControllerProvider.notifier).start();
    await pumpEventQueue();
    final s = c.read(moveCheckControllerProvider);
    expect(s.rep.reps, 3);
    expect(s.rep.view, PoseView.side);
    expect(s.frame, isNotNull);
    expect(s.frames, greaterThan(100));
  });

  test('the status and speed come from the source', () async {
    final source = FakePoseSource();
    final c = containerWith(() => source);
    await c.read(moveCheckControllerProvider.notifier).start();
    source.setStatus(
      const PoseSourceStatus(PoseSourceState.running, fps: 14.5),
    );
    expect(c.read(moveCheckControllerProvider).status.fps, 14.5);
  });

  test('a refused camera shows the problem and releases the source', () async {
    final source = FakePoseSource(
      startsAs: const PoseSourceStatus(
        PoseSourceState.failed,
        problem: PoseProblem.denied,
      ),
    );
    final c = containerWith(() => source);
    await c.read(moveCheckControllerProvider.notifier).start();
    final s = c.read(moveCheckControllerProvider);
    expect(s.status.problem, PoseProblem.denied);
    expect(source.stops, 1);
    // Trying again makes a new source.
    await c.read(moveCheckControllerProvider.notifier).start();
    expect(source.starts, 2);
  });

  test('stop releases the camera; the count stays until reset', () async {
    final source = FakePoseSource();
    final c = containerWith(() => source);
    final controller = c.read(moveCheckControllerProvider.notifier);
    await controller.start();
    SynthSet.reps(2).frames().forEach(source.emit);
    expect(c.read(moveCheckControllerProvider).rep.reps, 2);
    expect(c.read(moveCheckControllerProvider).lastEvent, isA<RepEvent>());
    await controller.stop();
    expect(source.stops, 1);
    expect(c.read(moveCheckControllerProvider).status, PoseSourceStatus.idle);
    expect(c.read(moveCheckControllerProvider).rep.reps, 2);
    controller.resetCount();
    expect(c.read(moveCheckControllerProvider).rep.reps, 0);
    expect(c.read(moveCheckControllerProvider).frame, isNull);
  });

  test('a second start while running does not open a second camera', () async {
    var made = 0;
    final c = containerWith(() {
      made++;
      return FakePoseSource();
    });
    final controller = c.read(moveCheckControllerProvider.notifier);
    await controller.start();
    await controller.start();
    expect(made, 1);
  });

  test('closing the screen releases the camera', () async {
    final source = FakePoseSource();
    final c = ProviderContainer(
      overrides: [poseSourceFactoryProvider.overrideWithValue(() => source)],
    );
    final sub = c.listen(moveCheckControllerProvider, (_, _) {});
    await c.read(moveCheckControllerProvider.notifier).start();
    sub.close();
    await pumpEventQueue();
    expect(source.stops, 1);
    c.dispose();
  });

  group('moveCheckAllowed', () {
    tearDown(FeatureFlags.overrides.clear);

    test('testers on staging and dev with the flag on', () async {
      FeatureFlags.overrides[Flags.moveGamesDebug] = true;
      expect(await moveCheckAllowed(flavor: AppFlavor.staging), isTrue);
      expect(await moveCheckAllowed(flavor: AppFlavor.dev), isTrue);
    });

    test('never in prod, whatever the flag says', () async {
      FeatureFlags.overrides[Flags.moveGamesDebug] = true;
      expect(await moveCheckAllowed(flavor: AppFlavor.prod), isFalse);
      // Tests run without a flavor: treated as prod.
      expect(await moveCheckAllowed(), isFalse);
    });

    test('off without the flag', () async {
      expect(await moveCheckAllowed(flavor: AppFlavor.staging), isFalse);
    });
  });
}
