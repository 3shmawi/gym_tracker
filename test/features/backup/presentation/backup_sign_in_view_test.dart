import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_controller.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_view.dart';
import 'package:gym_tracker/l10n/gen/app_localizations.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

BackupSignInView view({
  BackupStep step = BackupStep.email,
  String email = '',
  bool busy = false,
  BackupProblem? problem,
  int resendIn = 0,
  ValueChanged<String>? onSubmitEmail,
  ValueChanged<String>? onSubmitCode,
  VoidCallback? onResend,
  VoidCallback? onChangeEmail,
  VoidCallback? onUseExisting,
  VoidCallback? onDone,
}) => BackupSignInView(
  step: step,
  email: email,
  busy: busy,
  problem: problem,
  resendIn: resendIn,
  onSubmitEmail: onSubmitEmail ?? (_) {},
  onSubmitCode: onSubmitCode ?? (_) {},
  onResend: onResend ?? () {},
  onChangeEmail: onChangeEmail ?? () {},
  onUseExisting: onUseExisting ?? () {},
  onDone: onDone ?? () {},
);

void main() {
  group(BackupSignInView, () {
    testWidgets('the email step: type, send', (tester) async {
      String? sent;
      await tester.pumpApp(view(onSubmitEmail: (e) => sent = e));
      expect(find.text(l10nEn.backupHeadline), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('backup_email')),
        'me@example.com',
      );
      await tester.tap(find.byKey(const Key('backup_send_code')));
      expect(sent, 'me@example.com');
    });

    testWidgets('busy: the button waits', (tester) async {
      var taps = 0;
      await tester.pumpApp(view(busy: true, onSubmitEmail: (_) => taps++));
      await tester.tap(
        find.byKey(const Key('backup_send_code')),
        warnIfMissed: false,
      );
      expect(taps, 0);
    });

    testWidgets('an email the app refuses says so on the field', (
      tester,
    ) async {
      await tester.pumpApp(view(problem: BackupProblem.invalidEmail));
      expect(find.text(l10nEn.backupEmailInvalid), findsOneWidget);
    });

    testWidgets(
      'an email that has an account offers to sign in to it, with the warning',
      (tester) async {
        var used = 0;
        await tester.pumpApp(
          view(problem: BackupProblem.emailTaken, onUseExisting: () => used++),
        );
        expect(find.text(l10nEn.backupEmailTaken), findsOneWidget);
        expect(find.text(l10nEn.backupUseExistingWarning), findsOneWidget);
        await tester.tap(find.byKey(const Key('backup_use_existing')));
        expect(used, 1);
      },
    );

    testWidgets(
      'the code step: six digits enable the button, paste is cleaned',
      (tester) async {
        String? sent;
        await tester.pumpApp(
          view(
            step: BackupStep.code,
            email: 'me@example.com',
            onSubmitCode: (c) => sent = c,
          ),
        );
        expect(
          find.text(l10nEn.backupCodeSent('me@example.com')),
          findsOneWidget,
        );
        // Not enough digits: the button is off.
        await tester.enterText(find.byType(TextField), '12 34');
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('backup_verify')),
          warnIfMissed: false,
        );
        expect(sent, isNull);
        await tester.enterText(find.byType(TextField), '123 456');
        await tester.pump();
        await tester.tap(find.byKey(const Key('backup_verify')));
        expect(sent, '123456');
      },
    );

    testWidgets(
      'a new code: counts down, then works; another email goes back',
      (tester) async {
        var resent = 0;
        var changed = 0;
        await tester.pumpApp(
          view(
            step: BackupStep.code,
            email: 'me@example.com',
            resendIn: 42,
            onResend: () => resent++,
            onChangeEmail: () => changed++,
          ),
        );
        expect(find.text(l10nEn.backupResendIn(42)), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('backup_resend')),
          warnIfMissed: false,
        );
        expect(resent, 0);
        await tester.tap(find.byKey(const Key('backup_change_email')));
        expect(changed, 1);
        await tester.pumpApp(
          view(
            step: BackupStep.code,
            email: 'me@example.com',
            onResend: () => resent++,
          ),
        );
        await tester.tap(find.byKey(const Key('backup_resend')));
        expect(resent, 1);
      },
    );

    testWidgets('a wrong code says so under the boxes', (tester) async {
      await tester.pumpApp(
        view(
          step: BackupStep.code,
          email: 'me@example.com',
          problem: BackupProblem.wrongOrExpired,
        ),
      );
      expect(find.text(l10nEn.backupCodeWrong), findsOneWidget);
    });

    testWidgets('done: says it is saved and closes', (tester) async {
      var closed = 0;
      await tester.pumpApp(view(step: BackupStep.done, onDone: () => closed++));
      expect(find.text(l10nEn.backupDoneTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('backup_done')));
      expect(closed, 1);
    });

    testWidgets('Arabic: the same screens read right to left', (tester) async {
      await tester.pumpApp(view(), locale: const Locale('ar'));
      expect(
        find.text(lookupAppLocalizations(const Locale('ar')).backupHeadline),
        findsOneWidget,
      );
    });
  });

  screensUiTests({
    'backup_email': view,
    'backup_email_invalid': () => view(problem: BackupProblem.invalidEmail),
    'backup_email_taken': () =>
        view(email: 'me@example.com', problem: BackupProblem.emailTaken),
    'backup_email_offline': () =>
        view(email: 'me@example.com', problem: BackupProblem.offline),
    'backup_code': () =>
        view(step: BackupStep.code, email: 'me@example.com', resendIn: 41),
    'backup_code_wrong': () => view(
      step: BackupStep.code,
      email: 'me@example.com',
      problem: BackupProblem.wrongOrExpired,
    ),
    'backup_code_busy': () =>
        view(step: BackupStep.code, email: 'me@example.com', busy: true),
    'backup_done': () => view(step: BackupStep.done),
  });
}
