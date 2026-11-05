import 'dart:async';

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

  test(
    'a widget that never answers is a reported failure, not a retry',
    () async {
      await expectLater(
        captcha(
          (k, b) => Completer<String?>().future,
          timeout: const Duration(milliseconds: 20),
        ).token(),
        throwsA(
          isA<UnknownFailure>().having(
            (f) => '${f.cause}',
            'cause',
            contains('timed out'),
          ),
        ),
      );
    },
  );

  test('the failure says what the web view saw', () async {
    await expectLater(
      captcha((k, b) async {
        TurnstileCaptcha.lastNote = 'error 110200';
        return null;
      }).token(),
      throwsA(
        isA<UnknownFailure>().having(
          (f) => '${f.cause}',
          'cause',
          'turnstile: no token (error 110200)',
        ),
      ),
    );
  });

  test('waits less than the join itself (guard, 20 s)', () {
    expect(
      const TurnstileCaptcha(siteKey: 'site').timeout,
      lessThan(const Duration(seconds: 20)),
    );
  });

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
