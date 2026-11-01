import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/rest_on_time_sheet.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/ui_check.dart';

/// Opens the sheet from a button, like the workout screen does.
class _Opener extends StatelessWidget {
  const new({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: Center(
      child: AppPrimaryButton(
        label: 'Open',
        onPressed: () async => onResult(await showRestOnTimeSheet(context)),
      ),
    ),
  );
}

/// The sheet on a screen-sized surface, as it looks over the workout.
class _Shown extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const AppScaffold(
    body: Align(
      alignment: AlignmentDirectional.bottomCenter,
      child: Material(child: RestOnTimeSheet()),
    ),
  );
}

void main() {
  for (final (key, expected) in [
    ('rest_on_time_open', true),
    ('rest_on_time_later', false),
  ]) {
    testWidgets('$key → $expected', (tester) async {
      bool? result;
      await tester.pumpApp(_Opener(onResult: (r) => result = r));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Ring when your rest is over?'), findsOneWidget);
      expect(
        find.textContaining('Alarms & reminders'),
        findsOneWidget,
        reason: 'names the Android setting to turn on',
      );
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(result, expected);
    });
  }

  testWidgets('dismissed by dragging down: false', (tester) async {
    bool? result;
    await tester.pumpApp(_Opener(onResult: (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('Arabic', (tester) async {
    await tester.pumpApp(const _Shown(), locale: const Locale('ar'));
    expect(find.text('نرنّلك لما الراحة تخلص؟'), findsOneWidget);
    expect(find.text('افتح الإعدادات'), findsOneWidget);
    expect(find.text('مش دلوقتي'), findsOneWidget);
  });

  screenUiTests('rest_on_time_sheet', () => const _Shown());
}
