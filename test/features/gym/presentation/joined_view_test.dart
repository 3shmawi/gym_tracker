import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/gym_logo_fakes.dart';
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

    testWidgets("the gym's logo over its letters, once it is on the phone", (
      tester,
    ) async {
      await tester.pumpApp(
        JoinedView(joined: joinedGym(), onStart: () {}, logo: testLogoImage),
      );
      await tester.runAsync(
        () => precacheImage(
          testLogoImage,
          tester.element(find.byType(JoinedView)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      // The letters stay underneath: shown while it loads or if it fails.
      expect(find.text('IH'), findsOneWidget);
      expect(find.bySemanticsLabel('IH'), findsNothing, reason: 'decoration');
    });

    testWidgets("the letters take the gym's colour, with readable text", (
      tester,
    ) async {
      const yellow = Color(0xFFFACC15);
      await tester.pumpApp(
        JoinedView(joined: joinedGym(), onStart: () {}, color: yellow),
      );
      final expected = BrandColors.fromSeed(yellow, Brightness.light);
      expect(
        tester.widget<Text>(find.text('IH')).style!.color,
        expected.onBrand,
      );
      // Whatever the colour, light or dark: 4.5:1 for the letters.
      for (final seed in const [
        yellow,
        Color(0xFF1E3A8A),
        Color(0xFFDC2626),
        Color(0xFF22C55E),
      ]) {
        for (final b in Brightness.values) {
          final c = BrandColors.fromSeed(seed, b);
          expect(
            BrandColorRule.passes(
              BrandColors.toRgb(c.onBrand),
              BrandColors.toRgb(c.brand),
              9,
              2,
            ),
            isTrue,
            reason: '$seed $b',
          );
        }
      }
      // No colour chosen: the design's gradient and white letters.
      await tester.pumpApp(JoinedView(joined: joinedGym(), onStart: () {}));
      expect(tester.widget<Text>(find.text('IH')).style!.color, Colors.white);
    });

    testWidgets('a logo that cannot load leaves the letters', (tester) async {
      await tester.pumpApp(
        JoinedView(
          joined: joinedGym(),
          onStart: () {},
          logo: MemoryImage(Uint8List.fromList([1, 2, 3])),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('IH'), findsOneWidget);
    });

    testWidgets('the logo fades in, or appears at once with Reduce Motion', (
      tester,
    ) async {
      for (final still in [false, true]) {
        await tester.pumpApp(
          MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: JoinedView(
              joined: joinedGym(),
              onStart: () {},
              logo: MemoryImage(testLogoPng),
            ),
          ),
        );
        final fade = tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(JoinedView),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(fade.opacity, 0, reason: 'not decoded yet');
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(testLogoPng),
            tester.element(find.byType(JoinedView)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
          still ? Duration.zero : isNot(Duration.zero),
          reason: still ? 'Reduce Motion' : 'fade',
        );
      }
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(JoinedView(joined: joinedGym(), onStart: () {}));
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'joined_trainee': () => JoinedView(joined: joinedGym(), onStart: () {}),
    'joined_brand_color': () => JoinedView(
      joined: joinedGym(),
      onStart: () {},
      color: const Color(0xFFFACC15),
    ),
    'joined_with_logo': () =>
        JoinedView(joined: joinedGym(), onStart: () {}, logo: testLogoImage),
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
