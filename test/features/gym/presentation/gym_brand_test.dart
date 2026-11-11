import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/theme/azm_theme.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/gym_brand.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/plan_sync_fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/active_workout_view_test.dart' as workout;
import '../../workout/presentation/next_workout_view_test.dart' as home;

const yellow = '#facc15';
const navy = '#1e3a8a';
const yellowColor = Color(0xFFFACC15);
const navyColor = Color(0xFF1E3A8A);

Membership inGym(
  String? color, {
  String id = 'm1',
  MembershipStatus status = MembershipStatus.active,
}) {
  final m = member(id: id, status: status);
  return Membership(
    id: m.id,
    gym: Gym(id: m.gym.id, name: m.gym.name, brandColor: color),
    role: m.role,
    status: m.status,
    permissions: m.permissions,
    displayName: m.displayName,
  );
}

GymSnapshot snapshot(List<Membership> memberships, {String? active}) =>
    GymSnapshot(
      workspace: active == null ? const SoloWorkspace() : GymWorkspace(active),
      memberships: memberships,
    );

class _Gyms extends GymController {
  new(this._first);

  final GymSnapshot _first;

  @override
  Future<GymSnapshot> build() async => _first;

  void show(GymSnapshot next) => state = AsyncData(next);
}

Future<ProviderContainer> app(
  GymSnapshot first, {
  List<Object> more = const [],
}) async {
  final c = ProviderContainer(
    overrides: [
      gymControllerProvider.overrideWith(() => _Gyms(first)),
      ...more.cast(),
    ],
  );
  addTearDown(c.dispose);
  await c.read(gymControllerProvider.future);
  return c;
}

/// A screen as a member of a gym with [color] sees it.
Widget themed(Color color, Widget screen) => Builder(
  builder: (context) => Theme(
    data: AppTheme.of(Theme.of(context).brightness, gymColor: color),
    child: screen,
  ),
);

