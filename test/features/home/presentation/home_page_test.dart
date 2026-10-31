import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/home/presentation/home_page.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group(HomePage, () {
    testWidgets('shows the welcome message and a settings button', (
      tester,
    ) async {
      await tester.pumpApp(const HomePage());

      expect(find.text(l10nEn.homeWelcome), findsOneWidget);
      expect(find.byKey(const Key('home_settings_button')), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(const HomePage());
      await tester.expectAccessible();
    });

    testWidgets('renders right-to-left in Arabic', (tester) async {
      await tester.pumpApp(const HomePage(), locale: const Locale('ar'));

      final direction = Directionality.of(
        tester.element(find.byType(Text).last),
      );
      expect(direction, TextDirection.rtl);
    });
  });
}
