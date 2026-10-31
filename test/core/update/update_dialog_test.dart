import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/update/app_version.dart';
import 'package:gym_tracker/core/update/update_dialog.dart';
import 'package:gym_tracker/core/update/update_info.dart';

import '../../helpers/pump_app.dart';

void main() {
  UpdateInfo info(UpdateType type) => UpdateInfo(
    type: type,
    current: const AppVersion(1, 0, 0),
    config: const VersionConfig(
      latest: AppVersion(1, 1, 0),
      minSupported: AppVersion(1, 0, 0),
      storeUrl: 'https://example.com',
      changelogEn: 'Faster search',
    ),
  );

  Future<void> openDialog(WidgetTester tester, UpdateInfo updateInfo) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(showUpdateDialog(context, updateInfo)),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('optional update shows versions, changelog and Later', (
    tester,
  ) async {
    await openDialog(tester, info(UpdateType.optional));

    expect(find.text(l10nEn.updateOptionalTitle), findsOneWidget);
    expect(find.text(l10nEn.updateVersions('1.0.0', '1.1.0')), findsOneWidget);
    expect(find.text('Faster search'), findsOneWidget);
    expect(find.text(l10nEn.updateLater), findsOneWidget);

    await tester.tap(find.text(l10nEn.updateLater));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.updateOptionalTitle), findsNothing);
  });

  testWidgets('force update has no Later and cannot be dismissed', (
    tester,
  ) async {
    await openDialog(tester, info(UpdateType.force));

    expect(find.text(l10nEn.updateForceTitle), findsOneWidget);
    expect(find.text(l10nEn.updateLater), findsNothing);
    expect(find.text(l10nEn.updateNow), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.updateForceTitle), findsOneWidget);
  });
}
