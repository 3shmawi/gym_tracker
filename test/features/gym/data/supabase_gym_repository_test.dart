import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/install_id_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/gym_fakes.dart';

class _Client extends Mock implements SupabaseClient;

class _Auth extends Mock implements GoTrueClient;

class _Functions extends Mock implements FunctionsClient;

class _Ids implements InstallIdStore {
  @override
  Future<String> get() async => 'install-1';
}

User _user({bool anonymous = true}) => User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-02T00:00:00Z',
  isAnonymous: anonymous,
);

Session _session({bool anonymous = true}) => Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: _user(anonymous: anonymous),
);

const Map<String, Object> _ok = {
  'ok': true,
  'gym': {'id': 'g1', 'name': 'Iron House', 'history_after_end': 'readable'},
  'membership_id': 'm1',
  'role': 'trainee',
  'permissions': {'edit_targets': true, 'edit_plan': false},
};

FunctionException _http(int status, [Object? details]) =>
    FunctionsHttpException(status: status, details: details);

void main() {
  late _Client client;
  late _Auth auth;
  late _Functions functions;
  Session? current;
  var signIns = 0;
  String? captchaSeen;

  SupabaseGymRepository repo({
    Future<List<Map<String, Object?>>> Function()? rows,
    int retries = 0,
  }) => SupabaseGymRepository(
    client,
    _Ids(),
    captchaToken: () async => 'captcha-token',
    membershipRows: rows,
    retries: retries,
  );

  setUp(() {
    client = _Client();
    auth = _Auth();
    functions = _Functions();
    current = null;
    signIns = 0;
    captchaSeen = null;
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenAnswer((_) => current);
    when(() => auth.currentUser).thenAnswer((_) => current?.user);
    when(() => auth.signInAnonymously(captchaToken: any(named: 'captchaToken')))
        .thenAnswer((invocation) async {
          signIns++;
          captchaSeen = invocation.namedArguments[#captchaToken] as String?;
          current = _session();
          return AuthResponse(session: current);
        });
    when(auth.signOut).thenAnswer((_) async => current = null);
    when(
      () => functions.invoke(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => const FunctionResponse(data: _ok, status: 200));
  });

  group('redeem', () {
    test('signs in anonymously when there is no session, then joins', () async {
      final result = await repo().redeem(testCode);

      final joined = (result as Success<JoinedGym>).value;
      expect(joined.gym.name, 'Iron House');
      expect(joined.membershipId, 'm1');
      expect(signIns, 1);
      expect(captchaSeen, 'captcha-token', reason: 'the Turnstile seam');
      verify(
        () => functions.invoke(
          'redeem_invite',
          body: {'code': 'K7M2QX', 'install_id': 'install-1'},
        ),
      ).called(1);
    });

    test('keeps the session a person already has (second gym)', () async {
      current = _session();
      await repo().redeem(testCode);
      expect(signIns, 0);
    });

    test('maps every answer of the function to a reason', () async {
      final cases = <(int, Object?, InviteProblem)>[
        (400, {'ok': false, 'error': 'invalid'}, InviteProblem.invalid),
        (404, {'ok': false, 'error': 'not_found'}, InviteProblem.invalid),
        (410, {'ok': false, 'error': 'expired'}, InviteProblem.expired),
        (410, {'ok': false, 'error': 'revoked'}, InviteProblem.expired),
        (409, {'ok': false, 'error': 'used'}, InviteProblem.used),
        (409, {'ok': false, 'error': 'conflict'}, InviteProblem.conflict),
        (409, 'text', InviteProblem.used),
        (429, {'ok': false, 'error': 'throttled'}, InviteProblem.throttled),
      ];
      current = _session();
      for (final (status, details, problem) in cases) {
        when(() => functions.invoke(any(), body: any(named: 'body')))
            .thenThrow(_http(status, details));
        final result = await repo().redeem(testCode);
        expect(
          (result as Failed<JoinedGym>).failure,
          isA<InviteFailure>().having((f) => f.problem, 'problem', problem),
          reason: '$status $details',
        );
      }
    });

    test('other statuses stay generic (no guess about the code)', () async {
      current = _session();
      final cases = <(int, Matcher)>[
        (500, isA<ServerFailure>()),
        (503, isA<ServerFailure>()),
        (413, isA<UnknownFailure>()),
        (415, isA<UnknownFailure>()),
        (405, isA<UnknownFailure>()),
        (401, isA<UnauthorizedFailure>()),
      ];
      for (final (status, matcher) in cases) {
        when(() => functions.invoke(any(), body: any(named: 'body')))
            .thenThrow(_http(status));
        // A permanent session is never replaced, so 401 stays a failure.
        current = _session(anonymous: false);
        final result = await repo().redeem(testCode);
        expect(
          (result as Failed<JoinedGym>).failure,
          matcher,
          reason: '$status',
        );
      }
    });

    test('no connection is a network failure and is tried again', () async {
      current = _session();
      var calls = 0;
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer((
        _,
      ) async {
        calls++;
        if (calls == 1) throw const FunctionsFetchException(details: 'down');
        return const FunctionResponse(data: _ok, status: 200);
      });
      final result = await SupabaseGymRepository(
        client,
        _Ids(),
        retries: 1,
      ).redeem(testCode);
      expect(result, isA<Success<JoinedGym>>());
      expect(calls, 2, reason: 'the code is not used until the server accepts');
    });

    test('with no connection at all the failure is Network', () async {
      current = _session();
      when(() => functions.invoke(any(), body: any(named: 'body')))
          .thenThrow(const FunctionsFetchException(details: 'down'));
      final result = await repo().redeem(testCode);
      expect((result as Failed<JoinedGym>).failure, isA<NetworkFailure>());
    });

    test(
      'a stored anonymous session the server forgot is replaced once',
      () async {
        current = _session();
        var calls = 0;
        when(() => functions.invoke(any(), body: any(named: 'body')))
            .thenAnswer((_) async {
              calls++;
              if (calls == 1) throw _http(401);
              return const FunctionResponse(data: _ok, status: 200);
            });
        final result = await repo().redeem(testCode);
        expect(result, isA<Success<JoinedGym>>());
        expect(signIns, 1);
        verify(auth.signOut).called(1);
      },
    );

    test('a forgotten anonymous session is not replaced forever', () async {
      current = _session();
      when(() => functions.invoke(any(), body: any(named: 'body')))
          .thenThrow(_http(401));
      final result = await repo().redeem(testCode);
      expect((result as Failed<JoinedGym>).failure, isA<UnauthorizedFailure>());
      expect(signIns, 1, reason: 'one fresh sign-in, then stop');
    });

    test('a permanent session is never replaced on a 401', () async {
      current = _session(anonymous: false);
      when(() => functions.invoke(any(), body: any(named: 'body')))
          .thenThrow(_http(401));
      await repo().redeem(testCode);
      verifyNever(auth.signOut);
      expect(signIns, 0);
    });

    test('a wrong 200 body is a validation failure, not a crash', () async {
      current = _session();
      for (final data in <Object?>[
        null,
        'ok',
        <String, Object?>{},
        {'ok': false},
        {'ok': true, 'membership_id': 'm1'},
      ]) {
        when(() => functions.invoke(any(), body: any(named: 'body')))
            .thenAnswer((_) async => FunctionResponse(data: data, status: 200));
        final result = await repo().redeem(testCode);
        expect(
          (result as Failed<JoinedGym>).failure,
          isA<ValidationFailure>(),
          reason: '$data',
        );
      }
    });

    test('a failed sign-in is a failure, not a crash', () async {
      when(
        () => auth.signInAnonymously(captchaToken: any(named: 'captchaToken')),
      ).thenThrow(AuthRetryableFetchException());
      final result = await repo().redeem(testCode);
      expect((result as Failed<JoinedGym>).failure, isA<NetworkFailure>());
      verifyNever(() => functions.invoke(any(), body: any(named: 'body')));
    });
  });

  group('inviteFailureFor', () {
    test('says nothing about codes for a missing connection', () {
      expect(
        SupabaseGymRepository.inviteFailureFor(
          const FunctionsFetchException(details: 'x'),
        ),
        isNull,
      );
    });
  });

  group('loadMemberships', () {
    test('without a session there is nothing to ask', () async {
      var asked = false;
      final result = await repo(
        rows: () async {
          asked = true;
          return [];
        },
      ).loadMemberships();
      expect((result as Success<List<Membership>>).value, isEmpty);
      expect(asked, isFalse);
    });

    test('reads the rows', () async {
      current = _session();
      final result = await repo(
        rows: () async => [
          {
            'id': 'm1',
            'role': 'trainee',
            'status': 'active',
            'gyms': {'id': 'g1', 'name': 'Iron House'},
          },
          {
            'id': 'm2',
            'role': 'trainee',
            'status': 'ended',
            'gyms': {'id': 'g2', 'name': 'Peak', 'history_after_end': 'locked'},
          },
        ],
      ).loadMemberships();
      final list = (result as Success<List<Membership>>).value;
      expect(list.map((m) => m.id), ['m1', 'm2']);
      expect(list.last.isLocked, isTrue);
    });

    test('a broken row is a validation failure, not a crash', () async {
      current = _session();
      final result = await repo(
        rows: () async => [
          {'id': 'm1'},
        ],
      ).loadMemberships();
      expect(
        (result as Failed<List<Membership>>).failure,
        isA<ValidationFailure>(),
      );
    });
  });
}
