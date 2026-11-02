import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  group(JoinedView, () {
    testWidgets('names the gym and states exactly what the trainee may do', (
      tester,
    ) async {
      var started = 0;
      await tester.pumpApp(
        JoinedView(joined: joinedGym(), onStart: () => started++),
      );
      expect(find.text(l10nEn.joinedWelcome('Iron House')), findsOneWidget);
      expect(find.text('IH'), findsOneWidget);
      expect(find.text(l10nEn.joinedPermTargets), findsOneWidget);
      expect(find.text(l10nEn.joinedPermPlan), findsOneWidget);
      expect(find.text(l10nEn.joinedPermOwn), findsOneWidget);
      // targets on, plan off, own plan off: one check, two crosses.
      expect(find.byIcon(Icons.check), findsNWidgets(2), reason: 'badge + 1');
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      expect(find.text(l10nEn.joinedPrivacy), findsOneWidget);
      await tester.tap(find.byKey(const Key('joined_start')));
      expect(started, 1);
    });

    testWidgets('editing the whole plan implies editing targets', (
      tester,
    ) async {
      await tester.pumpApp(
        JoinedView(
          joined: joinedGym(permissions: const GymPermissions(editPlan: true)),
          onStart: () {},
        ),
      );
      // badge + targets + plan; own plan off.
      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('a captain sees their role, not a trainee permission card', (
      tester,
    ) async {
      await tester.pumpApp(
        JoinedView(
          joined: joinedGym(role: GymRole.captain),
          onStart: () {},
        ),
      );
      expect(find.text(l10nEn.roleCaptain), findsOneWidget);
      expect(find.text(l10nEn.joinedPermTargets), findsNothing);
    });

    testWidgets('a long or hostile gym name is shown as plain text', (
      tester,
    ) async {
      await tester.pumpApp(
        JoinedView(
          joined: joinedGym(gym: '<b>Iron</b> House ' * 4),
          onStart: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('<b>Iron</b>'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(JoinedView(joined: joinedGym(), onStart: () {}));
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'joined_trainee': () => JoinedView(joined: joinedGym(), onStart: () {}),
    'joined_all_permissions': () => JoinedView(
      joined: joinedGym(
        permissions: const GymPermissions(
          editTargets: true,
          editPlan: true,
          buildOwnPlan: true,
        ),
      ),
      onStart: () {},
    ),
    'joined_captain': () => JoinedView(
      joined: joinedGym(role: GymRole.captain),
      onStart: () {},
    ),
    'joined_long_name': () => JoinedView(
      joined: joinedGym(gym: 'Golden Strength and Fitness'),
      onStart: () {},
    ),
  });
}
