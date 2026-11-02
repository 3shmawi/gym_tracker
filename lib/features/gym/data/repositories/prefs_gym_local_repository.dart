import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [GymLocalRepository] on the phone. Nothing here is secret: a workspace
/// name, gym names and roles. The session lives in secure storage.
class PrefsGymLocalRepository implements GymLocalRepository {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static const workspaceKey = 'gym.workspace';
  static const membershipsKey = 'gym.memberships';
  static const onboardingKey = 'gym.onboarding_done';

  /// More than a person can belong to; a corrupt or hostile cache cannot grow.
  static const maxMemberships = 50;

  @override
  Future<Result<Workspace>> loadWorkspace() => guard(
    () async => Workspace.parse(_prefs.getString(workspaceKey)),
    retries: 0,
  );

  @override
  Future<Result<void>> saveWorkspace(Workspace workspace) =>
      guard(() => _prefs.setString(workspaceKey, workspace.stored), retries: 0);

  /// A cache that cannot be read is an empty cache (the next refresh fills
  /// it), never an error screen.
  @override
  Future<Result<List<Membership>>> loadMemberships() => guard(() async {
    final raw = _prefs.getString(membershipsKey);
    if (raw == null) return <Membership>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List<Object?> || list.length > maxMemberships) {
        return <Membership>[];
      }
      return [
        for (final item in list)
          Membership.fromJson(item! as Map<String, Object?>),
      ];
      // A cast failure in our own parser is data, not a bug.
      // ignore: avoid_catching_errors
    } on TypeError {
      return <Membership>[];
    } on FormatException {
      return <Membership>[];
    }
  }, retries: 0);

  @override
  Future<Result<void>> saveMemberships(List<Membership> memberships) => guard(
    () => _prefs.setString(
      membershipsKey,
      jsonEncode([
        for (final m in memberships.take(maxMemberships)) m.toJson(),
      ]),
    ),
    retries: 0,
  );

  @override
  Future<Result<bool>> loadOnboardingDone() =>
      guard(() async => _prefs.getBool(onboardingKey) ?? false, retries: 0);

  @override
  Future<Result<void>> saveOnboardingDone() =>
      guard(() => _prefs.setBool(onboardingKey, true), retries: 0);

  @override
  Future<Result<void>> clear() => guard(() async {
    await _prefs.remove(workspaceKey);
    await _prefs.remove(membershipsKey);
  }, retries: 0);
}
