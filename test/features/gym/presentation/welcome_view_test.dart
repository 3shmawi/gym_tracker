import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  group(WelcomeView, () {
    testWidgets('three ways forward, each calls its own callback', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpApp(
        WelcomeView(
          onJoin: () => calls.add('join'),
          onSolo: () => calls.add('solo'),
          onHaveCode: () => calls.add('code'),
        ),
      );
      expect(find.text(l10nEn.welcomeTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_join')));
      await tester.tap(find.byKey(const Key('welcome_solo')));
      await tester.tap(find.byKey(const Key('welcome_have_code')));
      expect(calls, ['join', 'solo', 'code']);
    });

    testWidgets('nothing is chosen for the person', (tester) async {
      final calls = <String>[];
      await tester.pumpApp(
        WelcomeView(
          onJoin: () => calls.add('join'),
          onSolo: () => calls.add('solo'),
          onHaveCode: () => calls.add('code'),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(calls, isEmpty);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        WelcomeView(onJoin: () {}, onSolo: () {}, onHaveCode: () {}),
      );
      await tester.expectAccessible();
    });

    testWidgets('has no back button: it is the first screen', (tester) async {
      await tester.pumpApp(
        WelcomeView(onJoin: () {}, onSolo: () {}, onHaveCode: () {}),
      );
      expect(find.byTooltip('Back'), findsNothing);
    });
  });

  screensUiTests({
    'welcome': () =>
        WelcomeView(onJoin: () {}, onSolo: () {}, onHaveCode: () {}),
  });
}