void main() {
  setUp(() async {
    // The flag is on, and the phone already knows it.
    Dependencies.flagCache = InMemoryFlagCache();
    await Dependencies.flagCache.write(Flags.gymBrandColours, value: true);
    FeatureFlags.overrides[Flags.gymBrandColours] = true;
  });
  tearDown(FeatureFlags.overrides.clear);

  group('the colour on a gym', () {
    test('a valid colour is read from the server and from the cache', () {
      final gym = Gym.fromJson(const {
        'id': 'g',
        'name': 'G',
        'brand_color': yellow,
      });
      expect(gym.brandColor, yellow);
      final again = Membership.fromJson(inGym(yellow).toJson());
      expect(again.gym.brandColor, yellow);
    });

    test('anything else is no colour, and the gym still loads', () {
      for (final bad in <Object?>[
        null,
        '',
        '#FACC15',
        '#fff',
        'red',
        '#808080',
        '#000000',
        42,
        true,
        ['#facc15'],
        {'hex': yellow},
        '#facc15 ',
        "#facc15'; drop table gyms;--",
        '<script>',
        '#facc15' * 50000,
      ]) {
        final gym = Gym.fromJson({'id': 'g', 'name': 'G', 'brand_color': bad});
        expect(gym.brandColor, isNull, reason: '$bad'.split('\n').first);
        expect(gym.name, 'G');
      }
      expect(Gym.fromJson(const {'id': 'g', 'name': 'G'}).brandColor, isNull);
    });

    test('the colour is not part of what makes two gyms equal', () {
      expect(inGym(yellow), inGym(navy));
      expect(inGym(yellow).hashCode, inGym(null).hashCode);
    });
  });

  group('activeBrandColorProvider', () {
    test('the active gym with a colour', () async {
      final c = await app(snapshot([inGym(yellow)], active: 'm1'));
      expect(c.read(activeBrandColorProvider), yellowColor);
    });

    test('solo, no colour, ended and unknown workspaces are Azm', () async {
      for (final s in [
        snapshot([inGym(yellow)]),
        snapshot([inGym(null)], active: 'm1'),
        snapshot([inGym(yellow, status: MembershipStatus.ended)], active: 'm1'),
        snapshot([inGym(yellow)], active: 'someone-else'),
        const GymSnapshot(),
      ]) {
        final c = await app(s);
        expect(c.read(activeBrandColorProvider), isNull);
      }
    });

    test('flag off: Azm even with a colour saved', () async {
      await Dependencies.flagCache.write(Flags.gymBrandColours, value: false);
      FeatureFlags.overrides[Flags.gymBrandColours] = false;
      final c = await app(snapshot([inGym(yellow)], active: 'm1'));
      expect(c.read(activeBrandColorProvider), isNull);
    });

    test(
      'the flag starts from the phone, then keeps what PostHog says',
      () async {
        // Nothing known yet: off.
        Dependencies.flagCache = InMemoryFlagCache();
        final first = await app(const GymSnapshot());
        expect(first.read(gymBrandColoursEnabledProvider), isFalse);
        await pumpEventQueue();
        expect(first.read(gymBrandColoursEnabledProvider), isTrue);
        expect(Dependencies.flagCache.read(Flags.gymBrandColours), isTrue);
        // Next start: on at once, before PostHog answers.
        final second = await app(const GymSnapshot());
        expect(second.read(gymBrandColoursEnabledProvider), isTrue);
        // PostHog turns it off: remembered for the start after.
        FeatureFlags.overrides[Flags.gymBrandColours] = false;
        final third = await app(const GymSnapshot());
        expect(third.read(gymBrandColoursEnabledProvider), isTrue);
        await pumpEventQueue();
        expect(third.read(gymBrandColoursEnabledProvider), isFalse);
        expect(Dependencies.flagCache.read(Flags.gymBrandColours), isFalse);
      },
    );

    test('the kept flag answer is a bool or nothing', () async {
      SharedPreferences.setMockInitialValues({
        PrefsFlagCache.keyFor(Flags.gymBrandColours): 'yes',
      });
      final cache = PrefsFlagCache(await SharedPreferences.getInstance());
      expect(cache.read(Flags.gymBrandColours), isNull);
      await cache.write(Flags.gymBrandColours, value: true);
      expect(cache.read(Flags.gymBrandColours), isTrue);
    });

    test('switching workspace switches the colour', () async {
      final both = [inGym(yellow), inGym(navy, id: 'm2')];
      final c = await app(snapshot(both, active: 'm1'));
      await pumpEventQueue();
      final gyms = c.read(gymControllerProvider.notifier) as _Gyms;
      expect(c.read(activeBrandColorProvider), yellowColor);
      gyms.show(snapshot(both, active: 'm2'));
      expect(c.read(activeBrandColorProvider), navyColor);
      gyms.show(snapshot(both));
      expect(c.read(activeBrandColorProvider), isNull);
    });

    test(
      'a new colour during a workout: the workout repository is not rebuilt',
      () async {
        SharedPreferences.setMockInitialValues({});
        final local = LocalWorkoutRepository(
          await SharedPreferences.getInstance(),
        );
        final c = await app(
          snapshot([inGym(yellow)], active: 'm1'),
          more: [
            ...gymProviderOverrides,
            localWorkoutRepositoryProvider.overrideWithValue(local),
            gymPlanRepositoryProvider.overrideWithValue(FakePlanServer()),
            gymPlanStoreProvider.overrideWithValue(MemoryPlanStore()),
            sessionOutboxProvider.overrideWithValue(MemoryOutbox()),
          ],
        );
        await pumpEventQueue();
        var membershipChanges = 0;
        c.listen(activeMembershipProvider, (_, _) => membershipChanges++);
        final repository = c.read(workoutRepositoryProvider);
        (c.read(gymControllerProvider.notifier) as _Gyms).show(
          snapshot([inGym(navy)], active: 'm1'),
        );

        expect(c.read(activeBrandColorProvider), navyColor);
        expect(membershipChanges, 0);
        expect(
          identical(c.read(workoutRepositoryProvider), repository),
          isTrue,
        );
      },
    );
  });

  group('BrandThemeHost', () {
    Future<void> pumpHost(WidgetTester tester, Color? color) => tester.pumpApp(
      ProviderScope(
        overrides: [activeBrandColorProvider.overrideWithValue(color)],
        child: const BrandThemeHost(
          child: Column(
            children: [
              _Probe(key: Key('inside')),
              AzmTheme(child: _Probe(key: Key('azm'))),
            ],
          ),
        ),
      ),
    );

    Color brandOf(WidgetTester tester, String key) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    testWidgets('a gym colour reaches what is inside; AzmTheme stays Azm', (
      tester,
    ) async {
      await pumpHost(tester, yellowColor);
      await tester.pumpAndSettle();
      final rule = BrandColorRule.derive((0xFA, 0xCC, 0x15), dark: false);
      expect(brandOf(tester, 'inside'), BrandColors.toColor(rule.brand));
      expect(brandOf(tester, 'azm'), AppColors.primary);
    });

    testWidgets('no gym colour: the app theme object itself, nothing new', (
      tester,
    ) async {
      await pumpHost(tester, null);
      await tester.pumpAndSettle();
      expect(brandOf(tester, 'inside'), AppColors.primary);
      final host = tester.widget<AnimatedTheme>(
        find.descendant(
          of: find.byType(BrandThemeHost),
          matching: find.byType(AnimatedTheme),
        ),
      );
      expect(identical(host.data, AppTheme.light), isTrue);
    });

    testWidgets('the colour fades in 200 ms, or at once with Reduce Motion', (
      tester,
    ) async {
      await pumpHost(tester, null);
      await pumpHost(tester, navyColor);
      await tester.pump(const Duration(milliseconds: 100));
      final half = brandOf(tester, 'inside');
      expect(half, isNot(AppColors.primary));
      expect(half, isNot(navyColor));
      await tester.pumpAndSettle();
      expect(brandOf(tester, 'inside'), navyColor);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpHost(tester, yellowColor);
      await tester.pump();
      await tester.pump();
      final rule = BrandColorRule.derive((0xFA, 0xCC, 0x15), dark: false);
      expect(brandOf(tester, 'inside'), BrandColors.toColor(rule.brand));
    });
  });

  screensUiTests({
    'gym_colour_yellow_home': () => themed(
      yellowColor,
      home.view(
        AsyncData(home.day1Waiting()),
        onStart: () {},
        onOpenWorkspace: () {},
      ),
    ),
    'gym_colour_navy_home': () => themed(
      navyColor,
      home.view(
        AsyncData(home.day1Waiting()),
        onStart: () {},
        onOpenWorkspace: () {},
      ),
    ),
    'gym_colour_yellow_workout': () =>
        themed(yellowColor, workout.view(AsyncData(workout.logging()))),
    'gym_colour_navy_rest': () =>
        themed(navyColor, workout.view(AsyncData(workout.resting()))),
  });
}

class _Probe extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: ColoredBox(color: context.palette.brand),
  );
}
