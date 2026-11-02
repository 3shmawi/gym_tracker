import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/workspace_sheet.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/plan_samples.dart' show SheetHost;

GymSnapshot twoGyms({Workspace workspace = const GymWorkspace('m1')}) =>
    GymSnapshot(
      workspace: workspace,
      memberships: [
        member(),
        member(id: 'm2', gym: 'Peak Fitness', role: GymRole.captain),
      ],
    );

final withEnded = GymSnapshot(
  memberships: [
    member(),
    member(
      id: 'm3',
      gym: 'Gold X',
      status: MembershipStatus.ended,
      history: HistoryAfterEnd.locked,
      endedAt: DateTime.utc(2026, 9, 3),
    ),
    member(
      id: 'm4',
      gym: 'Peak Fitness',
      status: MembershipStatus.ended,
      endedAt: DateTime.utc(2026, 10, 12),
    ),
  ],
);

Widget host(GymSnapshot snapshot) => SheetHost(
  background: const SizedBox.expand(),
  open: (context) => showWorkspaceSheet(
    context,
    snapshot: snapshot,
    onPick: (_) {},
    onJoinAnother: () {},
  ),
);

void main() {
  group(WorkspaceSheet, () {
    testWidgets('solo, each active gym, and join another', (tester) async {
      final picked = <Workspace>[];
      var joinMore = 0;
      await tester.pumpApp(
        Material(
          child: WorkspaceSheet(
            snapshot: twoGyms(),
            onPick: picked.add,
            onJoinAnother: () => joinMore++,
          ),
        ),
      );
      expect(find.text(l10nEn.switchTitle), findsOneWidget);
      expect(find.text('Iron House'), findsOneWidget);
      expect(find.text('Peak Fitness'), findsOneWidget);
      await tester.tap(find.byKey(const Key('workspace_m2')));
      await tester.tap(find.byKey(const Key('workspace_solo')));
      await tester.tap(find.byKey(const Key('workspace_join_another')));
      expect(picked, [const GymWorkspace('m2'), const SoloWorkspace()]);
      expect(joinMore, 1);
    });

    testWidgets('exactly one row is selected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpApp(
        Material(
          child: WorkspaceSheet(
            snapshot: twoGyms(),
            onPick: (_) {},
            onJoinAnother: () {},
          ),
        ),
      );
      Iterable<String> selected() => [
        for (final key in ['workspace_solo', 'workspace_m1', 'workspace_m2'])
          if (tester
                  .getSemantics(find.byKey(Key(key)))
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected
                  .toBoolOrNull() ??
              false)
            key,
      ];
      expect(selected(), ['workspace_m1']);
      handle.dispose();
    });

    testWidgets('ended gyms are listed but can never be opened to log', (
      tester,
    ) async {
      final picked = <Workspace>[];
      await tester.pumpApp(
        Material(
          child: WorkspaceSheet(
            snapshot: withEnded,
            onPick: picked.add,
            onJoinAnother: () {},
          ),
        ),
      );
      expect(find.text(l10nEn.switchEndedHeader), findsOneWidget);
      expect(find.text(l10nEn.switchLocked), findsOneWidget);
      expect(find.text(l10nEn.switchReadOnly), findsOneWidget);
      expect(find.text(l10nEn.switchLockedNote), findsOneWidget);
      await tester.tap(find.byKey(const Key('workspace_ended_m3')));
      await tester.tap(find.byKey(const Key('workspace_ended_m4')));
      expect(picked, isEmpty);
    });

    testWidgets('only solo: no ended section, still a way to join', (
      tester,
    ) async {
      await tester.pumpApp(
        Material(
          child: WorkspaceSheet(
            snapshot: const GymSnapshot(),
            onPick: (_) {},
            onJoinAnother: () {},
          ),
        ),
      );
      expect(find.text(l10nEn.switchEndedHeader), findsNothing);
      expect(find.byKey(const Key('workspace_join_another')), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        Material(
          child: WorkspaceSheet(
            snapshot: withEnded,
            onPick: (_) {},
            onJoinAnother: () {},
          ),
        ),
      );
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'workspace_two_gyms': () => host(twoGyms()),
    'workspace_solo_active': () =>
        host(twoGyms(workspace: const SoloWorkspace())),
    'workspace_with_ended': () => host(withEnded),
    'workspace_only_solo': () => host(const GymSnapshot()),
  });
}
