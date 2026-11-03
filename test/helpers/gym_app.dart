import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/router_refresh.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_solo_import.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_camera.dart';
import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gym_fakes.dart';
import 'solo_fakes.dart';

/// A fake camera: tests call [scan] as if the camera had read a QR, or
/// [fail] as if it could not start.
class FakeCamera {
  ValueChanged<String?>? _onScanned;
  ValueChanged<CameraProblem>? _onProblem;

  void scan(String? raw) => _onScanned?.call(raw);
  void fail(CameraProblem problem) => _onProblem?.call(problem);

  ScannerCameraBuilder get builder =>
      (context, {required onScanned, required onProblem}) {
        _onScanned = onScanned;
        _onProblem = onProblem;
        return const ColoredBox(key: Key('fake_camera'), color: Colors.black);
      };
}

/// The whole app (router, providers) with fake gym repositories. [Dependencies]
/// is where the router reads the session, so it is set here and put back by
/// [GymApp.tearDown].
class GymApp {
  new({
    AccountSession session = AccountSession.signedOut,
    this.withPlan = true,
    this.history = const [],
    bool onboardingDone = true,
    this._flagOn = true,
  }) : account = FakeAccountRepository(session),
       gyms = FakeGymRepository(),
       local = InMemoryGymLocalRepository(onboardingDone: onboardingDone),
       camera = FakeCamera();

  final FakeAccountRepository account;
  final FakeGymRepository gyms;
  final InMemoryGymLocalRepository local;
  final FakeCamera camera;
  final bool _flagOn;
  final bool withPlan;
  final List<WorkoutSession> history;
  final InMemorySoloImportStore soloStore = InMemorySoloImportStore();
  final FakeSoloServer soloServer = FakeSoloServer();
  late SharedPreferences prefs;

  void tearDown() {
    FeatureFlags.overrides.clear();
    Dependencies.accountRepository = FakeAccountRepository();
    Dependencies.gymLocalRepository = InMemoryGymLocalRepository();
    Dependencies.soloImportStore = InMemorySoloImportStore();
    Dependencies.soloImportRepository =
        const UnconfiguredSoloImportRepository();
  }

  Future<void> pump(
    WidgetTester tester, {
    List<Override> overrides = const [],
    String? at,
  }) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(tearDown);
    // A new app, not the previous one with new overrides.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues({
      if (withPlan) LocalWorkoutRepository.planKey: _planJson,
      if (history.isNotEmpty)
        LocalWorkoutRepository.historyKey: jsonEncode([
          for (final s in history) s.toJson(),
        ]),
    });
    prefs = await SharedPreferences.getInstance();
    FeatureFlags.overrides[Flags.gymJoin] = _flagOn;
    Dependencies.accountRepository = account;
    Dependencies.gymRepository = gyms;
    Dependencies.gymLocalRepository = local;
    Dependencies.soloImportStore = soloStore;
    Dependencies.soloImportRepository = soloServer;
    Dependencies.workoutRepository = LocalWorkoutRepository(prefs);
    routerRefresh.attach(account.sessionChanges);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerCameraBuilderProvider.overrideWithValue(camera.builder),
          settingsRepositoryProvider.overrideWithValue(
            SharedPrefsSettingsRepository(prefs),
          ),
          ...overrides,
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The router is one global object: each test starts it where it wants.
    appRouter.go(at ?? '/');
    await tester.pumpAndSettle();
  }
}

final String _planJson = jsonEncode(PlanTemplates.fiveDaySplit.toJson());
