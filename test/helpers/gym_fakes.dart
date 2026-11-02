import 'dart:async';

import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';

/// A valid code for tests.
final InviteCode testCode = InviteCode.tryParse('K7M2QX')!;

Membership member({
  String id = 'm1',
  String gym = 'Iron House',
  GymRole role = GymRole.trainee,
  MembershipStatus status = MembershipStatus.active,
  HistoryAfterEnd history = HistoryAfterEnd.readable,
  GymPermissions permissions = const GymPermissions(editTargets: true),
  String? name = 'Mohamed',
  DateTime? endedAt,
}) => Membership(
  id: id,
  gym: Gym(id: 'g-$id', name: gym, historyAfterEnd: history),
  role: role,
  status: status,
  permissions: permissions,
  displayName: name,
  endedAt: endedAt,
);

JoinedGym joinedGym({
  String id = 'm1',
  String gym = 'Iron House',
  GymRole role = GymRole.trainee,
  GymPermissions permissions = const GymPermissions(editTargets: true),
}) => JoinedGym(
  membershipId: id,
  gym: Gym(id: 'g-$id', name: gym),
  role: role,
  permissions: permissions,
);

/// A gym backend that answers from a script and remembers what it was asked.
class FakeGymRepository implements GymRepository {
  new({Result<JoinedGym>? redeemResult, Result<List<Membership>>? memberships})
    : redeemResult = redeemResult ?? Success(joinedGym()),
      membershipsResult = memberships ?? const Success(<Membership>[]);

  Result<JoinedGym> redeemResult;
  Result<List<Membership>> membershipsResult;
  final List<InviteCode> redeemed = [];
  Completer<void>? hold;
  int loads = 0;

  @override
  Future<Result<JoinedGym>> redeem(InviteCode code) async {
    redeemed.add(code);
    await hold?.future;
    return redeemResult;
  }

  @override
  Future<Result<List<Membership>>> loadMemberships() async {
    loads++;
    return membershipsResult;
  }
}

class FakeAccountRepository implements AccountRepository {
  new([this.current = AccountSession.signedOut]);

  AccountSession current;
  final changes = StreamController<AccountSession>.broadcast();
  Result<void> signOutResult = const Success(null);
  Result<void> addEmailResult = const Success(null);
  Result<void> deleteResult = const Success(null);
  final List<String> emails = [];
  int signOuts = 0;
  int deletes = 0;

  void emit(AccountSession next) {
    current = next;
    changes.add(next);
  }

  @override
  AccountSession get session => current;

  @override
  Stream<AccountSession> get sessionChanges => changes.stream;

  @override
  Future<Result<void>> signOut() async {
    signOuts++;
    if (signOutResult is Success<void>) emit(AccountSession.signedOut);
    return signOutResult;
  }

  @override
  Future<Result<void>> addEmail(String email) async {
    emails.add(email);
    return addEmailResult;
  }

  @override
  Future<Result<void>> deleteAccount() async {
    deletes++;
    if (deleteResult is Success<void>) emit(AccountSession.signedOut);
    return deleteResult;
  }
}

const anonymousSession = AccountSession(isSignedIn: true, isAnonymous: true);
const emailSession = AccountSession(isSignedIn: true, email: 'me@example.com');

const offline = Failed<Never>(NetworkFailure());
