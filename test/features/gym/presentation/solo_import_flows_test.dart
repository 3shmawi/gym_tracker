import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_sheet.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_app.dart';
import '../../../helpers/gym_fakes.dart';
import '../../../helpers/pump_app.dart';

final List<WorkoutSession> workouts = [
  for (var i = 0; i < 3; i++)
    WorkoutSession(
      dayId: 'day-1',
      finishedAt: DateTime.utc(2026, 10, 1 + i, 9),
      sets: const [LoggedSet(exerciseId: 'bench', weight: 50, reps: 12)],
    ),
];

void main() {
  Finder field() => find.descendant(
    of: find.byKey(const Key('join_code')),
    matching: find.byType(TextField),
  );

  Future<GymApp> joinWith(
    WidgetTester tester, {
    List<WorkoutSession>? history,
    bool withPlan = true,
  }) async {
    final app = GymApp(history: history ?? workouts, withPlan: withPlan);
    await app.pump(tester, at: '/join');
    await tester.enterText(field(), 'K7M2QX');
    await tester.pump();
    app.account.emit(anonymousSession);
    await tester.tap(find.byKey(const Key('join_submit')));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets("after joining, the phone's data is asked about once", (
    tester,
  ) async {
    final app = await joinWith(tester);
    expect(find.byType(JoinedView), findsOneWidget);
    expect(find.byType(SoloImportSheet), findsOneWidget);
    expect(find.text(l10nEn.soloBody(3)), findsOneWidget);
    expect(app.soloServer.calls, 0, reason: 'nothing leaves without a choice');
  });

  testWidgets('"keep" (the default) sends nothing and is not asked again', (
    tester,
  ) async {
    final app = await joinWith(tester);
    await tester.tap(find.byKey(const Key('solo_confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(SoloImportSheet), findsNothing);
    expect(app.soloStore.status.choice, SoloImportChoice.keep);
    expect(app.soloServer.calls, 0);
    expect(app.soloServer.stored, isEmpty);
  });

  testWidgets('"add to my account" copies, confirms and keeps the phone copy', (
    tester,
  ) async {
    final app = await joinWith(tester);
    await tester.tap(find.byKey(const Key('solo_copying')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('solo_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('solo_done')), findsOneWidget);
    expect(app.soloServer.stored, hasLength(3));
    expect(app.soloServer.plan, isNotNull);
    expect(app.soloStore.status.choice, SoloImportChoice.done);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalWorkoutRepository.historyKey), isNotNull);
    expect(prefs.getString(LocalWorkoutRepository.planKey), isNotNull);
  });

  testWidgets('a failed copy says nothing was lost and can be retried', (
    tester,
  ) async {
    final app = await joinWith(tester);
    app.soloServer.script.add('before');
    await tester.tap(find.byKey(const Key('solo_copying')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('solo_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('solo_failed')), findsOneWidget);
    expect(app.soloStore.status.choice, SoloImportChoice.copying);

    await tester.tap(find.byKey(const Key('solo_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('solo_done')), findsOneWidget);
    expect(app.soloServer.stored, hasLength(3));
  });

  testWidgets('"skip" is asked again, and there is a row in the profile', (
    tester,
  ) async {
    final app = await joinWith(tester);
    await tester.tap(find.byKey(const Key('solo_skip')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('solo_confirm')));
    await tester.pumpAndSettle();
    expect(app.soloStore.status.choice, SoloImportChoice.skip);

    app.local.memberships = [member()];
    app.gyms.membershipsResult = Success([member()]);
    await app.pump(tester, at: '/profile');
    expect(find.byKey(const Key('profile_solo_import')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile_solo_import')));
    await tester.pumpAndSettle();
    expect(find.byType(SoloImportSheet), findsOneWidget);
  });

  testWidgets('no data on the phone: no question', (tester) async {
    await joinWith(tester, history: const [], withPlan: false);
    expect(find.byType(JoinedView), findsOneWidget);
    expect(find.byType(SoloImportSheet), findsNothing);
  });

  testWidgets('once copied, the profile says so and offers nothing', (
    tester,
  ) async {
    final app = GymApp(session: anonymousSession, history: workouts);
    app.soloStore.status = const SoloImportStatus(
      choice: SoloImportChoice.done,
    );
    app.local.memberships = [member()];
    app.gyms.membershipsResult = Success([member()]);
    await app.pump(tester, at: '/profile');
    expect(find.byKey(const Key('profile_solo_done')), findsOneWidget);
    expect(find.byKey(const Key('profile_solo_import')), findsNothing);
  });

  testWidgets('solo mode, signed out: never asked, nothing sent', (
    tester,
  ) async {
    final app = GymApp(history: workouts);
    await app.pump(tester);
    expect(find.byType(SoloImportSheet), findsNothing);
    expect(app.soloServer.calls, 0);
  });

  testWidgets('a network failure while copying keeps the answer pending', (
    tester,
  ) async {
    final app = await joinWith(tester);
    app.soloServer.script.addAll(['before', 'before', 'before']);
    await tester.tap(find.byKey(const Key('solo_copying')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('solo_confirm')));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.errorNetwork), findsOneWidget);
    expect(app.soloStore.status.choice, isNot(SoloImportChoice.done));
    expect(const NetworkFailure(), isA<AppFailure>());
  });
}
