import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';

import '../../../helpers/gym_fakes.dart';

void main() {
  group('Gym', () {
    test('initials: two words, one word, Arabic, blanks', () {
      expect(const Gym(id: 'g', name: 'Iron House').initials, 'IH');
      expect(const Gym(id: 'g', name: 'Peak').initials, 'PE');
      expect(const Gym(id: 'g', name: '  gold   x ').initials, 'GX');
      expect(const Gym(id: 'g', name: 'نادي القوة').initials, 'نا');
      expect(const Gym(id: 'g', name: '   ').initials, '?');
    });

    test('fromJson refuses a gym without id or name', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'id': 'g'},
        {'name': 'x'},
        {'id': '', 'name': 'x'},
        {'id': 1, 'name': 'x'},
      ]) {
        expect(() => Gym.fromJson(json), throwsFormatException);
      }
    });

    test('an unknown history setting reads as readable', () {
      final gym = Gym.fromJson(const {
        'id': 'g',
        'name': 'x',
        'history_after_end': 'whatever',
      });
      expect(gym.historyAfterEnd, HistoryAfterEnd.readable);
    });
  });

  group('roles and permissions', () {
    test('an unknown role is a trainee (the least a role can allow)', () {
      expect(GymRole.fromName('captain'), GymRole.captain);
      expect(GymRole.fromName('admin'), GymRole.trainee);
      expect(GymRole.fromName(null), GymRole.trainee);
    });

    test('permissions default to nothing, from any wrong shape', () {
      for (final bad in <Object?>[null, 'x', 5, <Object?>[]]) {
        expect(GymPermissions.fromJson(bad), const GymPermissions());
      }
      final p = GymPermissions.fromJson(const {
        'edit_targets': true,
        'edit_plan': 'yes',
        'build_own_plan': true,
      });
      expect(p.editTargets, isTrue);
      expect(p.editPlan, isFalse, reason: 'only a real true counts');
      expect(p.buildOwnPlan, isTrue);
    });
  });

  group('Membership', () {
    test('survives the local cache round trip', () {
      final m = member(
        status: MembershipStatus.ended,
        history: HistoryAfterEnd.locked,
        permissions: const GymPermissions(editTargets: true, editPlan: true),
        endedAt: DateTime.utc(2026, 10, 12),
      );
      expect(Membership.fromJson(m.toJson()), m);
    });

    test('reads a server row with the gym joined in', () {
      final m = Membership.fromJson(const {
        'id': 'm9',
        'role': 'owner',
        'status': 'active',
        'display_name': 'Ahmed',
        'ended_at': null,
        'can_edit_targets': true,
        'can_edit_plan': false,
        'can_build_own_plan': true,
        'gyms': {'id': 'g9', 'name': 'Peak', 'history_after_end': 'locked'},
      });
      expect(m.role, GymRole.owner);
      expect(m.isActive, isTrue);
      expect(m.permissions.buildOwnPlan, isTrue);
      expect(m.gym.historyAfterEnd, HistoryAfterEnd.locked);
    });

    test('an unknown status reads as ended (never opens a gym by mistake)', () {
      final m = Membership.fromJson(const {
        'id': 'm',
        'status': 'weird',
        'gyms': {'id': 'g', 'name': 'x'},
      });
      expect(m.status, MembershipStatus.ended);
      expect(m.isActive, isFalse);
    });

    test('ended: readable or locked follows the gym setting', () {
      final readable = member(status: MembershipStatus.ended);
      final locked = member(
        status: MembershipStatus.ended,
        history: HistoryAfterEnd.locked,
      );
      expect(readable.isReadOnly, isTrue);
      expect(readable.isLocked, isFalse);
      expect(locked.isLocked, isTrue);
      expect(locked.isReadOnly, isFalse);
      expect(member().isReadOnly, isFalse);
    });

    test('refuses rows without an id or a gym', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'id': 'm'},
        {'gyms': <String, Object?>{}},
        {'id': 'm', 'gyms': 'not a map'},
      ]) {
        expect(() => Membership.fromJson(json), throwsFormatException);
      }
    });
  });

  group('JoinedGym', () {
    test('reads the redeem answer', () {
      final j = JoinedGym.fromJson(const {
        'ok': true,
        'gym': {'id': 'g', 'name': 'Iron House', 'logo_path': 'g/logo.png'},
        'membership_id': 'm1',
        'role': 'trainee',
        'permissions': {'edit_targets': true},
      });
      expect(j.gym.name, 'Iron House');
      expect(j.permissions.editTargets, isTrue);
      expect(j.toMembership().isActive, isTrue);
    });

    test('a short or wrong answer is a format failure, not a crash', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'membership_id': 'm'},
        {'gym': <String, Object?>{}, 'membership_id': 'm'},
        {
          'gym': {'id': 'g', 'name': 'x'},
          'membership_id': 5,
        },
      ]) {
        expect(() => JoinedGym.fromJson(json), throwsFormatException);
      }
    });
  });

  group('Workspace', () {
    test('parses what it stores, and falls back to solo', () {
      expect(Workspace.parse('solo'), const SoloWorkspace());
      expect(Workspace.parse('gym:m1'), const GymWorkspace('m1'));
      expect(const GymWorkspace('m1').stored, 'gym:m1');
      for (final bad in <String?>[
        null,
        '',
        'gym:',
        'gym',
        'GYM:m1',
        'gym:${'x' * 65}',
        'other',
      ]) {
        expect(Workspace.parse(bad), const SoloWorkspace(), reason: '$bad');
      }
    });
  });

  group('InviteCode.fromScan', () {
    InviteCode? scan(String? raw) => InviteCode.fromScan(raw);

    test('accepts the three forms the app produces', () {
      for (final raw in [
        'https://azmm.pages.dev/join/K7M2QX',
        'HTTPS://AZMM.PAGES.DEV/join/k7m2qx',
        'azm://join/K7M2QX',
        'AZM://JOIN/k7m2qx',
        'K7M2QX',
        '  k7m2qx\n',
      ]) {
        expect(scan(raw)?.value, 'K7M2QX', reason: raw);
      }
    });

    test('refuses everything else', () {
      for (final raw in [
        null,
        '',
        '   ',
        'http://azmm.pages.dev/join/K7M2QX',
        'https://azmm.pages.dev.evil.example/join/K7M2QX',
        'https://evil.example/join/K7M2QX',
        'https://evil.example/azmm.pages.dev/join/K7M2QX',
        'https://azmm.pages.dev@evil.example/join/K7M2QX',
        'https://someone@azmm.pages.dev/join/K7M2QX',
        'https://azmm.pages.dev:8443/join/K7M2QX',
        'https://azmm.pages.dev/join/K7M2QX?c=1',
        'https://azmm.pages.dev/join/K7M2QX#x',
        'https://azmm.pages.dev/join/K7M2QX/extra',
        'https://azmm.pages.dev/join/K7M2QX/',
        'https://azmm.pages.dev/join',
        'https://azmm.pages.dev/join/',
        'https://azmm.pages.dev/other/K7M2QX',
        'https://azmm.pages.dev/?c=K7M2QX',
        'https://azmm.pages.dev/join?c=K7M2QX',
        'azm://join',
        'azm://join/K7M2QX/x',
        'azm://other/K7M2QX',
        'azm://evil/join/K7M2QX',
        'javascript:alert(1)',
        'data:text/html,<script>1</script>',
        'file:///etc/passwd',
        'mailto:a@b.c',
        'WIFI:S:x;T:WPA;P:y;;',
        'K7M2Q',
        'K7M2QXX',
        'K7M2Q0',
        'K7M2QI',
        'ſ7M2QX',
        'K7M2QX\u0000',
        '<script>alert(1)</script>',
        "'; drop table invites;--",
        'x' * 5000,
        'https://azmm.pages.dev/join/${'K' * 5000}',
      ]) {
        expect(
          scan(raw),
          isNull,
          reason: '$raw'.substring(0, 40.clamp(0, '$raw'.length)),
        );
      }
    });

    test('never prints the code', () {
      expect('${scan('K7M2QX')}', isNot(contains('K7M2QX')));
    });
  });
}
