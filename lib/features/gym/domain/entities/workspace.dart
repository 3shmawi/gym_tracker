import 'package:meta/meta.dart';

/// Where the person is training now: on their own, or in one gym
/// (docs/decisions/gym_accounts.md §10). One at a time.
@immutable
sealed class Workspace {
  const new();

  /// `solo` or `gym:<membership id>`; anything else is solo.
  static Workspace parse(String? raw) {
    if (raw == null || !raw.startsWith(_gymPrefix)) {
      return const SoloWorkspace();
    }
    final id = raw.substring(_gymPrefix.length);
    return id.isEmpty || id.length > 64
        ? const SoloWorkspace()
        : GymWorkspace(id);
  }

  static const _gymPrefix = 'gym:';

  String get stored;
}

final class SoloWorkspace extends Workspace {
  const new();

  @override
  String get stored => 'solo';

  @override
  bool operator ==(Object other) => other is SoloWorkspace;

  @override
  int get hashCode => 0;
}

final class GymWorkspace extends Workspace {
  const new(this.membershipId);

  final String membershipId;

  @override
  String get stored => '${Workspace._gymPrefix}$membershipId';

  @override
  bool operator ==(Object other) =>
      other is GymWorkspace && other.membershipId == membershipId;

  @override
  int get hashCode => membershipId.hashCode;
}
