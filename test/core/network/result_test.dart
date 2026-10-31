import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppFailure.from', () {
    test('maps platform and Supabase errors', () {
      expect(
        AppFailure.from(const SocketException('offline')),
        isA<NetworkFailure>(),
      );
      expect(AppFailure.from(TimeoutException('slow')), isA<TimeoutFailure>());
      expect(
        AppFailure.from(const AuthException('expired')),
        isA<UnauthorizedFailure>(),
      );
      expect(
        AppFailure.from(
          const PostgrestException(message: 'x', code: 'PGRST116'),
        ),
        isA<NotFoundFailure>(),
      );
      expect(
        AppFailure.from(const PostgrestException(message: 'x', code: '42501')),
        isA<UnauthorizedFailure>(),
      );
      expect(
        AppFailure.from(const PostgrestException(message: 'x', code: '22P02')),
        isA<ValidationFailure>(),
      );
      expect(
        AppFailure.from(const PostgrestException(message: 'x', code: '500')),
        isA<ServerFailure>(),
      );
      expect(AppFailure.from(StateError('?')), isA<UnknownFailure>());
    });
  });

  group('guard', () {
    test('wraps a value in Success', () async {
      final result = await guard(() async => 42);
      expect(result, isA<Success<int>>());
      expect((result as Success<int>).value, 42);
    });

    test('retries retryable failures, then succeeds', () async {
      var calls = 0;
      final result = await guard(() async {
        calls++;
        if (calls < 3) throw const SocketException('flaky');
        return 'ok';
      }, delay: Duration.zero);

      expect(calls, 3);
      expect(result, isA<Success<String>>());
    });

    test('gives up after the retries with the failure', () async {
      var calls = 0;
      final result = await guard<void>(
        () async {
          calls++;
          throw const SocketException('down');
        },
        retries: 1,
        delay: Duration.zero,
      );

      expect(calls, 2);
      expect((result as Failed<void>).failure, isA<NetworkFailure>());
    });

    test('does not retry errors that will not recover', () async {
      var calls = 0;
      final result = await guard<void>(() async {
        calls++;
        throw const AuthException('expired');
      }, delay: Duration.zero);

      expect(calls, 1);
      expect((result as Failed<void>).failure, isA<UnauthorizedFailure>());
    });

    test('fold picks the right branch', () {
      const Result<int> ok = Success(1);
      const Result<int> failed = Failed(NotFoundFailure());
      String describe(Result<int> r) =>
          r.fold(onSuccess: (v) => 'value $v', onFailure: (f) => 'failure');
      expect(describe(ok), 'value 1');
      expect(describe(failed), 'failure');
    });
  });
}
