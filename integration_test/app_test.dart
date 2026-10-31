import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/home/presentation/home_page.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';
import 'package:gym_tracker/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'helpers/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts on home and opens settings', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    expect(find.byType(HomePage), findsOneWidget);

    await tester.tap(find.byKey(const Key('home_settings_button')));
    await tester.pumpAndSettle();
    await beat(tester);

    expect(find.byType(SettingsView), findsOneWidget);
    await beat(tester, 1500);
  });
}
