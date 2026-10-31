import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/network/app_failure.dart';

/// The outcome of an operation that can fail: [Success] or [Failed].
/// Repositories return `Future<Result<T>>`; the UI switches on it.
@immutable
sealed class Result<T> {
  const new();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failed<T>(:final failure) => onFailure(failure),
  };
}

final class Success<T> extends Result<T> {
  const new(this.value);

  final T value;
}

final class Failed<T> extends Result<T> {
  const new(this.failure);

  final AppFailure failure;
}

/// Runs [action] and turns any error into a [Failed] result.
///
/// Retryable failures (network, timeout, server) are retried [retries]
/// times with exponential backoff starting at [delay]. Unexpected errors are
/// reported to monitoring.
Future<Result<T>> guard<T>(
  Future<T> Function() action, {
  int retries = 2,
  Duration delay = const Duration(milliseconds: 400),
  Duration timeout = const Duration(seconds: 20),
}) async {
  var attempt = 0;
  while (true) {
    try {
      return Success(await action().timeout(timeout));
    } on Object catch (error, stackTrace) {
      final failure = AppFailure.from(error);
      if (failure.isRetryable && attempt < retries) {
        await Future<void>.delayed(delay * (1 << attempt));
        attempt++;
        continue;
      }
      if (failure is UnknownFailure || failure is ServerFailure) {
        unawaited(Monitoring.captureException(error, stackTrace));
      }
      return Failed(failure);
    }
  }
}
