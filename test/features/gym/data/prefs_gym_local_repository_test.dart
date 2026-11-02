import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_fakes.dart';

void main() {
  Future<(PrefsGymLocalRepository, SharedPreferences)> make([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return (PrefsGymLocalRepository(prefs), prefs);
  }

  T value<T>(Result<T> r) => (r as Success<T>).value;

  test('starts solo, with no gyms, not onboarded', () async {
    final (repo, _) = await make();
    expect(value(await repo.loadWorkspace()), const SoloWorkspace());
    expect(value(await repo.loadMemberships()), isEmpty);
    expect(value(await repo.loadOnboardingDone()), isFalse);
  });

  test('remembers the workspace, gyms and the first answer', () async {
    final (repo, _) = await make();
    await repo.saveWorkspace(const GymWorkspace('m1'));
    await repo.saveMemberships([member(), member(id: 'm2', gym: 'Peak')]);
    await repo.saveOnboardingDone();
    expect(value(await repo.loadWorkspace()), const GymWorkspace('m1'));
    expect(value(await repo.loadMemberships()).map((m) => m.id), ['m1', 'm2']);
    expect(value(await repo.loadOnboardingDone()), isTrue);
  });

  test('clear forgets the workspace and gyms, not the first answer', () async {
    final (repo, _) = await make();
    await repo.saveWorkspace(const GymWorkspace('m1'));
    await repo.saveMemberships([member()]);
    await repo.saveOnboardingDone();
    await repo.clear();
    expect(value(await repo.loadWorkspace()), const SoloWorkspace());
    expect(value(await repo.loadMemberships()), isEmpty);
    expect(value(await repo.loadOnboardingDone()), isTrue);
  });

  test('a broken or hostile cache reads as empty, never as an error', () async {
    for (final raw in [
      'not json',
      '{"a":1}',
      '[1,2]',
      '[{"id":"m"}]',
      '[{"id":"m","gyms":5}]',
      '"text"',
    ]) {
      final (repo, _) = await make({
        PrefsGymLocalRepository.membershipsKey: raw,
      });
      expect(value(await repo.loadMemberships()), isEmpty, reason: raw);
    }
  });

  test('a cache longer than any person could have is ignored', () async {
    final (repo, prefs) = await make();
    await repo.saveMemberships([
      for (var i = 0; i < 80; i++) member(id: 'm$i'),
    ]);
    // Saving keeps at most the cap; a hand-made longer list is refused.
    expect(value(await repo.loadMemberships()), hasLength(50));
    await prefs.setString(
      PrefsGymLocalRepository.membershipsKey,
      '[${List.filled(51, member().toJson().toString()).join(',')}]',
    );
    expect(value(await repo.loadMemberships()), isEmpty);
  });

  test('a workspace of the wrong shape is solo', () async {
    final (repo, _) = await make({
      PrefsGymLocalRepository.workspaceKey: 'gym:',
    });
    expect(value(await repo.loadWorkspace()), const SoloWorkspace());
  });

  test('stores no secret: only names, roles and a workspace', () async {
    final (repo, prefs) = await make();
    await repo.saveMemberships([member()]);
    final stored = prefs.getString(PrefsGymLocalRepository.membershipsKey)!;
    for (final word in ['token', 'password', 'code', 'install', 'refresh']) {
      expect(stored.toLowerCase(), isNot(contains(word)), reason: word);
    }
    expect(Membership.fromJson(member().toJson()), member());
  });
}
