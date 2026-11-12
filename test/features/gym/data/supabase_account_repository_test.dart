// Long mock setups read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_account_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient;

class _Auth extends Mock implements GoTrueClient;

class _Functions extends Mock implements FunctionsClient;

class _Attributes extends Fake implements UserAttributes;

Session _session({bool anonymous = true, String? email}) => Session(
  accessToken: 't',
  tokenType: 'bearer',
  user: User(
    id: 'u1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-11-02T00:00:00Z',
    isAnonymous: anonymous,
    email: email,
  ),
);

void main() {
  late _Client client;
  late _Auth auth;
  late _Functions functions;
  Session? current;

  setUpAll(() {
    registerFallbackValue(_Attributes());
    registerFallbackValue(OtpType.email);
  });

  setUp(() {
    client = _Client();
    auth = _Auth();
    functions = _Functions();
    current = null;
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenAnswer((_) => current);
    when(auth.signOut).thenAnswer((_) async => current = null);
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => const FunctionResponse(data: {'ok': true}, status: 200),
    );
  });

  SupabaseAccountRepository repo() => SupabaseAccountRepository(client);

  test('the session is what the UI needs and no more', () {
    expect(repo().session, AccountSession.signedOut);
    current = _session();
    expect(
      repo().session,
      const AccountSession(isSignedIn: true, isAnonymous: true),
    );
    current = _session(anonymous: false, email: 'me@example.com');
    expect(
      repo().session,
      const AccountSession(isSignedIn: true, email: 'me@example.com'),
    );
    current = _session(anonymous: false, email: '');
    expect(repo().session.email, isNull);
  });

  test('changes follow the auth stream, without repeats', () async {
    final events = StreamController<AuthState>();
    when(() => auth.onAuthStateChange).thenAnswer((_) => events.stream);
    final seen = <AccountSession>[];
    final sub = repo().sessionChanges.listen(seen.add);
    events
      ..add(AuthState(AuthChangeEvent.signedIn, _session()))
      ..add(AuthState(AuthChangeEvent.tokenRefreshed, _session()))
      ..add(const AuthState(AuthChangeEvent.signedOut, null));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [
      const AccountSession(isSignedIn: true, isAnonymous: true),
      AccountSession.signedOut,
    ]);
    await sub.cancel();
    await events.close();
  });

  test('sign out asks Auth to end this session', () async {
    current = _session();
    final result = await repo().signOut();
    expect(result, isA<Success<void>>());
    verify(auth.signOut).called(1);
  });

  test('adding an email sends the trimmed address to Auth', () async {
    when(() => auth.updateUser(any())).thenAnswer(
      (_) async => UserResponse.fromJson({
        'id': 'u1',
        'aud': 'authenticated',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'created_at': '2026-11-02T00:00:00Z',
      }),
    );
    final result = await repo().addEmail('  me@example.com ');
    expect(result, isA<Success<void>>());
    final sent =
        verify(() => auth.updateUser(captureAny())).captured.single
            as UserAttributes;
    expect(sent.email, 'me@example.com');
  });

  test('adding an email fails quietly when offline', () async {
    when(() => auth.updateUser(any())).thenThrow(AuthRetryableFetchException());
    final result = await repo().addEmail('me@example.com');
    expect((result as Failed<void>).failure, isA<NetworkFailure>());
  });

  group('sign in by code', () {
    AuthResponse okResponse() => AuthResponse();

    test('a signed-out person: signInWithOtp creates the user when new, with the captcha token', () async {
      when(
        () => auth.signInWithOtp(
          email: any(named: 'email'),
          shouldCreateUser: any(named: 'shouldCreateUser'),
          captchaToken: any(named: 'captchaToken'),
        ),
      ).thenAnswer((_) async {});
      final repository = SupabaseAccountRepository(
        client,
        captchaToken: () async => 'turnstile-token',
      );
      final result = await repository.sendCode('  me@example.com ');
      expect(result, isA<Success<void>>());
      verify(
        () => auth.signInWithOtp(
          email: 'me@example.com',
          shouldCreateUser: true,
          captchaToken: 'turnstile-token',
        ),
      ).called(1);
      verifyNever(() => auth.updateUser(any()));
    });

    test('an anonymous gym trainee keeps the same account: updateUser, never a new sign-in', () async {
      current = _session();
      when(() => auth.updateUser(any())).thenAnswer(
        (_) async => UserResponse.fromJson({
          'id': 'u1',
          'aud': 'authenticated',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'created_at': '2026-11-02T00:00:00Z',
        }),
      );
      expect(await repo().sendCode('me@example.com'), isA<Success<void>>());
      verify(() => auth.updateUser(any())).called(1);
      verifyNever(
        () => auth.signInWithOtp(
          email: any(named: 'email'),
          shouldCreateUser: any(named: 'shouldCreateUser'),
          captchaToken: any(named: 'captchaToken'),
        ),
      );
    });

    test('the code is checked as an email code, or as an email change for an anonymous account', () async {
      when(
        () => auth.verifyOTP(
          email: any<String?>(named: 'email'),
          token: any<String?>(named: 'token'),
          type: any<OtpType>(named: 'type'),
        ),
      ).thenAnswer((_) async => okResponse());
      expect(
        await repo().verifyCode(' me@example.com ', ' 123456 '),
        isA<Success<void>>(),
      );
      verify(
        () => auth.verifyOTP(
          email: 'me@example.com',
          token: '123456',
          type: OtpType.email,
        ),
      ).called(1);
      current = _session();
      await repo().verifyCode('me@example.com', '123456');
      verify(
        () => auth.verifyOTP(
          email: 'me@example.com',
          token: '123456',
          type: OtpType.emailChange,
        ),
      ).called(1);
    });

    test(
      'Auth errors become what a person can act on; the rest stays generic',
      () async {
        Future<AppFailure> failureOf(Object error) async {
          when(
            () => auth.verifyOTP(
              email: any(named: 'email'),
              token: any(named: 'token'),
              type: any(named: 'type'),
            ),
          ).thenThrow(error);
          return ((await repo().verifyCode(
            'me@example.com',
            '000000',
          )) as Failed<void>).failure;
        }

        expect(
          await failureOf(
            const AuthApiException('x', statusCode: '403', code: 'otp_expired'),
          ),
          isA<AuthCodeFailure>().having(
            (f) => f.problem,
            'problem',
            AuthCodeProblem.wrongOrExpired,
          ),
        );
        expect(
          await failureOf(
            const AuthApiException(
              'x',
              statusCode: '429',
              code: 'over_email_send_rate_limit',
            ),
          ),
          isA<AuthCodeFailure>().having(
            (f) => f.problem,
            'problem',
            AuthCodeProblem.tooMany,
          ),
        );
        expect(
          await failureOf(const AuthApiException('x', statusCode: '429')),
          isA<AuthCodeFailure>().having(
            (f) => f.problem,
            'problem',
            AuthCodeProblem.tooMany,
          ),
        );
        expect(
          await failureOf(
            const AuthApiException(
              'x',
              statusCode: '422',
              code: 'email_exists',
            ),
          ),
          isA<AuthCodeFailure>().having(
            (f) => f.problem,
            'problem',
            AuthCodeProblem.emailTaken,
          ),
        );
        expect(
          await failureOf(
            const AuthApiException(
              'x',
              statusCode: '400',
              code: 'captcha_failed',
            ),
          ),
          isA<UnauthorizedFailure>(),
        );
        expect(
          await failureOf(AuthRetryableFetchException()),
          isA<NetworkFailure>(),
        );
      },
    );
  });

  group('deleteAccount', () {
    test('sends exactly {"confirm":"delete"}, then ends the session', () async {
      current = _session();
      final result = await repo().deleteAccount();
      expect(result, isA<Success<void>>());
      verify(
        () => functions.invoke('delete-account', body: {'confirm': 'delete'}),
      ).called(1);
      verify(auth.signOut).called(1);
    });

    test('a sole owner is refused with the gym names', () async {
      when(() => functions.invoke(any(), body: any(named: 'body'))).thenThrow(
        const FunctionsHttpException(
          status: 409,
          details: {
            'ok': false,
            'error': 'last_owner',
            'gyms': [
              {'name': 'Iron House'},
              {'name': 'Peak'},
              {'nope': 1},
              'text',
            ],
          },
        ),
      );
      final result = await repo().deleteAccount();
      expect(
        (result as Failed<void>).failure,
        isA<LastOwnerFailure>().having((f) => f.gymNames, 'names', [
          'Iron House',
          'Peak',
        ]),
      );
      verifyNever(auth.signOut);
    });

    test('names are capped', () {
      final failure = SupabaseAccountRepository.lastOwnerFailureFor(
        FunctionsHttpException(
          status: 409,
          details: {
            'error': 'last_owner',
            'gyms': [
              for (var i = 0; i < 100; i++) {'name': 'g$i'},
            ],
          },
        ),
      );
      expect(failure!.gymNames, hasLength(20));
    });

    test('another 409, or a 500, is not a last-owner message', () async {
      for (final error in [
        const FunctionsHttpException(status: 409, details: {'error': 'x'}),
        const FunctionsHttpException(status: 409),
        const FunctionsHttpException(status: 500),
        const FunctionsFetchException(details: 'down'),
      ]) {
        when(() => functions.invoke(any(), body: any(named: 'body')))
            .thenThrow(error);
        final result = await repo().deleteAccount();
        expect(
          (result as Failed<void>).failure,
          isNot(isA<LastOwnerFailure>()),
        );
      }
    });
  });
}
