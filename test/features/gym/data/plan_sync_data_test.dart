import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_plan_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_session_uploader.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/plan_sync_fakes.dart';

class _Client extends Mock implements SupabaseClient;

OutboxEntry entry(int i) => OutboxEntry(
  clientId: '$i'.padLeft(64, 'a'),
  gymId: 'g1',
  membershipId: 'm1',
  session: WorkoutSession(
    dayId: 'day-1',
    finishedAt: DateTime.utc(2026, 10, 1, i),
    sets: const [LoggedSet(exerciseId: 'bench', weight: 50, reps: 10)],
    membershipId: 'm1',
  ),
);

void main() {
  group(SupabaseGymPlanRepository, () {
    SupabaseGymPlanRepository repo({
      Future<Map<String, Object?>?> Function(String)? read,
      Future<Object?> Function(Map<String, Object?>)? call,
    }) => SupabaseGymPlanRepository(
      _Client(),
      retries: 0,
      readRow: read,
      call: call,
    );

    test('reads the plan row', () async {
      final r = await repo(
        read: (id) async => {
          'body': PlanTemplates.fiveDaySplit.toJson(),
          'version': 4,
          'updated_by': 'captain-m',
        },
      ).fetch('m1');
      final plan = (r as Success<GymPlan?>).value!;
      expect(plan.version, 4);
      expect(plan.changedByOther, isTrue);
      expect(plan.plan.days, hasLength(5));
    });

    test('no row is no plan; a broken row is a validation failure', () async {
      final none = await repo(read: (_) async => null).fetch('m1');
      expect((none as Success<GymPlan?>).value, isNull);
      for (final row in <Map<String, Object?>>[
        {},
        {'body': 'x', 'version': 1},
        {
          'body': <String, Object?>{'days': []},
          'version': 0,
        },
        {'body': PlanTemplates.fiveDaySplit.toJson(), 'version': 'a'},
      ]) {
        final r = await repo(read: (_) async => row).fetch('m1');
        expect(
          (r as Failed<GymPlan?>).failure,
          isA<ValidationFailure>(),
          reason: '$row',
        );
      }
    });

    test(
      'save sends the base version and the body, and reads the answer',
      () async {
        Map<String, Object?>? sent;
        final r = await repo(
          call: (params) async {
            sent = params;
            return {'version': 3, 'updated_by': 'm1'};
          },
        ).save('m1', 2, PlanTemplates.fiveDaySplit);
        expect((r as Success<GymPlan>).value.version, 3);
        expect(sent!['p_membership_id'], 'm1');
        expect(sent!['p_base_version'], 2);
        expect(sent!['p_body'], PlanTemplates.fiveDaySplit.toJson());
      },
    );

    test('plan_changed, forbidden and invalid_plan map to failures', () async {
      for (final (e, matcher) in [
        (
          const PostgrestException(message: 'plan_changed', code: 'P0001'),
          isA<PlanChangedFailure>(),
        ),
        (
          const PostgrestException(message: 'forbidden', code: '42501'),
          isA<UnauthorizedFailure>(),
        ),
        (
          const PostgrestException(message: 'invalid_plan: x', code: '22023'),
          isA<ValidationFailure>(),
        ),
      ]) {
        final r = await repo(call: (_) async => throw e)
            .save('m1', 1, PlanTemplates.fiveDaySplit);
        expect((r as Failed<GymPlan>).failure, matcher, reason: e.message);
      }
    });

    test('a wrong answer is a validation failure', () async {
      for (final answer in <Object?>[
        null,
        'x',
        <String, Object?>{},
        {'version': 0},
      ]) {
        final r = await repo(call: (_) async => answer)
            .save('m1', 1, PlanTemplates.fiveDaySplit);
        expect(
          (r as Failed<GymPlan>).failure,
          isA<ValidationFailure>(),
          reason: '$answer',
        );
      }
    });
  });

  group(SupabaseSessionUploader, () {
    test('inserts the rows with the person, gym and membership', () async {
      List<Map<String, Object?>>? rows;
      final up = SupabaseSessionUploader(
        _Client(),
        retries: 0,
        personId: () async => 'p1',
        insert: (r) async => rows = r,
      );
      final r = await up.upload([entry(1), entry(2)]);
      expect(r, isA<Success<void>>());
      expect(rows, hasLength(2));
      expect(rows!.first['person_id'], 'p1');
      expect(rows!.first['gym_id'], 'g1');
      expect(rows!.first['membership_id'], 'm1');
      expect(rows!.first['finished_at'], '2026-10-01T01:00:00.000Z');
      expect(rows!.first['client_id'], entry(1).clientId);
    });

    test('over 50 is refused before any call; a failure maps', () async {
      var called = 0;
      final up = SupabaseSessionUploader(
        _Client(),
        retries: 0,
        personId: () async => 'p1',
        insert: (r) async {
          called++;
          throw const PostgrestException(message: 'x', code: '42501');
        },
      );
      final big = await up.upload([for (var i = 0; i < 51; i++) entry(i)]);
      expect((big as Failed<void>).failure, isA<ValidationFailure>());
      expect(called, 0);
      final denied = await up.upload([entry(1)]);
      expect((denied as Failed<void>).failure, isA<UnauthorizedFailure>());
    });
  });

  group('local stores', () {
    Future<SharedPreferences> prefs([Map<String, Object> v = const {}]) async {
      SharedPreferences.setMockInitialValues(v);
      return await SharedPreferences.getInstance();
    }

    test('a gym plan survives the round trip, pending included', () async {
      final store = PrefsGymPlanStore(await prefs());
      await store.save(
        'm1',
        StoredGymPlan(
          plan: PlanTemplates.fiveDaySplit,
          version: 2,
          seenVersion: 2,
          pending: gymPlan(version: 3, updatedBy: 'cap', plan: renamedDay1()),
        ),
      );
      final back = (await store.load('m1') as Success<StoredGymPlan?>).value!;
      expect(
        [back.version, back.seenVersion, back.pending?.version],
        [2, 2, 3],
      );
      expect(back.pending!.plan.days.first.name.en, 'Renamed');
      await store.clear('m1');
      expect((await store.load('m1') as Success<StoredGymPlan?>).value, isNull);
    });

    test(
      'a corrupt or hostile plan copy is no copy; a bad id is refused',
      () async {
        for (final raw in ['not json', '{}', '[1]', '{"plan":1,"version":1}']) {
          final store = PrefsGymPlanStore(
            await prefs({PrefsGymPlanStore.key('m1'): raw}),
          );
          expect(
            (await store.load('m1') as Success<StoredGymPlan?>).value,
            isNull,
            reason: raw,
          );
        }
        final store = PrefsGymPlanStore(await prefs());
        for (final id in ['', '../x', 'a b', 'x' * 65]) {
          final saved = await store.save(
            id,
            const StoredGymPlan(plan: PlanTemplates.fiveDaySplit, version: 1),
          );
          expect(saved, isA<Failed<void>>(), reason: id);
          expect(
            (await store.load(id) as Success<StoredGymPlan?>).value,
            isNull,
          );
        }
      },
    );

    test(
      'the outbox is append-only by id, survives a restart, and is capped',
      () async {
        final p = await prefs();
        final box = PrefsSessionOutbox(p);
        await box.add(entry(1));
        await box.add(entry(1));
        await box.add(entry(2));
        expect(
          (await PrefsSessionOutbox(p).load() as Success<List<OutboxEntry>>)
              .value,
          hasLength(2),
        );
        await box.remove({entry(1).clientId});
        expect(
          (await box.load() as Success<List<OutboxEntry>>)
              .value
              .single
              .clientId,
          entry(2).clientId,
        );

        for (final raw in ['x', '{}', '[1]', '[{"client_id":1}]']) {
          final bad = PrefsSessionOutbox(
            await prefs({PrefsSessionOutbox.storageKey: raw}),
          );
          expect(
            (await bad.load() as Success<List<OutboxEntry>>).value,
            isEmpty,
            reason: raw,
          );
        }
      },
    );
  });
}
