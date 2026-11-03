import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The picture library (docs/features/exercise_image_library.md): a public
/// table, a seed generated from a reviewed commit, and an upload script that
/// holds the only secret. These tests guard what must never drift.
void main() {
  final migration = File('supabase/migrations/0013_exercise_images.sql')
      .readAsStringSync();
  final seed = File('supabase/migrations/0014_exercise_images_seed.sql')
      .readAsStringSync();
  final upload = File('tool/exercise_images/upload.py').readAsStringSync();
  final build = File('tool/exercise_images/build.py').readAsStringSync();
  final ciBuild = File('tool/exercise_images/ci_build.sh').readAsStringSync();
  final workflow = File('.github/workflows/exercise-images.yml')
      .readAsStringSync();

  group('the table', () {
    test('RLS on, read-only for everyone, no write policy at all', () {
      expect(
        migration,
        contains(
          'alter table public.exercise_images enable row level security',
        ),
      );
      expect(
        migration,
        contains(
          'revoke all on table public.exercise_images from anon, authenticated',
        ),
      );
      expect(
        migration,
        contains(
          'grant select on table public.exercise_images to anon, authenticated',
        ),
      );
      expect(migration, isNot(contains('for insert')));
      expect(migration, isNot(contains('for update')));
      expect(migration, isNot(contains('for delete')));
      expect(migration, isNot(contains('for all')));
    });

    test('only licences we may use in a commercial app are accepted', () {
      final allowed = RegExp(r'license in \(([^)]*)\)')
          .firstMatch(migration)!
          .group(1)!;
      expect(allowed, isNot(contains('NC')));
      expect(allowed, isNot(contains('ND')));
      for (final licence in ['CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-4.0']) {
        expect(allowed, contains(licence));
      }
    });

    test('the public id is a plain path under exercises', () {
      expect(migration, contains(r"'^exercises/[a-z0-9-]+$'"));
    });
  });

  group('the seed', () {
    final rows = RegExp(
      r"^\s+\('exercises/(ek-\d{4})-(tension|relaxation)'",
      multiLine: true,
    ).allMatches(seed).toList();

    test('is one idempotent statement from the reviewed commit', () {
      final commit = RegExp('SOURCE_COMMIT = "([0-9a-f]{40})"')
          .firstMatch(build)!
          .group(1)!;
      expect(rows.length, greaterThan(500));
      expect(RegExp(';').allMatches(seed).length, 1);
      expect(seed.trimRight(), endsWith(';'));
      expect(seed, contains('on conflict (public_id) do update'));
      expect(
        RegExp("'$commit'").allMatches(seed).length,
        rows.length,
        reason: 'every row names the commit it was built from',
      );
    });

    test('every row has the licence, author and a CC BY-SA attribution', () {
      expect(
        RegExp(r"'CC-BY-SA-4.0', 'Everkinetic \(Greg Priday\)'")
            .allMatches(seed)
            .length,
        rows.length,
      );
      expect(
        RegExp(r'CC BY-SA 4\.0\. Changed: made transparent, resized\.')
            .allMatches(seed)
            .length,
        rows.length,
      );
    });

    test('keywords are in English and Arabic, and nothing else sneaks in', () {
      expect(seed, contains(RegExp('[؀-ۿ]')), reason: 'Arabic words');
      expect(seed, contains("array['"));
      // No comment markers or statements smuggled into the data.
      final data = seed
          .split('\n')
          .where((l) => !l.startsWith('--'))
          .join('\n');
      expect(data, isNot(contains('--')));
      expect(data, isNot(contains('/*')));
      expect(data.toLowerCase(), isNot(contains('drop ')));
    });

    test('each exercise has both frames or one, never a stray id', () {
      final keys = rows.map((m) => m.group(1)).toSet();
      expect(keys.length, greaterThan(250));
      expect(keys.length, lessThanOrEqualTo(rows.length));
    });
  });

  group('the tool and the workflow keep the secret secret', () {
    test('the secret is read only from the environment and never printed', () {
      expect(upload, contains('os.environ.get("CLOUDINARY_API_SECRET"'));
      for (final line in upload.split('\n')) {
        if (line.contains('print(')) {
          expect(line, isNot(contains('secret')), reason: line);
          expect(line, isNot(contains('key}')), reason: line);
        }
      }
      expect(upload, contains('replace(credential, "***")'));
      expect(ciBuild, isNot(contains('set -x')));
      expect(upload, isNot(contains('set -x')));
    });

    test('it never reads the other source folders', () {
      final code = build
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('#') && !t.startsWith('"""');
          })
          .join('\n');
      expect(code, contains('"src" / "exercises"'));
      expect(code, isNot(contains('images-ai"')));
      expect(code, isNot(contains('images-png-unknown"')));
    });

    test(
      'the upload job is manual, in an environment, and secrets come by env',
      () {
        expect(workflow, contains('environment: cloudinary'));
        expect(
          workflow,
          contains("github.event_name == 'workflow_dispatch' && inputs.upload"),
        );
        expect(workflow, isNot(contains('pull_request_target')));
        expect(workflow, contains('permissions:\n  contents: read'));
        expect(workflow, contains('persist-credentials: false'));
        // The pull request run (build + validate) names no secret at all.
        final packageJob = workflow.substring(
          workflow.indexOf('\n  package:\n'),
          workflow.indexOf('\n  upload:\n'),
        );
        expect(packageJob, isNot(contains('secrets.')));
      },
    );
  });

  group('the upload script refuses hostile input', () {
    late Directory dir;
    late bool hasPython;

    setUpAll(() async {
      hasPython = (await Process.run('python3', ['--version'])).exitCode == 0;
    });

    setUp(() => dir = Directory.systemTemp.createTempSync('azm_pkg'));
    tearDown(() => dir.deleteSync(recursive: true));

    String package({
      String publicId = 'exercises/ek-0001-tension',
      String license = 'CC-BY-SA-4.0',
      int copies = 1,
      bool file = true,
    }) {
      final row = {
        'public_id': publicId,
        'exercise_key': 'ek-0001',
        'frame': 'tension',
      };
      File('${dir.path}/images.json').writeAsStringSync(
        jsonEncode({
          'sourceCommit': 'x',
          'license': license,
          'images': List.filled(copies, row),
        }),
      );
      Directory('${dir.path}/png').createSync();
      if (file) {
        File('${dir.path}/png/ek-0001-tension.png').writeAsBytesSync([0]);
      }
      return dir.path;
    }

    Future<ProcessResult> dryRun(
      String package, {
      String cloud = 'demo-cloud',
    }) => Process.run(
      'python3',
      [
        '-I',
        'tool/exercise_images/upload.py',
        '--package',
        package,
        '--dry-run',
      ],
      environment: {'CLOUDINARY_CLOUD_NAME': cloud},
    );

    test('a good package passes the dry run and sends nothing', () async {
      if (!hasPython) return;
      final result = await dryRun(package());
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Dry run: nothing was sent'));
    });

    test('crafted public ids, licences, duplicates, missing files', () async {
      if (!hasPython) return;
      final bad = <String Function()>[
        () => package(publicId: '../../evil'),
        () => package(publicId: 'exercises/../x'),
        () => package(publicId: 'azm/exercises/ek-0001-tension'),
        () => package(publicId: 'other/folder/x'),
        () => package(publicId: 'exercises/UPPER'),
        () => package(license: 'CC-BY-NC-4.0'),
        () => package(license: 'CC-BY-ND-4.0'),
        () => package(license: ''),
        () => package(copies: 2),
        () => package(file: false),
      ];
      for (final make in bad) {
        // A fresh folder each time: one bad thing per package.
        for (final f in dir.listSync()) {
          f.deleteSync(recursive: true);
        }
        final path = make();
        final result = await dryRun(path);
        expect(
          result.exitCode,
          isNot(0),
          reason: File('$path/images.json').readAsStringSync(),
        );
      }
    });

    test('a cloud name that is not a plain name is refused', () async {
      if (!hasPython) return;
      for (final cloud in [
        '',
        '../x',
        'a b',
        'UPPER',
        'a/b',
        'x;y',
        'a\nb',
        'x' * 80,
      ]) {
        final result = await dryRun(package(), cloud: cloud);
        expect(result.exitCode, isNot(0), reason: 'cloud "$cloud"');
      }
    });

    test(
      'a real upload without the credentials stops before any request',
      () async {
        if (!hasPython) return;
        final result = await Process.run(
          'python3',
          ['-I', 'tool/exercise_images/upload.py', '--package', package()],
          environment: {'CLOUDINARY_CLOUD_NAME': 'demo-cloud'},
        );
        expect(result.exitCode, isNot(0));
        expect('${result.stdout}${result.stderr}', contains('must be set'));
      },
    );
  });
}
