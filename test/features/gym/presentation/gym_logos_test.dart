import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_logos.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/presentation/gym_logos.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/gym_logo_fakes.dart';

class _Signed extends AccountSessionNotifier {
  @override
  AccountSession build() => anonymousSession;
}

/// The server's memberships; counts loads and can hold one.
class _Server extends FakeGymRepository {
  new(List<Membership> memberships) : super(memberships: Success(memberships));

  Completer<void>? gate;

  void answer(List<Membership> memberships) =>
      membershipsResult = Success(memberships);

  @override
  Future<Result<List<Membership>>> loadMemberships() async {
    final result = await super.loadMemberships();
    await gate?.future;
    return result;
  }
}

Membership inA({DateTime? version, bool logo = true}) => member(
  gymId: gymA,
  logoPath: logo ? logoPathOf(gymA) : null,
  logoVersion: version ?? DateTime.utc(2026, 11),
);

void main() {
  late _Server server;
  late FakeGymLogoRepository bucket;
  late InMemoryGymLogoStore store;

  setUp(() async {
    Dependencies.flagCache = InMemoryFlagCache();
    FeatureFlags.overrides[Flags.gymLogos] = true;
    await Dependencies.flagCache.write(Flags.gymLogos, value: true);
    server = _Server([inA()]);
    bucket = FakeGymLogoRepository({logoPathOf(gymA): testLogoPng});
    store = InMemoryGymLogoStore();
  });
  tearDown(FeatureFlags.overrides.clear);

  List<Override> overrides() => [
    accountSessionProvider.overrideWith(_Signed.new),
    gymRepositoryProvider.overrideWithValue(server),
    gymLocalRepositoryProvider.overrideWithValue(
      InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
        logos: store,
      ),
    ),
    gymLogoRepositoryProvider.overrideWithValue(bucket),
    gymLogoStoreProvider.overrideWithValue(store),
  ];

  Future<ProviderContainer> app() async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c
      ..listen(gymControllerProvider, (_, _) {})
      ..listen(gymLogoImagesProvider, (_, _) {});
    await c.read(gymControllerProvider.future);
    await c.read(gymControllerProvider.notifier).refresh();
    return c;
  }

  group(GymLogoSync, () {
    test("downloads the active gyms' logos; the tiles get them", () async {
      final c = await app();
      expect(c.read(gymLogoImagesProvider), isEmpty);
      await c.read(gymLogoSyncProvider).sync();
      await c.read(storedGymLogosProvider.future);
      expect(store.bytesOf(gymA), testLogoPng);
      expect(c.read(gymLogoImagesProvider).keys, {gymA});
      expect(c.read(gymLogoImagesProvider)[gymA], isA<FileImage>());
    });

    test('flag off: nothing downloads, every tile shows letters', () async {
      FeatureFlags.overrides[Flags.gymLogos] = false;
      await Dependencies.flagCache.write(Flags.gymLogos, value: false);
      await store.save(inA().gym.logo!, testLogoPng);
      final c = await app();
      await c.read(gymLogoSyncProvider).sync();
      expect(bucket.fetched, isEmpty);
      expect(c.read(gymLogoImagesProvider), isEmpty, reason: 'even if kept');
    });

    test(
      'calls during a sync make it run once more, not twice at once',
      () async {
        final c = await app();
        final sync = c.read(gymLogoSyncProvider);
        final first = sync.sync();
        final second = sync.sync();
        final third = sync.sync();
        await Future.wait([first, second, third]);
        expect(bucket.fetched, hasLength(1), reason: 'the rerun found it kept');
      },
    );

    test('signing out deletes the logos', () async {
      final c = await app();
      await c.read(gymLogoSyncProvider).sync();
      await c.read(gymLocalRepositoryProvider).clear();
      expect(await store.load(), isEmpty);
    });
  });

  test('a new logo does not restart what depends on the gym', () async {
    final c = await app();
    var changes = 0;
    c.listen(activeMembershipProvider, (_, _) => changes++);
    expect(c.read(activeMembershipProvider)?.gym.id, gymA);
    server.answer([inA(version: DateTime.utc(2026, 11, 14))]);
    await c.read(gymControllerProvider.notifier).refresh();
    server.answer([inA(logo: false)]);
    await c.read(gymControllerProvider.notifier).refresh();
    expect(changes, 0, reason: 'the workout, plan and pictures stay');
  });

  test('refreshes that come together ask the server once', () async {
    final c = await app();
    final before = server.loads;
    server.gate = Completer();
    final controller = c.read(gymControllerProvider.notifier);
    final a = controller.refresh();
    final b = controller.refresh();
    server.gate!.complete();
    await Future.wait([a, b]);
    expect(server.loads - before, 1);
  });

  testWidgets('back in the app: the gym is asked again, the new logo follows', (
    tester,
  ) async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    SharedPreferences.setMockInitialValues({});
    Dependencies.workoutRepository = LocalWorkoutRepository(
      (await tester.runAsync(SharedPreferences.getInstance))!,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: GymSyncHost(
          onlineChanges: online.stream,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(bucket.fetched.map((l) => l.version).toSet(), {
      DateTime.utc(2026, 11).millisecondsSinceEpoch,
    });
    final loads = server.loads;

    // The owner replaces the logo while the app is in the background.
    final v2 = DateTime.utc(2026, 11, 14);
    server.answer([inA(version: v2)]);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(server.loads, greaterThan(loads), reason: 'asked on resume');
    expect((await store.load())[gymA]!.logo.version, v2.millisecondsSinceEpoch);
  });
}
