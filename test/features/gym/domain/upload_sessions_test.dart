import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/usecases/upload_sessions.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/plan_sync_fakes.dart';

WorkoutSession session(int i, {String? membershipId = 'm1'}) => WorkoutSession(
  dayId: 'day-1',
  finishedAt: DateTime.utc(2026, 10).add(Duration(hours: i)),
  sets: [LoggedSet(exerciseId: 'bench', weight: 50 + i.toDouble(), reps: 10)],
  membershipId: membershipId,
);

void main() {
  late MemoryOutbox outbox;
  late FakeUploader uploader;

  setUp(() {
    outbox = MemoryOutbox();
    uploader = FakeUploader();
  });

  Future<void> queue(WorkoutSession s) =>
      QueueSession(outbox)(s, gymId: 'g1', membershipId: 'm1');

  test(
    'the same workout queued twice is one entry (id = content hash)',
    () async {
      await queue(session(1));
      await queue(session(1));
      await queue(session(2));
      expect(outbox.entries, hasLength(2));
      expect(outbox.entries.first.clientId, matches(RegExp(r'^[0-9a-f]{64}$')));
    },
  );

  test(
    'uploads in chunks of 50, oldest first, and empties the queue',
    () async {
      for (var i = 120; i > 0; i--) {
        await queue(session(i));
      }
      final left = await UploadSessions(outbox, uploader)();
      expect((left as Success<int>).value, 0);
      expect(uploader.chunkSizes, [50, 50, 20]);
      expect(uploader.stored, hasLength(120));
      expect(outbox.entries, isEmpty);
    },
  );

  test('a failure keeps the unconfirmed entries; the retry finishes', () async {
    for (var i = 0; i < 70; i++) {
      await queue(session(i));
    }
    uploader.script.addAll(['ok', 'fail']);
    final first = await UploadSessions(outbox, uploader)();
    expect(first, isA<Failed<int>>());
    expect(outbox.entries, hasLength(20), reason: 'the first 50 are confirmed');
    final second = await UploadSessions(outbox, uploader)();
    expect((second as Success<int>).value, 0);
    expect(uploader.stored, hasLength(70));
  });

  test('a lost answer: sending again stores nothing twice', () async {
    await queue(session(1));
    await UploadSessions(outbox, uploader)();
    // The server has it, but suppose the phone never heard: queue it again.
    await queue(session(1));
    await UploadSessions(outbox, uploader)();
    expect(uploader.stored, hasLength(1));
  });

  test('a gym that refuses its rows does not hold back the others', () async {
    await queue(session(1));
    await QueueSession(outbox)(session(2), gymId: 'g2', membershipId: 'm2');
    uploader.denied.add('m1');
    final r = await UploadSessions(outbox, uploader)();
    expect((r as Success<int>).value, 1);
    expect(uploader.stored.values.single.membershipId, 'm2');
    expect(outbox.entries.single.membershipId, 'm1', reason: 'kept, not lost');
  });

  test('an empty queue calls nothing', () async {
    await UploadSessions(outbox, uploader)();
    expect(uploader.calls, 0);
  });

  test(
    'the phone keeps the workout in its own history (the outbox is a copy)',
    () async {
      await queue(session(1));
      final entry = outbox.entries.single;
      expect(entry.session.membershipId, 'm1');
      expect(entry.gymId, 'g1');
    },
  );

  group('PlanPermissions', () {
    test('solo and managers may do everything', () {
      expect(PlanPermissions.of(null), PlanPermissions.solo);
      for (final role in [GymRole.owner, GymRole.captain]) {
        expect(PlanPermissions.of(member(role: role)), PlanPermissions.solo);
      }
    });

    test('a trainee gets exactly what the captain switched on', () {
      final none = PlanPermissions.of(
        member(permissions: const GymPermissions()),
      );
      expect(
        [none.editTargets, none.editStructure, none.buildOwnPlan],
        [false, false, false],
      );
      expect(none.readOnly, isTrue);

      final targets = PlanPermissions.of(member());
      expect([targets.editTargets, targets.editStructure], [true, false]);

      final plan = PlanPermissions.of(
        member(permissions: const GymPermissions(editPlan: true)),
      );
      expect(
        [plan.editTargets, plan.editStructure],
        [true, true],
        reason: 'edit plan implies edit targets',
      );

      final own = PlanPermissions.of(
        member(permissions: const GymPermissions(buildOwnPlan: true)),
      );
      expect(own.buildOwnPlan, isTrue);
      expect(own.editTargets, isFalse);
    });

    test('an ended membership may change nothing', () {
      final ended = PlanPermissions.of(member(status: MembershipStatus.ended));
      expect(ended, PlanPermissions.none);
      expect(ended.canSave, isFalse);
    });
  });
}
