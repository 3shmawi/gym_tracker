import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/presentation/delete_account_view.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';
import 'package:gym_tracker/features/gym/presentation/profile_view.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_camera.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_view.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';

import '../../../helpers/gym_app.dart';
import '../../../helpers/gym_fakes.dart';
import '../../../helpers/home_menu.dart';
import '../../../helpers/pump_app.dart';

/// The member's journey through the gym screens, with fake repositories.
void main() {
  Finder field() => find.descendant(
    of: find.byKey(const Key('join_code')),
    matching: find.byType(TextField),
  );

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(field(), code);
    await tester.pump();
  }

  Future<void> tapJoin(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('join_submit')));
    await tester.pumpAndSettle();
  }

  group('typing a code', () {
    testWidgets('joins, shows "Welcome", then opens today\'s workout', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join');
      await typeCode(tester, 'k7m2qx');
      await tapJoin(tester);

      expect(find.byType(JoinedView), findsOneWidget);
      expect(find.text(l10nEn.joinedWelcome('Iron House')), findsOneWidget);
      expect(app.gyms.redeemed, [testCode]);
      expect(app.local.workspace, const GymWorkspace('m1'));

      await tester.tap(find.byKey(const Key('joined_start')));
      await tester.pumpAndSettle();
      expect(find.byType(NextWorkoutPage), findsOneWidget);
    });

    testWidgets('a wrong code is shown in the field and can be corrected', (
      tester,
    ) async {
      final app = GymApp();
      app.gyms.redeemResult = const Failed(
        InviteFailure(InviteProblem.invalid),
      );
      await app.pump(tester, at: '/join');
      await typeCode(tester, 'K7M2QZ');
      await tapJoin(tester);

      expect(find.text(l10nEn.joinInvalidInline), findsOneWidget);
      expect(find.byType(JoinedView), findsNothing);

      app.gyms.redeemResult = Success(joinedGym());
      await typeCode(tester, 'K7M2QX');
      expect(find.text(l10nEn.joinInvalidInline), findsNothing);
      await tapJoin(tester);
      expect(find.byType(JoinedView), findsOneWidget);
    });

    for (final (problem, title) in [
      (InviteProblem.expired, l10nEn.joinExpiredTitle),
      (InviteProblem.used, l10nEn.joinUsedTitle),
      (InviteProblem.conflict, l10nEn.joinConflictTitle),
      (InviteProblem.throttled, l10nEn.joinThrottledTitle),
    ]) {
      testWidgets('$problem opens a sheet and never a dead end', (
        tester,
      ) async {
        final app = GymApp();
        app.gyms.redeemResult = Failed(InviteFailure(problem));
        await app.pump(tester, at: '/join');
        await typeCode(tester, 'K7M2QX');
        await tapJoin(tester);

        expect(find.text(title), findsOneWidget);
        await tester.tap(find.byKey(const Key('join_outcome_primary')));
        await tester.pumpAndSettle();
        expect(find.text(title), findsNothing);
        expect(find.byType(JoinedView), findsNothing);
        expect(app.local.workspace, const SoloWorkspace());
      });
    }

    testWidgets('"type another code" clears the boxes', (tester) async {
      final app = GymApp();
      app.gyms.redeemResult = const Failed(InviteFailure(InviteProblem.used));
      await app.pump(tester, at: '/join/K7M2QX');
      expect(tester.widget<TextField>(field()).controller!.text, 'K7M2QX');
      await tapJoin(tester);
      await tester.tap(find.byKey(const Key('join_outcome_secondary')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    });

    testWidgets('offline: the sheet offers to try again with the same code', (
      tester,
    ) async {
      final app = GymApp();
      app.gyms.redeemResult = offline;
      await app.pump(tester, at: '/join');
      await typeCode(tester, 'K7M2QX');
      await tapJoin(tester);
      expect(find.text(l10nEn.scanOfflineTitle), findsOneWidget);

      app.gyms.redeemResult = Success(joinedGym());
      await tester.tap(find.byKey(const Key('join_outcome_primary')));
      await tester.pumpAndSettle();
      expect(app.gyms.redeemed, [testCode, testCode]);
      expect(find.byType(JoinedView), findsOneWidget);
    });

    testWidgets('a second tap while joining sends nothing more', (
      tester,
    ) async {
      final app = GymApp();
      app.gyms.hold = Completer<void>();
      await app.pump(tester, at: '/join');
      await typeCode(tester, 'K7M2QX');
      await tester.tap(find.byKey(const Key('join_submit')));
      await tester.pump();
      expect(find.text(l10nEn.joinInProgress), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('join_submit')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(app.gyms.redeemed, hasLength(1));
      app.gyms.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(JoinedView), findsOneWidget);
    });

    testWidgets('a link only fills the code; nothing is sent until the tap', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/K7M2QX');
      await tester.pump(const Duration(seconds: 3));
      expect(app.gyms.redeemed, isEmpty);
      await tapJoin(tester);
      expect(app.gyms.redeemed, [testCode]);
    });
  });

  group('the scanner', () {
    testWidgets('a scanned QR joins at once', (tester) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/scan');
      expect(find.byType(ScannerView), findsOneWidget);
      expect(find.byKey(const Key('fake_camera')), findsOneWidget);

      app.camera.scan('https://azmm.pages.dev/join/K7M2QX');
      await tester.pumpAndSettle();
      expect(app.gyms.redeemed, [testCode]);
      expect(find.byType(JoinedView), findsOneWidget);
    });

    testWidgets('the bare code and azm:// links work too', (tester) async {
      for (final raw in ['K7M2QX', 'azm://join/K7M2QX']) {
        final app = GymApp();
        await app.pump(tester, at: '/join/scan');
        app.camera.scan(raw);
        await tester.pumpAndSettle();
        expect(app.gyms.redeemed, [testCode], reason: raw);
      }
    });

    testWidgets('someone else\'s QR is "invalid" and is never sent', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/scan');
      for (final raw in [
        'https://evil.example/join/K7M2QX',
        'WIFI:S:cafe;T:WPA;P:secret;;',
        'javascript:alert(1)',
        'https://azmm.pages.dev/join/K7M2QX?x=1',
        '',
      ]) {
        app.camera.scan(raw);
        await tester.pumpAndSettle();
        expect(find.text(l10nEn.joinInvalidTitle), findsOneWidget, reason: raw);
        await tester.tap(find.byKey(const Key('join_outcome_primary')));
        await tester.pumpAndSettle();
      }
      expect(app.gyms.redeemed, isEmpty);
    });

    testWidgets('the same frame read many times opens one sheet', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/scan');
      app.camera.scan('nope');
      app.camera.scan('nope');
      app.camera.scan('nope');
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.joinInvalidTitle), findsOneWidget);
    });

    testWidgets('a server refusal opens the same sheets', (tester) async {
      final app = GymApp();
      app.gyms.redeemResult = const Failed(
        InviteFailure(InviteProblem.expired),
      );
      await app.pump(tester, at: '/join/scan');
      app.camera.scan('K7M2QX');
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.joinExpiredTitle), findsOneWidget);
      // "Type another code" leaves for the keyboard screen.
      await tester.tap(find.byKey(const Key('join_outcome_secondary')));
      await tester.pumpAndSettle();
      expect(field(), findsOneWidget);
    });

    testWidgets('offline: a full-screen state that retries the same code', (
      tester,
    ) async {
      final app = GymApp();
      app.gyms.redeemResult = offline;
      await app.pump(tester, at: '/join/scan');
      app.camera.scan('K7M2QX');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scanner_offline')), findsOneWidget);

      app.gyms.redeemResult = Success(joinedGym());
      await tester.tap(find.byKey(const Key('scanner_primary')));
      await tester.pumpAndSettle();
      expect(app.gyms.redeemed, [testCode, testCode]);
      expect(find.byType(JoinedView), findsOneWidget);
    });

    testWidgets('camera denied and unavailable are never dead ends', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/scan');
      app.camera.fail(CameraProblem.denied);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scanner_denied')), findsOneWidget);
      await tester.tap(find.byKey(const Key('scanner_type_code')));
      await tester.pumpAndSettle();
      expect(field(), findsOneWidget, reason: 'typing the code still works');

      final other = GymApp();
      await other.pump(tester, at: '/join/scan');
      other.camera.fail(CameraProblem.unavailable);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scanner_unavailable')), findsOneWidget);
    });

    testWidgets('close goes back to the first screen when nothing is behind', (
      tester,
    ) async {
      final app = GymApp();
      await app.pump(tester, at: '/join/scan');
      await tester.tap(find.byKey(const Key('scanner_close')));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeView), findsOneWidget);
    });
  });

  group('the first screen', () {
    testWidgets('is asked once, on a fresh install with the flag on', (
      tester,
    ) async {
      final app = GymApp(withPlan: false, onboardingDone: false);
      await app.pump(tester);
      expect(find.byType(WelcomeView), findsOneWidget);

      await tester.tap(find.byKey(const Key('welcome_solo')));
      await tester.pumpAndSettle();
      expect(find.byType(NextWorkoutPage), findsOneWidget);
      expect(app.local.onboardingDone, isTrue);
    });

    testWidgets('"join" opens the scanner, "I have a code" the keyboard', (
      tester,
    ) async {
      final app = GymApp(withPlan: false, onboardingDone: false);
      await app.pump(tester);
      await tester.tap(find.byKey(const Key('welcome_join')));
      await tester.pumpAndSettle();
      expect(find.byType(ScannerView), findsOneWidget);

      await tester.tap(find.byKey(const Key('scanner_type_code')));
      await tester.pumpAndSettle();
      expect(field(), findsOneWidget);
    });

    testWidgets('is never asked of people who already have a plan', (
      tester,
    ) async {
      final app = GymApp(onboardingDone: false);
      await app.pump(tester);
      expect(find.byType(NextWorkoutPage), findsOneWidget);
      expect(app.local.onboardingDone, isTrue, reason: 'remembered');
    });

    testWidgets('is never asked of people who are signed in', (tester) async {
      final app = GymApp(
        session: anonymousSession,
        withPlan: false,
        onboardingDone: false,
      );
      await app.pump(tester);
      expect(find.byType(NextWorkoutPage), findsOneWidget);
    });

    testWidgets('does not exist while the flag is off', (tester) async {
      final app = GymApp(withPlan: false, onboardingDone: false, flagOn: false);
      await app.pump(tester);
      expect(find.byType(NextWorkoutPage), findsOneWidget);
      await app.pump(tester, at: '/welcome');
      expect(find.byType(WelcomeView), findsNothing);
    });
  });

  group('the account', () {
    testWidgets('home gets a switcher button only with an account', (
      tester,
    ) async {
      final signedOut = GymApp();
      await signedOut.pump(tester);
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_workspace_button')), findsNothing);
      // Training alone: joining a gym is one of the menu's rows.
      expect(find.byKey(const Key('home_join_gym_button')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      final signedIn = GymApp(session: anonymousSession);
      signedIn.local
        ..memberships = [member(), member(id: 'm2', gym: 'Peak Fitness')]
        ..workspace = const GymWorkspace('m1');
      signedIn.gyms.membershipsResult = Success(signedIn.local.memberships);
      await signedIn.pump(tester);
      await openHomeMenu(tester);
      expect(find.byKey(const Key('home_join_gym_button')), findsNothing);
      await tester.tap(find.byKey(const Key('home_workspace_button')));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.switchTitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('workspace_m2')));
      await tester.pumpAndSettle();
      expect(signedIn.local.workspace, const GymWorkspace('m2'));

      await openHomeMenu(tester);
      await tester.tap(find.byKey(const Key('home_workspace_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspace_solo')));
      await tester.pumpAndSettle();
      expect(signedIn.local.workspace, const SoloWorkspace());
    });

    testWidgets('sign out asks first, then leaves the account', (tester) async {
      final app = GymApp(session: anonymousSession);
      app.local.memberships = [member()];
      app.gyms.membershipsResult = Success([member()]);
      await app.pump(tester, at: '/profile');
      expect(find.byType(ProfileView), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile_sign_out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign_out_stay')));
      await tester.pumpAndSettle();
      expect(app.account.signOuts, 0);

      await tester.tap(find.byKey(const Key('profile_sign_out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign_out_confirm')));
      await tester.pumpAndSettle();
      expect(app.account.signOuts, 1);
      expect(find.byType(NextWorkoutPage), findsOneWidget);
      expect(app.local.workspace, const SoloWorkspace());
      expect(app.local.memberships, isEmpty);
    });

    testWidgets('a session ended elsewhere leaves a protected screen', (
      tester,
    ) async {
      final app = GymApp(session: anonymousSession);
      await app.pump(tester, at: '/profile');
      expect(find.byType(ProfileView), findsOneWidget);
      app.account.emit(AccountSession.signedOut);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileView), findsNothing);
      expect(find.byType(WelcomeView), findsOneWidget);
    });

    testWidgets('a revoked session puts the person back in solo', (
      tester,
    ) async {
      final app = GymApp(session: anonymousSession);
      app.local
        ..workspace = const GymWorkspace('m1')
        ..memberships = [member()];
      app.gyms.membershipsResult = Success([member()]);
      await app.pump(tester);
      app.account.emit(AccountSession.signedOut);
      await tester.pumpAndSettle();
      expect(app.local.workspace, const SoloWorkspace());
      expect(app.local.memberships, isEmpty);
    });

    testWidgets('deleting: erase-local choice, then the server, then home', (
      tester,
    ) async {
      final app = GymApp(session: anonymousSession);
      app.local.memberships = [member()];
      app.gyms.membershipsResult = Success([member()]);
      await app.pump(tester, at: '/profile/delete');
      expect(find.byType(DeleteAccountView), findsOneWidget);
      expect(find.byKey(const Key('delete_owner_name')), findsNothing);

      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();
      expect(app.account.deletes, 1);
      expect(find.byType(NextWorkoutPage), findsOneWidget);
    });

    testWidgets('an owner types the gym name; a last owner is told why', (
      tester,
    ) async {
      final app = GymApp(session: emailSession);
      final owner = member(role: GymRole.owner);
      app.local.memberships = [owner];
      app.gyms.membershipsResult = Success([owner]);
      app.account.deleteResult = const Failed(LastOwnerFailure(['Iron House']));
      await app.pump(tester, at: '/profile/delete');

      final scrollable = find
          .descendant(
            of: find.byType(DeleteAccountView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('delete_owner_name')),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.byKey(const Key('delete_owner_name')),
        'Iron House',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();
      expect(app.account.deletes, 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('delete_last_owner')),
        100,
        scrollable: scrollable,
      );
      expect(find.byKey(const Key('delete_last_owner')), findsOneWidget);
      expect(find.byType(DeleteAccountView), findsOneWidget);
    });

    testWidgets('settings offers the right door', (tester) async {
      final out = GymApp();
      await out.pump(tester, at: '/settings');
      expect(find.byKey(const Key('settings_join_gym')), findsOneWidget);
      expect(find.byKey(const Key('settings_account')), findsNothing);

      final signedIn = GymApp(session: anonymousSession);
      await signedIn.pump(tester, at: '/settings');
      expect(find.byKey(const Key('settings_account')), findsOneWidget);
      expect(find.byKey(const Key('settings_join_gym')), findsNothing);
    });

    testWidgets('settings shows no gym section while the flag is off', (
      tester,
    ) async {
      final app = GymApp(flagOn: false);
      await app.pump(tester, at: '/settings');
      expect(find.byKey(const Key('settings_join_gym')), findsNothing);
      expect(find.byKey(const Key('settings_account')), findsNothing);
    });
  });
}
