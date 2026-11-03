import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards for the gym account screens (docs/security.md → "Gym
/// accounts in the app"): where the session lives, what is sent to analytics,
/// what the scanner may do with a QR.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFiles(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

  final gymLib = dartFiles('lib/features/gym').toList();

  test('the session lives in secure storage, not in shared preferences', () {
    final backend = read('lib/core/backend/backend.dart');
    expect(backend, contains('localStorage: SecureLocalStorage('));
    expect(backend, contains('FlutterSecretStore()'));
    for (final file in dartFiles('lib/features/gym/data/datasources')) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:shared_preferences')),
        reason: '${file.path}: secrets never go to shared preferences',
      );
    }
    final secrets = read('lib/features/gym/data/datasources/secret_store.dart');
    expect(secrets, contains('first_unlock_this_device'));
  });

  test('the install id and the session are the only secrets stored', () {
    final keys = <String>{};
    for (final file in dartFiles('lib/features/gym/data/datasources')) {
      for (final m in RegExp(
        r"'(azm\.[a-z_.]+)'",
      ).allMatches(file.readAsStringSync())) {
        keys.add(m.group(1)!);
      }
    }
    expect(keys, {'azm.supabase.session', 'azm.install_id'});
  });

  test('nothing in the gym code prints or logs', () {
    for (final file in gymLib) {
      final text = file.readAsStringSync();
      for (final banned in ['print(', 'debugPrint(', 'developer.log(']) {
        expect(text, isNot(contains(banned)), reason: file.path);
      }
    }
  });

  test('analytics: only the agreed events, with fixed words as properties', () {
    final events = <String>{};
    final properties = <String>{};
    for (final file in dartFiles('lib')) {
      final text = file.readAsStringSync();
      if (!file.path.contains('features/gym')) continue;
      for (final m in RegExp(
        r"Analytics\.capture\(\s*'([a-z_]+)'(?:,\s*\{([^}]*)\})?",
      ).allMatches(text)) {
        events.add(m.group(1)!);
        for (final p in RegExp(
          r"(?:^|,)\s*'([a-z_]+)'\s*:",
        ).allMatches(m.group(2) ?? '')) {
          properties.add(p.group(1)!);
        }
      }
    }
    expect(events, {
      'gym_join_started',
      'gym_joined',
      'gym_join_failed',
      'gym_switched',
      'account_signed_out',
      'account_deleted',
      'solo_import_started',
      'solo_import_done',
      'solo_import_failed',
      'gym_plan_synced',
      'gym_plan_updated_shown',
      'gym_sessions_uploaded',
    });
    // `via`: scan | link | code. `reason`: a word. `to`: solo | gym. Never a
    // code, a name, an id or an email. Sync: booleans and counts only.
    expect(properties, {
      'via',
      'reason',
      'to',
      'replaced',
      'deferred',
      'count',
      'left',
    });
  });

  test('the scanner takes text only through InviteCode.fromScan', () {
    final page = read('lib/features/gym/presentation/scanner_page.dart');
    final camera = read('lib/features/gym/presentation/scanner_camera.dart');
    expect(page, contains('InviteCode.fromScan(raw)'));
    for (final banned in [
      'Uri.parse',
      'launchUrl',
      'canLaunchUrl',
      'url_launcher',
    ]) {
      expect(page, isNot(contains(banned)), reason: 'scanner_page: $banned');
      expect(
        camera,
        isNot(contains(banned)),
        reason: 'scanner_camera: $banned',
      );
    }
    expect(camera, contains('BarcodeFormat.qrCode'));
    expect(camera, isNot(contains('returnImage: true')));
    expect(camera, isNot(contains('analyzeImage')));
  });

  test('no gym screen opens a web address or another app', () {
    for (final file in gymLib) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('url_launcher')), reason: file.path);
      expect(text, isNot(contains('launchUrl')), reason: file.path);
    }
  });

  test('delete-account is called with exactly the agreed body', () {
    final repo = read(
      'lib/features/gym/data/repositories/supabase_account_repository.dart',
    );
    expect(repo, contains("'delete-account'"));
    expect(repo, contains("body: {'confirm': 'delete'}"));
  });

  test('redeem sends exactly the code and the install id', () {
    final repo = read(
      'lib/features/gym/data/repositories/supabase_gym_repository.dart',
    );
    expect(repo, contains("'redeem_invite'"));
    expect(
      repo,
      contains("body: {'code': code.value, 'install_id': installId}"),
    );
  });

  test('a code never reaches a log, a failure or a string', () {
    final controller = read(
      'lib/features/gym/presentation/join_controller.dart',
    );
    expect(controller, isNot(contains('code.value')));
    final entity = read('lib/features/gym/domain/entities/invite_code.dart');
    expect(entity, contains("'InviteCode(***)'"));
  });

  test('the router never joins, signs out or deletes by itself', () {
    final router = read('lib/core/router/app_router.dart');
    for (final banned in [
      'redeem(',
      'signOut(',
      'deleteAccount(',
      'signInAnonymously(',
    ]) {
      expect(router, isNot(contains(banned)), reason: banned);
    }
  });

  test('anonymous sign-in happens only when a code is redeemed', () {
    for (final file in dartFiles('lib')) {
      if (file.path.endsWith('supabase_gym_repository.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('signInAnonymously')),
        reason: '${file.path}: never at launch (solo users make no account)',
      );
    }
  });

  test('Turnstile: the site key comes from the env file, never the secret', () {
    final env = read('lib/core/config/env.dart');
    expect(env, contains("String.fromEnvironment('TURNSTILE_SITE_KEY')"));
    final di = read('lib/core/di/dependencies.dart');
    expect(di, contains('Env.turnstileSiteKey.isEmpty'));
    expect(di, contains('captchaToken:'));
    final example = read('env/example.json');
    expect(example, contains('"TURNSTILE_SITE_KEY": ""'));
    for (final file in dartFiles('lib')) {
      final text = file.readAsStringSync();
      expect(
        RegExp('0x4[A-Za-z0-9_-]{20,}').hasMatch(text),
        isFalse,
        reason: '${file.path}: a Turnstile key in source',
      );
      expect(text.toLowerCase(), isNot(contains('turnstile_secret')));
    }
  });

  test('the Turnstile origin is a domain of the website only', () {
    final captcha = read('lib/core/captcha/turnstile_captcha.dart');
    expect(captcha, contains("defaultBaseUrl = 'https://azmm.pages.dev'"));
    // The website's strict CSP must not open up for the widget.
    expect(
      read('website/_headers'),
      isNot(contains('challenges.cloudflare.com')),
    );
  });
}
