import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_solo_import_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_solo_import_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient;

ImportSession item(int i) => ImportSession(
  clientId: '$i'.padLeft(64, 'a'),
  dayId: 'day-1',
  finishedAt: '2026-10-01T09:00:00.000Z',
  sets: const [
    {'exercise': 'bench', 'weight': 50.0, 'reps': 12},
  ],
);

void main() {
  group(SupabaseSoloImportRepository, () {
    SupabaseSoloImportRepository repo(
      Future<Object?> Function(String, Map<String, Object?>) call,
    ) => SupabaseSoloImportRepository(_Client(), retries: 0, call: call);

    test('calls import_solo_data with the sessions and the plan', () async {
      String? name;
      Map<String, Object?>? sent;
      final result = await repo((n, params) async {
        name = n;
        sent = params;
        return {
          'imported': 1,
          'skipped': 0,
          'plan_saved': true,
          'solo_total': 1,
        };
      }).importChunk([item(1)], plan: PlanTemplates.fiveDaySplit);
      expect((result as Success<ImportAck>).value.soloTotal, 1);
      expect(name, 'import_solo_data');
      expect(sent!['p_sessions'], [item(1).toJson()]);
      expect(sent!['p_plan'], PlanTemplates.fiveDaySplit.toJson());
    });

    test('no plan is sent as null', () async {
      Map<String, Object?>? sent;
      await repo((n, params) async {
        sent = params;
        return {
          'imported': 0,
          'skipped': 0,
          'plan_saved': false,
          'solo_total': 0,
        };
      }).importChunk([]);
      expect(sent!['p_plan'], isNull);
    });

    test('refuses a chunk over 50 before any call', () async {
      var called = false;
      final result = await repo((n, p) async {
        called = true;
        return null;
      }).importChunk([for (var i = 0; i < 51; i++) item(i)]);
      expect((result as Failed<ImportAck>).failure, isA<ValidationFailure>());
      expect(called, isFalse);
    });

    test('server errors map to failures', () async {
      for (final (code, matcher) in [
        ('22023', isA<ValidationFailure>()),
        ('42501', isA<UnauthorizedFailure>()),
      ]) {
        final result = await repo(
          (n, p) async => throw PostgrestException(message: 'x', code: code),
        ).importChunk([item(1)]);
        expect((result as Failed<ImportAck>).failure, matcher, reason: code);
      }
    });

    test('a wrong answer is a validation failure', () async {
      final result = await repo((n, p) async => 'nope').importChunk([item(1)]);
      expect((result as Failed<ImportAck>).failure, isA<ValidationFailure>());
    });
  });

  group(PrefsSoloImportStore, () {
    test(
      'remembers the answer and progress, and survives odd values',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = PrefsSoloImportStore(prefs);
        expect(
          (await store.load() as Success<SoloImportStatus>).value.choice,
          SoloImportChoice.undecided,
        );
        await store.save(
          SoloImportStatus(
            choice: SoloImportChoice.done,
            nextIndex: 7,
            migratedAt: DateTime.utc(2026, 11, 2),
          ),
        );
        final back = (await store.load() as Success<SoloImportStatus>).value;
        expect(
          [back.choice, back.nextIndex, back.migratedAt],
          [SoloImportChoice.done, 7, DateTime.utc(2026, 11, 2)],
        );

        await prefs.setString(PrefsSoloImportStore.choiceKey, '<script>');
        await prefs.setInt(PrefsSoloImportStore.indexKey, -5);
        await prefs.setString(PrefsSoloImportStore.migratedKey, 'not a date');
        final odd = (await store.load() as Success<SoloImportStatus>).value;
        expect(
          [odd.choice, odd.nextIndex, odd.migratedAt],
          [SoloImportChoice.undecided, 0, null],
        );

        await store.clear();
        expect(
          prefs.getKeys().where((k) => k.startsWith('gym.solo_import')),
          isEmpty,
        );
      },
    );
  });
}
