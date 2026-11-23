import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/presentation/home_menu_sheet.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'plan_samples.dart';

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

  List<HomeMenuEntry> entries({bool gym = false}) => [
    if (gym)
      HomeMenuEntry(
        key: const Key('w'),
        icon: Icons.swap_horiz,
        label: 'Gym or solo',
        detail: 'Switch between your gym and solo',
        secondary: true,
        onTap: () {},
      )
    else
      HomeMenuEntry(
        key: const Key('j'),
        icon: Icons.qr_code_scanner,
        label: 'Join your gym',
        detail: "Scan your gym's code",
        secondary: true,
        onTap: () {},
      ),
    HomeMenuEntry(
      key: const Key('p'),
      icon: Icons.format_list_bulleted,
      label: 'Your plan',
      detail: 'Days, exercises and targets',
      onTap: () {},
    ),
    HomeMenuEntry(
      key: const Key('g'),
      icon: Icons.show_chart,
      label: 'Progress',
      detail: 'Your weights and records',
      onTap: () {},
    ),
    HomeMenuEntry(
      key: const Key('m'),
      icon: Icons.sports_gymnastics,
      label: 'Move · rep games',
      detail: 'Quick rounds, the camera counts',
      onTap: () {},
    ),
    HomeMenuEntry(
      key: const Key('s'),
      icon: Icons.settings,
      label: 'Settings',
      detail: 'Language, theme and more',
      secondary: true,
      onTap: () {},
    ),
  ];

  screensUiTests({
    'home_menu': () => SheetHost(
      background: const SizedBox.expand(),
      open: (context) => showHomeMenu(context, entries()),
    ),
    'home_menu_gym': () => SheetHost(
      background: const SizedBox.expand(),
      open: (context) => showHomeMenu(context, entries(gym: true)),
    ),
  });
}
