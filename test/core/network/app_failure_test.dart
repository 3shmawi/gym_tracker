import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppFailure.from (Edge Functions and Auth)', () {
    test('no connection to a function is a network failure', () {
      expect(
        AppFailure.from(const FunctionsFetchException(details: 'x')),
        isA<NetworkFailure>(),
      );
    });

    test(
      'Auth being unreachable is a network failure, not "sign in again"',
      () {
        expect(
          AppFailure.from(AuthRetryableFetchException()),
          isA<NetworkFailure>(),
        );
        expect(
          AppFailure.from(const AuthApiException('bad', statusCode: '400')),
          isA<UnauthorizedFailure>(),
        );
      },
    );

    test('function statuses', () {
      Matcher kind(int status) => isA<AppFailure>();
      expect(
        AppFailure.from(const FunctionsHttpException(status: 401)),
        isA<UnauthorizedFailure>(),
      );
      expect(
        AppFailure.from(const FunctionsHttpException(status: 403)),
        isA<UnauthorizedFailure>(),
      );
      expect(
        AppFailure.from(const FunctionsHttpException(status: 404)),
        isA<NotFoundFailure>(),
      );
      for (final status in [500, 502, 503]) {
        expect(
          AppFailure.from(FunctionsHttpException(status: status)),
          isA<ServerFailure>(),
          reason: '$status',
        );
      }
      expect(
        AppFailure.from(const FunctionsHttpException(status: 418)),
        isA<UnknownFailure>(),
      );
      expect(kind(0), isNotNull);
    });

    test('invite and last-owner failures pass through unchanged', () {
      const invite = InviteFailure(InviteProblem.used);
      const lastOwner = LastOwnerFailure(['x']);
      expect(AppFailure.from(invite), same(invite));
      expect(AppFailure.from(lastOwner), same(lastOwner));
      expect(invite.isRetryable, isFalse);
      expect(lastOwner.isRetryable, isFalse);
    });
  });

  group('AppFailure.from (database rules of the backup)', () {
    test('the 20,000-workout cap is refused for good, never retried', () {
      final failure = AppFailure.from(
        const PostgrestException(message: 'too_many_workouts', code: '54000'),
      );
      expect(failure, isA<ValidationFailure>());
      expect(failure.isRetryable, isFalse);
    });

    test('other database errors stay retryable server failures', () {
      final failure = AppFailure.from(
        const PostgrestException(message: 'boom', code: '57014'),
      );
      expect(failure, isA<ServerFailure>());
      expect(failure.isRetryable, isTrue);
    });
  });
}
