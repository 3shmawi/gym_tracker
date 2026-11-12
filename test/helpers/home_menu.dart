import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the home screen's menu (the bar's one button).
Future<void> openHomeMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home_menu_button')));
  await tester.pumpAndSettle();
}
