import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/presentation/home_menu_sheet.dart';

import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('the menu lists its entries, closes, then runs the one tapped', (
    tester,
  ) async {
    var ran = <String>[];
    late BuildContext sheetContext;
    await tester.pumpApp(
      Builder(
        builder: (context) {
          sheetContext = context;
          return const SizedBox.shrink();
        },
      ),
    );
    unawaited(
      showHomeMenu(sheetContext, [
        HomeMenuEntry(
          key: const Key('a'),
          icon: Icons.settings,
          label: 'First',
          onTap: () => ran = [...ran, 'a'],
        ),
        HomeMenuEntry(
          key: const Key('b'),
          icon: Icons.show_chart,
          label: 'Second',
          onTap: () => ran = [...ran, 'b'],
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    // Big rows: at least 48 high.
    expect(tester.getSize(find.byKey(const Key('b'))).height, greaterThan(47));

    await tester.tap(find.byKey(const Key('b')));
    await tester.pumpAndSettle();
    expect(ran, ['b']);
    expect(find.text('Second'), findsNothing, reason: 'the sheet closed');
  });
}
