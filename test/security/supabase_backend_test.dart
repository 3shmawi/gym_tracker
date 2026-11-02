import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards for the backend (docs/security.md → "Rules for new code").
/// The real proof is pgTAP in `supabase/tests/` and the Deno tests next to the
/// Edge Function; these keep a later migration or function from quietly
/// dropping the rules they rely on.
void main() {
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final sql = migrations.map((f) => f.readAsStringSync()).join('\n');

  // Created before the gym tables; anyone may read it by design.
  const publicReadTables = {'app_versions'};

  final tables = RegExp(r'create table (?:if not exists )?public\.(\w+)')
      .allMatches(sql)
      .map((m) => m.group(1)!)
      .toSet();

  test('there are migrations for the tables this test knows about', () {
    expect(
      tables,
      containsAll([
        'gyms',
        'people',
        'memberships',
        'invites',
        'invite_attempts',
        'plans',
      ]),
    );
  });

  test('every table has RLS enabled', () {
    for (final table in tables) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
        reason: '$table needs RLS',
      );
    }
  });

  test('every table has its pgTAP file', () {
    final tests = Directory('supabase/tests')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    for (final table in tables) {
      expect(
        tests.any((t) => t.startsWith('${table}_')),
        isTrue,
        reason: 'supabase/tests/${table}_rls.test.sql is missing',
      );
    }
  });

  test('anon and authenticated lose their default grants on every table', () {
    for (final table in tables.difference(publicReadTables)) {
      expect(
        sql,
        contains('revoke all on table public.$table from anon, authenticated'),
        reason: '$table keeps the default grants',
      );
    }
  });

  test('a security definer function pins its search_path', () {
    final functions = RegExp(
      r'create function ([\w.]+)\(.*?(?=create function |\Z)',
      dotAll: true,
    ).allMatches(sql);
    var definers = 0;
    for (final f in functions) {
      final body = f.group(0)!;
      if (!body.contains('security definer')) continue;
      definers++;
      expect(
        body,
        contains("set search_path = ''"),
        reason: '${f.group(1)} is security definer without a fixed search_path',
      );
    }
    expect(definers, greaterThan(10));
  });

  test('public functions that act as the table owner are closed to anon', () {
    final names = RegExp(r'create function (public\.\w+)\(')
        .allMatches(sql)
        .map((m) => m.group(1)!);
    final revokes = RegExp('revoke all on function[^;]*;')
        .allMatches(sql)
        .map((m) => m.group(0)!)
        .toList();
    for (final name in names) {
      expect(
        revokes.any((r) => r.contains('$name(') && r.contains('anon')),
        isTrue,
        reason: '$name must revoke execute from anon',
      );
    }
  });

  test(
    'the invite pepper is generated inside Postgres, never written down',
    () {
      final calls = RegExp(r'vault\.create_secret\(\s*([^,]+),');
      for (final m in calls.allMatches(sql)) {
        expect(
          m.group(1),
          contains('gen_random_bytes'),
          reason: 'a Vault secret in a migration must be random, not literal',
        );
      }
      // Only a hash is stored, and the code column does not exist.
      expect(sql, contains('code_hmac bytea not null unique'));
      expect(
        RegExp(r'\bcode text\b').hasMatch(
          sql.substring(
            sql.indexOf('create table public.invites'),
            sql.indexOf('alter table public.invites enable'),
          ),
        ),
        isFalse,
      );
    },
  );

  for (final name in ['redeem_invite', 'delete-account']) {
    group('Edge Function $name', () {
      final dir = Directory('supabase/functions/$name');
      // Its own files and the shared ones it imports.
      final sources =
          [
                ...dir.listSync().whereType<File>(),
                ...Directory('supabase/functions/_shared')
                    .listSync()
                    .whereType<File>(),
              ]
              .where(
                (f) => f.path.endsWith('.ts') && !f.path.endsWith('.test.ts'),
              )
              .toList();

      test('is deployed with JWT verification on', () {
        final config = File('supabase/config.toml').readAsStringSync();
        expect(
          config,
          matches(RegExp('\\[functions\\.$name\\][^\\[]*verify_jwt = true')),
        );
      });

      test('logs no request data, headers or tokens', () {
        for (final file in sources) {
          final text = file.readAsStringSync();
          expect(
            RegExp(r'console\.(log|info|debug|warn|trace|dir)').hasMatch(text),
            isFalse,
            reason: '${file.path} writes to the log',
          );
          // The only log lines are fixed texts plus a database error code.
          for (final m in RegExp(
            r'console\.error\(([^)]*)\)',
          ).allMatches(text)) {
            expect(
              m.group(1),
              isNot(matches(RegExp(r'\b(req|body|headers|code|token|ip)\b'))),
              reason: 'console.error must not print request data',
            );
          }
        }
      });

      test('reads no secret itself and does not widen access', () {
        for (final file in sources) {
          final text = file.readAsStringSync();
          expect(text, isNot(contains('Deno.env')), reason: file.path);
          expect(text, isNot(contains('Access-Control-Allow-Origin')));
          expect(text, isNot(contains('service_role')), reason: file.path);
        }
      });

      test('keeps its dependencies pinned and locked', () {
        final deno = File('${dir.path}/deno.json').readAsStringSync();
        expect(deno, matches(RegExp(r'npm:@supabase/server@\d+\.\d+\.\d+"')));
        expect(deno, matches(RegExp(r'jsr:@std/assert@\d+\.\d+\.\d+"')));
        expect(File('${dir.path}/deno.lock').existsSync(), isTrue);
      });
    });
  }

  test('invite cards and function secrets cannot be committed by accident', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('invites-*.pdf'));
    expect(ignore, contains('supabase/functions/.env'));
  });
}
