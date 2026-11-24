@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The scripts behind Actions → Announce update's daily run:
/// store_live.sh against fake stores (a `curl` on PATH that answers from the
/// FAKE_* variables — no network, no keys), announce_plan.sh and
/// whats_new.sh.
void main() {
  late Directory bin;

  setUpAll(() {
    bin = Directory.systemTemp.createTempSync('store_live_');
    File('${bin.path}/curl').writeAsStringSync(r'''
#!/usr/bin/env bash
out=/dev/stdout; method=GET; url=
while [ $# -gt 0 ]; do
  case $1 in
    -o) out=$2; shift ;;
    -X) method=$2; shift ;;
    -w|-H) shift ;;
    http*) url=$1 ;;
  esac
  shift
done
echo "$method $url" >> "$FAKE_LOG"
case "$method $url" in
  "POST "*/edits) body='{"id":"e1"}'; code=${FAKE_PLAY_CODE:-200} ;;
  "GET "*/tracks/production) body=$FAKE_PLAY_TRACK; code=200 ;;
  "DELETE "*) body=''; code=204 ;;
  "GET https://itunes.apple.com/"*) body=$FAKE_ITUNES; code=200 ;;
  *) body='{}'; code=404 ;;
esac
printf '%s' "$body" > "$out"
printf '%s' "$code"
''');
    Process.runSync('chmod', ['+x', '${bin.path}/curl']);
  });

  tearDownAll(() => bin.deleteSync(recursive: true));

  Future<({String out, String err, String log})> run(
    Map<String, String> env,
  ) async {
    final log = File('${bin.path}/log')..writeAsStringSync('');
    final result = await Process.run(
      'bash',
      ['scripts/store_live.sh'],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'PACKAGE_ID': 'com.example.app',
        'PLAY_TOKEN': 'test-token',
        'FAKE_LOG': log.path,
        ...env,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (
      out: (result.stdout as String).trim(),
      err: result.stderr as String,
      log: log.readAsStringSync(),
    );
  }

  String track(List<Map<String, String>> releases) =>
      jsonEncode({'track': 'production', 'releases': releases});
  String itunes(String? version) => version == null
      ? '{"resultCount":0,"results":[]}'
      : '{"resultCount":1,"results":[{"version":"$version"}]}';

  test('live in both stores → the lower version', () async {
    final r = await run({
      'FAKE_PLAY_TRACK': track([
        {'name': '45 (1.3.0)', 'status': 'completed'},
      ]),
      'FAKE_ITUNES': itunes('1.2.0'),
    });
    expect(r.out, '1.2.0');
    // The Play edit is opened read-only and thrown away.
    expect(r.log, contains('DELETE '));
  });

  test('a staged rollout or a draft is not live', () async {
    final r = await run({
      'FAKE_PLAY_TRACK': track([
        {'name': '1.3.0', 'status': 'inProgress'},
        {'name': '1.4.0', 'status': 'draft'},
        {'name': '1.2.0', 'status': 'completed'},
      ]),
      'FAKE_ITUNES': itunes('1.3.0'),
    });
    expect(r.out, '1.2.0');
  });

  test('not on the App Store yet → nothing', () async {
    final r = await run({
      'FAKE_PLAY_TRACK': track([
        {'name': '1.3.0', 'status': 'completed'},
      ]),
      'FAKE_ITUNES': itunes(null),
    });
    expect(r.out, isEmpty);
  });

  test('Play API refuses → a warning and nothing, never an error', () async {
    final r = await run({
      'FAKE_PLAY_CODE': '403',
      'FAKE_ITUNES': itunes('1.3.0'),
    });
    expect(r.out, isEmpty);
    expect(r.err, contains('::warning::'));
    expect(r.err, isNot(contains('test-token')));
  });

  test('ENABLE_ANDROID=false checks the App Store only', () async {
    final r = await run({
      'ENABLE_ANDROID': 'false',
      'FAKE_ITUNES': itunes('2.0.1'),
    });
    expect(r.out, '2.0.1');
    expect(r.log, isNot(contains('androidpublisher')));
  });

  test('hostile store text never becomes a version', () async {
    final r = await run({
      'ENABLE_ANDROID': 'false',
      'FAKE_ITUNES': itunes(r'1.2.0; rm -rf / $(id)'),
    });
    expect(r.out, '1.2.0');
  });

  group('announce_plan.sh', () {
    Future<String> plan(List<String> args, [Map<String, String>? env]) async {
      final r = await Process.run('bash', [
        'scripts/announce_plan.sh',
        ...args,
      ], environment: env);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return (r.stdout as String).trim();
    }

    test('newer than what both platforms announce → both', () async {
      expect(await plan(['1.2.0', '1.1.0', '1.1.9']), 'both');
      expect(await plan(['1.10.0', '1.9.0', '']), 'both');
    });

    test('never repeats or downgrades a notice', () async {
      expect(await plan(['1.2.0', '1.2.0', '1.1.0']), 'ios');
      expect(await plan(['1.2.0', '1.3.0', '1.2.0']), isEmpty);
    });

    test('ENABLE_IOS=false leaves iOS out', () async {
      expect(
        await plan(['1.2.0', '1.1.0', '1.1.0'], {'ENABLE_IOS': 'false'}),
        'android',
      );
    });

    test('refuses a live version that is not x.y.z', () async {
      final r = await Process.run('bash', [
        'scripts/announce_plan.sh',
        r'1.2.0$(id)',
        '1.0.0',
        '1.0.0',
      ]);
      expect(r.exitCode, isNot(0));
    });
  });

  group('whats_new.sh', () {
    late Directory repo;

    Future<void> git(List<String> args) async {
      final r = await Process.run('git', [
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@example.com',
        ...args,
      ], workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('whats_new_');
      Directory('${repo.path}/scripts').createSync();
      for (final name in ['whats_new.sh', 'release_notes.sh']) {
        File('scripts/$name').copySync('${repo.path}/scripts/$name');
      }
      await git(['init', '-q']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    Future<void> release(String tag, Map<String, String> files) async {
      files.forEach((path, text) {
        File('${repo.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      });
      await git(['add', '-A']);
      await git(['commit', '-qm', 'feat: faster search']);
      await git(['tag', tag]);
    }

    Future<String> whatsNew(String tag, String lang) async {
      final r = await Process.run('bash', [
        'scripts/whats_new.sh',
        tag,
        lang,
      ], workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return (r.stdout as String).trim();
    }

    const en = 'store/android/en-US/changelogs/default.txt';
    const ar = 'store/android/ar/changelogs/default.txt';

    test('uses the store "What\'s new" of that release', () async {
      await release('v1.1.0', {en: '- Dark mode\n', ar: '- الوضع الداكن\n'});
      expect(await whatsNew('v1.1.0', 'en'), '- Dark mode');
      expect(await whatsNew('v1.1.0', 'ar'), '- الوضع الداكن');
    });

    test('placeholders fall back to the commits (English only)', () async {
      await release('v1.1.0', {
        en: 'Feature one: TODO what changed',
        ar: 'اكتب هنا: إيه الجديد',
      });
      expect(await whatsNew('v1.1.0', 'en'), '• Faster search');
      expect(await whatsNew('v1.1.0', 'ar'), isEmpty);
    });
  });
}
