import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';

ExerciseImageManifest loadManifest() => ExerciseImageManifest.parse(
  File(ExerciseImages.manifestAsset).readAsStringSync(),
);

String json({String license = 'CC-BY-SA-4.0', Object? modified = true}) =>
    '''
{
  "adaptedLicense": "CC-BY-SA-4.0",
  "adaptedLicenseUrl": "https://creativecommons.org/licenses/by-sa/4.0/",
  "images": [
    {
      "exercise": "abs", "file": "assets/exercises/abs.webp",
      "thumb": "assets/exercises/abs_thumb.webp", "title": "Crunches",
      "sourceUrl": "https://example.org/a.png", "sourceFile": "a.png",
      "license": "$license", "licenseUrl": "https://example.org/l",
      "author": "A", "dateChecked": "2026-11-03",
      "licenseEvidence": ["https://example.org/e"], "modified": $modified,
      "modification": "x", "attribution": "y"
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest = loadManifest();
  final catalogIds = ExerciseCatalog.all.map((e) => e.id).toSet();

  group('bundled pictures', () {
    test('the available ids, the manifest and the files agree', () {
      final ids = manifest.images.map((i) => i.exercise).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate entry');
      expect(ids.toSet(), ExerciseImages.available);
      final files = Directory(ExerciseImages.directory)
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.webp'))
          .toSet();
      expect(files, {
        for (final id in ids) ...['$id.webp', '${id}_thumb.webp'],
      });
    });

    test('every library exercise has a picture or the placeholder', () {
      // No picture for an id the library does not have.
      expect(ExerciseImages.available.difference(catalogIds), isEmpty);
      for (final id in catalogIds) {
        if (!ExerciseImages.has(id)) continue;
        for (final path in [
          ExerciseImages.large(id),
          ExerciseImages.thumb(id),
        ]) {
          final bytes = File(path).readAsBytesSync();
          // A real WebP file: RIFF....WEBP
          expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
          expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
        }
        expect(
          File(ExerciseImages.thumb(id)).lengthSync(),
          lessThan(File(ExerciseImages.large(id)).lengthSync()),
        );
      }
    });

    test('every picture has a complete manifest entry', () {
      for (final i in manifest.images) {
        final reason = i.exercise;
        for (final value in [
          i.title,
          i.sourceUrl,
          i.sourceFile,
          i.license,
          i.licenseUrl,
          i.author,
          i.modification,
          i.attribution,
        ]) {
          expect(value.trim(), isNotEmpty, reason: reason);
        }
        expect(i.file, ExerciseImages.large(i.exercise), reason: reason);
        expect(i.thumb, ExerciseImages.thumb(i.exercise), reason: reason);
        expect(i.dateChecked, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(DateTime.tryParse(i.dateChecked), isNotNull, reason: reason);
        for (final url in [i.sourceUrl, i.licenseUrl, ...i.licenseEvidence]) {
          expect(url, startsWith('https://'), reason: reason);
        }
        expect(i.licenseEvidence, isNotEmpty, reason: reason);
        // We change every picture, so the change is stated.
        expect(i.modified, isTrue, reason: reason);
        // The attribution names the work, the author and the licence.
        expect(i.attribution, contains(i.title), reason: reason);
        expect(i.attribution, contains(i.author.split(' ').first));
        final spdx = RegExp(r'^CC-(.+)-(\d\.\d)$').firstMatch(i.license)!;
        expect(
          i.attribution,
          contains('CC ${spdx[1]} ${spdx[2]}'),
          reason: reason,
        );
      }
    });

    test('pictures of a similar exercise are marked, with a note', () {
      final substitutes = {
        for (final i in manifest.images)
          if (i.substitute) i.exercise,
      };
      // Docs: docs/features/exercise_images.md. Change both together.
      expect(substitutes, {
        'reverse_pec_deck',
        'cable_kickback',
        'reverse_wrist_curl',
        'barbell_wrist_curl',
      });
      for (final i in manifest.images) {
        expect(i.substituteNote.isNotEmpty, i.substitute, reason: i.exercise);
      }
    });

    test('no entry has a licence we may not use in a store app', () {
      for (final i in manifest.images) {
        expect(
          ExerciseImageManifest.allowedLicenses,
          contains(i.license),
          reason: '${i.exercise}: ${i.license}',
        );
        expect(i.license, isNot(matches(RegExp('-N[CD]-|unknown'))));
      }
      expect(manifest.adaptedLicense, 'CC-BY-SA-4.0');
    });
  });

  group('the manifest reader', () {
    test('reads a good manifest', () {
      expect(ExerciseImageManifest.parse(json()).images.single.exercise, 'abs');
    });

    test('a non-commercial or no-derivatives licence is not allowed', () {
      for (final bad in [
        'CC-BY-NC-4.0',
        'CC-BY-ND-4.0',
        'CC-BY-NC-SA-4.0',
        'unknown',
        '',
        'All rights reserved',
      ]) {
        final entry = ExerciseImageManifest.parse(json(license: bad));
        expect(
          ExerciseImageManifest.allowedLicenses,
          isNot(contains(entry.images.single.license)),
          reason: bad,
        );
      }
    });

    test('broken, hostile or wrong-typed input is refused, not crashed on', () {
      for (final bad in [
        '',
        'not json',
        '[]',
        '{}',
        '{"images": 1, "adaptedLicense": "x", "adaptedLicenseUrl": "y"}',
        json(modified: '"yes"'),
        json().replaceAll(
          '"modified": true,',
          '"modified": true, "substitute": 1,',
        ),
        json().replaceAll('"author": "A",', ''),
        json().replaceAll('"title": "Crunches"', '"title": 5'),
        '{"adaptedLicense":"x","adaptedLicenseUrl":"y","images":[1]}',
      ]) {
        expect(
          () => ExerciseImageManifest.parse(bad),
          throwsA(isA<FormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('the licenses page', () {
    test('lists every required attribution and the licence links', () async {
      ExerciseImages.registerLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final ours = entries.where(
        (e) => e.packages.contains('Exercise illustrations'),
      );
      expect(ours, hasLength(1));
      final text = ours.single.paragraphs.map((p) => p.text).join('\n');
      for (final i in manifest.images) {
        expect(text, contains(i.attribution), reason: i.exercise);
      }
      expect(text, contains('https://creativecommons.org/licenses/by-sa/4.0/'));
      expect(text, contains('https://creativecommons.org/licenses/by-sa/3.0/'));
      expect(text, contains('We changed them'));
    });

    test('lists the gym picture library once: author, source, licence, '
        'changes', () async {
      ExerciseImages.registerLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final library = entries.where(
        (e) => e.packages.contains('Exercise picture library (Everkinetic)'),
      );
      // registerLicenses ran twice in this file: one entry per call.
      expect(library, isNotEmpty);
      final text = library.first.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Everkinetic (Greg Priday)'));
      expect(text, contains('https://github.com/everkinetic/data'));
      expect(text, contains('CC BY-SA 4.0'));
      expect(text, contains('https://creativecommons.org/licenses/by-sa/4.0/'));
      expect(text, contains('Changed:'));
    });
  });
}
