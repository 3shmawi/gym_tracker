import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/captcha/turnstile_captcha.dart';
import 'package:gym_tracker/core/config/env.dart';
import 'package:gym_tracker/core/network/app_failure.dart';

void main() {
  TurnstileCaptcha captcha(
    Future<String?> Function(String, String) fetch, {
    Duration timeout = const Duration(seconds: 1),
  }) => TurnstileCaptcha(siteKey: 'site', timeout: timeout, fetch: fetch);

  test('gives the widget the site key and the registered domain', () async {
    String? key;
    String? base;
    final token = await captcha((k, b) async {
      key = k;
      base = b;
      return 'tok';
    }).token();
    expect(token, 'tok');
    expect(key, 'site');
    expect(base, 'https://azmm.pages.dev');
  });

  test(
    'no token or an empty one is a failure, never an empty string',
    () async {
      for (final value in <String?>[null, '']) {
        await expectLater(
          captcha((k, b) async => value).token(),
          throwsA(isA<UnknownFailure>()),
          reason: '$value',
        );
      }
    },
  );

  test('a widget that never answers times out', () async {
    await expectLater(
      captcha(
        (k, b) => Completer<String?>().future,
        timeout: const Duration(milliseconds: 20),
      ).token(),
      throwsA(isA<TimeoutFailure>()),
    );
  });

  test(
    'a retryable widget error is a network failure, the rest unknown',
    () async {
      await expectLater(
        captcha(
          (k, b) async =>
              throw const TurnstileException('net', retryable: true),
        ).token(),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(
        captcha((k, b) async => throw const TurnstileException('no')).token(),
        throwsA(isA<UnknownFailure>()),
      );
    },
  );

  test(
    'the site key is not baked into the app: it comes from the env file',
    () {
      expect(
        Env.turnstileSiteKey,
        isEmpty,
        reason: 'tests run with no env file',
      );
    },
  );
}
